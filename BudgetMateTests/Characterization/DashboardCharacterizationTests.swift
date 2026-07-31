import XCTest
@testable import BudgetMate

@MainActor
final class DashboardCharacterizationTests: XCTestCase {
    func testDashboardTotalsIncludeIncomeExpensesAndRemainingBudget() {
        let transactions = [
            BudgetMateTestFixtures.income(amount: 2_500),
            BudgetMateTestFixtures.expense(amount: 120),
            BudgetMateTestFixtures.expense(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000106")!,
                title: "Transport",
                amount: 80,
                category: .transportation
            )
        ]

        let totals = DashboardViewModel.totals(
            transactions: transactions,
            monthlyBudget: 500
        )

        XCTAssertEqual(totals.totalIncome, 2_500, accuracy: 0.001)
        XCTAssertEqual(totals.totalExpenses, 200, accuracy: 0.001)
        XCTAssertEqual(totals.currentBalance, 2_300, accuracy: 0.001)
        XCTAssertEqual(totals.remainingBudget, 300, accuracy: 0.001)
    }

    func testDashboardMemberFilterAttributesIncomeAndSplitSharesToMember() {
        let regularExpense = BudgetMateTestFixtures.expense(amount: 50, payerId: BudgetMateTestFixtures.aliceMemberID)
        let splitExpense = BudgetMateTestFixtures.customSplitExpense(amount: 90, payerId: BudgetMateTestFixtures.aliceMemberID)
        let transactions = [
            BudgetMateTestFixtures.income(amount: 100, memberId: BudgetMateTestFixtures.aliceMemberID),
            BudgetMateTestFixtures.income(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000107")!,
                amount: 200,
                memberId: BudgetMateTestFixtures.bobMemberID
            ),
            regularExpense,
            splitExpense
        ]

        let aliceTotals = DashboardViewModel.totals(
            transactions: transactions,
            monthlyBudget: 500,
            forMember: BudgetMateTestFixtures.aliceMemberID
        )
        let bobTotals = DashboardViewModel.totals(
            transactions: transactions,
            monthlyBudget: 500,
            forMember: BudgetMateTestFixtures.bobMemberID
        )

        XCTAssertEqual(aliceTotals.totalIncome, 100, accuracy: 0.001)
        XCTAssertEqual(aliceTotals.totalExpenses, 86, accuracy: 0.001)
        XCTAssertEqual(aliceTotals.currentBalance, 14, accuracy: 0.001)
        XCTAssertEqual(bobTotals.totalIncome, 200, accuracy: 0.001)
        XCTAssertEqual(bobTotals.totalExpenses, 54, accuracy: 0.001)
        XCTAssertEqual(bobTotals.currentBalance, 146, accuracy: 0.001)
    }

    func testCategorySpendingIncludesOnlyExpensesAndUsesMemberShareWhenFiltered() {
        let transactions = [
            BudgetMateTestFixtures.income(amount: 500),
            BudgetMateTestFixtures.expense(amount: 120, category: .groceries),
            BudgetMateTestFixtures.expense(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000108")!,
                title: "Train",
                amount: 40,
                category: .transportation
            ),
            BudgetMateTestFixtures.customSplitExpense(amount: 90)
        ]

        let allMembers = DashboardViewModel.expenseBreakdown(transactions: transactions)
        let bobOnly = DashboardViewModel.expenseBreakdown(
            transactions: transactions,
            forMember: BudgetMateTestFixtures.bobMemberID
        )

        let allAmounts = Dictionary(uniqueKeysWithValues: allMembers.map { ($0.category, $0.amount) })
        let bobAmounts = Dictionary(uniqueKeysWithValues: bobOnly.map { ($0.category, $0.amount) })
        XCTAssertEqual(allAmounts[.groceries] ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(allAmounts[.transportation] ?? 0, 40, accuracy: 0.001)
        XCTAssertEqual(allAmounts[.bills] ?? 0, 90, accuracy: 0.001)
        XCTAssertEqual(bobAmounts[.bills] ?? 0, 54, accuracy: 0.001)
        XCTAssertNil(bobAmounts[.groceries])
    }

    func testEqualSplitResolutionUsesCentsAndGivesRemainderToStableLeadingParticipants() throws {
        let viewModel = AddTransactionViewModel()
        viewModel.isSplit = true
        viewModel.splitMethod = .equally
        viewModel.amountText = "10.01"
        viewModel.participants = [BudgetMateTestFixtures.aliceMemberID, BudgetMateTestFixtures.bobMemberID, BudgetMateTestFixtures.carolMemberID]

        let resolved = try XCTUnwrap(viewModel.resolvedSplits(payerId: BudgetMateTestFixtures.bobMemberID))
        let amounts = Dictionary(uniqueKeysWithValues: resolved.map { ($0.memberId, $0.amount) })

        XCTAssertEqual(amounts[BudgetMateTestFixtures.bobMemberID] ?? 0, 3.34, accuracy: 0.001)
        XCTAssertEqual(amounts[BudgetMateTestFixtures.aliceMemberID] ?? 0, 3.34, accuracy: 0.001)
        XCTAssertEqual(amounts[BudgetMateTestFixtures.carolMemberID] ?? 0, 3.33, accuracy: 0.001)
        XCTAssertEqual(resolved.reduce(0) { $0 + $1.amount }, 10.01, accuracy: 0.001)
    }

    func testExactMoneyLocalTransactionAndSplitMaterialization() throws {
        let viewModel = AddTransactionViewModel()
        viewModel.title = "CAD groceries"
        viewModel.amountText = "10.01"
        viewModel.isSplit = true
        viewModel.splitMethod = .equally
        viewModel.participants = [
            BudgetMateTestFixtures.aliceMemberID,
            BudgetMateTestFixtures.bobMemberID,
            BudgetMateTestFixtures.carolMemberID
        ]

        let transaction = try XCTUnwrap(
            viewModel.buildTransaction(
                addedBy: BudgetMateTestFixtures.alice,
                currencyCode: "CAD"
            )
        )
        XCTAssertEqual(transaction.amountMinorUnits, 1001)
        XCTAssertEqual(transaction.currencyCode, "CAD")

        let shares = try XCTUnwrap(
            viewModel.resolvedSplits(
                payerId: BudgetMateTestFixtures.aliceMemberID,
                currencyCode: "CAD"
            )
        )
        XCTAssertEqual(shares[0].amount, 3.34, accuracy: 0.0001)
        XCTAssertEqual(shares[1].amount, 3.34, accuracy: 0.0001)
        XCTAssertEqual(shares[2].amount, 3.33, accuracy: 0.0001)
    }

    func testCategoryBreakdownIsReadOnlyScopedToExpenseMonthAndBudget() throws {
        let scope = BudgetMateTestFixtures.sharedBudgetID.uuidString
        let january = BudgetMateTestFixtures.makeDate(year: 2025, month: 1, day: 15)
        let interval = try XCTUnwrap(BudgetMateTestFixtures.utcCalendar.dateInterval(of: .month, for: january))
        let inScope = BudgetMateTestFixtures.expense(
            title: "Groceries",
            amount: 12.34,
            category: .groceries,
            date: january
        )
        let income = BudgetMateTestFixtures.income(amount: 999)
        let otherScope = BudgetMateTestFixtures.expense(
            title: "Other household",
            amount: 88,
            category: .groceries,
            date: january
        )
        otherScope.ownerUserId = BudgetMateTestFixtures.personalBudgetID.uuidString

        let metrics = BudgetTabMetrics.compute(
            transactions: [inScope, income, otherScope],
            settlements: [],
            members: [],
            monthInterval: interval,
            currencyCode: "CAD",
            budgetScopeId: scope
        )
        let breakdown = metrics.categoryBreakdown(
            for: .groceries,
            budgetScopeId: scope,
            currencyCode: "CAD"
        )

        XCTAssertEqual(breakdown.transactions.map(\.id), [inScope.id])
        XCTAssertEqual(breakdown.total, 12.34, accuracy: 0.001)
    }

    func testMonthSelectionMovesAcrossYearBoundaryUsingItsCalendarTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2024, month: 12, day: 15, hour: 12))
        )
        let store = MonthSelectionStore(calendar: calendar, referenceDate: referenceDate)

        XCTAssertEqual(store.selectedMonthKey, "2024-12")
        store.moveMonth(by: 1)
        XCTAssertEqual(store.selectedMonthKey, "2025-01")
        XCTAssertEqual(store.selectedYear, 2025)
        XCTAssertEqual(store.selectedMonthIndex, 0)

        store.moveMonth(by: -1)
        XCTAssertEqual(store.selectedMonthKey, "2024-12")
        XCTAssertEqual(store.selectedMonthTitle, "December 2024")
    }

    func testCustomSplitValidationRequiresTheEnteredSharesToMatchTotal() {
        let viewModel = AddTransactionViewModel()
        viewModel.isSplit = true
        viewModel.splitMethod = .custom
        viewModel.amountText = "100.00"
        viewModel.participants = [BudgetMateTestFixtures.aliceMemberID, BudgetMateTestFixtures.bobMemberID]
        viewModel.customAmounts = [
            BudgetMateTestFixtures.aliceMemberID: "40.00",
            BudgetMateTestFixtures.bobMemberID: "60.00"
        ]

        XCTAssertTrue(viewModel.isSplitValid)
        XCTAssertNil(viewModel.splitValidationMessage(currencyCode: "CAD", locale: Locale(identifier: "en_CA")))

        viewModel.updateCustomAmount("59.98", for: BudgetMateTestFixtures.bobMemberID)
        XCTAssertFalse(viewModel.isSplitValid)
        let addMoreMessage = viewModel.splitValidationMessage(
            currencyCode: "CAD",
            locale: Locale(identifier: "en_CA")
        )
        XCTAssertEqual(addMoreMessage, "Add $0.02 more to match the total.")
        XCTAssertTrue(addMoreMessage?.contains("$") ?? false)
        XCTAssertFalse(addMoreMessage?.contains("CAD") ?? true)
        XCTAssertFalse(addMoreMessage?.contains("CA$") ?? true)

        viewModel.updateCustomAmount("60.02", for: BudgetMateTestFixtures.bobMemberID)
        let overTotalMessage = viewModel.splitValidationMessage(
            currencyCode: "CAD",
            locale: Locale(identifier: "fr_CA")
        )
        XCTAssertEqual(overTotalMessage, "That's 0,02\u{00A0}$ over the total.")
        XCTAssertTrue(overTotalMessage?.contains("$") ?? false)
        XCTAssertFalse(overTotalMessage?.contains("CAD") ?? true)
        XCTAssertFalse(overTotalMessage?.contains("CA$") ?? true)
    }

    func testCustomSplitValidationKeepsNonCADCurrencyIdentity() {
        let viewModel = AddTransactionViewModel()
        viewModel.isSplit = true
        viewModel.splitMethod = .custom
        viewModel.amountText = "100.00"
        viewModel.participants = [BudgetMateTestFixtures.aliceMemberID, BudgetMateTestFixtures.bobMemberID]
        viewModel.customAmounts = [
            BudgetMateTestFixtures.aliceMemberID: "40.00",
            BudgetMateTestFixtures.bobMemberID: "59.98"
        ]

        let message = viewModel.splitValidationMessage(
            currencyCode: "EUR",
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(message, "Add €0.02 more to match the total.")
    }

    func testSettlementSuggestionsNetOpposingSplitBills() {
        let alicePaid = BudgetMateTestFixtures.equalSplitExpense(amount: 100, payerId: BudgetMateTestFixtures.aliceMemberID)
        let bobPaid = BudgetMateTestFixtures.equalSplitExpense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000109")!,
            amount: 60,
            payerId: BudgetMateTestFixtures.bobMemberID
        )

        let suggestions = DashboardViewModel.settlements(
            transactions: [alicePaid, bobPaid],
            members: [BudgetMateTestFixtures.alice, BudgetMateTestFixtures.bob]
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.from.id, BudgetMateTestFixtures.bobMemberID)
        XCTAssertEqual(suggestions.first?.to.id, BudgetMateTestFixtures.aliceMemberID)
        XCTAssertEqual(suggestions.first?.amount ?? 0, 20, accuracy: 0.001)
    }

    func testSettlementBreakdownExplainsSharesAndRecordedSettlement() {
        let expense = BudgetMateTestFixtures.equalSplitExpense(amount: 100, payerId: BudgetMateTestFixtures.aliceMemberID)
        let settlement = BudgetMateTestFixtures.settlement(amount: 20)

        let items = DashboardViewModel.breakdown(
            from: BudgetMateTestFixtures.bob,
            to: BudgetMateTestFixtures.alice,
            transactions: [expense],
            settlements: [settlement]
        )

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.filter { $0.kind == .debtorShare }.map(\.signedAmount), [50])
        XCTAssertEqual(items.filter { $0.kind == .settlement }.map(\.signedAmount), [-20])
        XCTAssertEqual(items.reduce(0) { $0 + $1.signedAmount }, 30, accuracy: 0.001)
    }

    func testDuplicateRowsKeepTheFirstStableIdentifierOccurrence() throws {
        let first = BudgetMateTestFixtures.expense(amount: 25)
        let duplicate = BudgetMateTestFixtures.expense(amount: 999)

        let result = [first, duplicate].deduplicatedByID()

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, first.id)
        XCTAssertEqual(try XCTUnwrap(result.first?.amount), 25, accuracy: 0.001)
    }

    func testJPYInputNormalizesFractionalTextAndPreservesExactShares() throws {
        let viewModel = AddTransactionViewModel()
        viewModel.title = "Yen dinner"
        viewModel.amountText = "100.5"
        viewModel.isSplit = true
        viewModel.splitMethod = .equally
        viewModel.participants = [BudgetMateTestFixtures.aliceMemberID, BudgetMateTestFixtures.bobMemberID]
        viewModel.updateAmountText("100.5", currencyCode: "JPY")

        XCTAssertEqual(viewModel.amountText, "100")
        XCTAssertEqual(viewModel.parsedAmount(currencyCode: "JPY"), 100)
        let shares = try XCTUnwrap(viewModel.resolvedSplits(
            payerId: BudgetMateTestFixtures.aliceMemberID,
            currencyCode: "JPY"
        ))
        XCTAssertEqual(shares.map(\.amount).reduce(0, +), 100, accuracy: 0.001)
        let exactShares = try XCTUnwrap(viewModel.resolvedMoneySplits(
            payerId: BudgetMateTestFixtures.aliceMemberID,
            currencyCode: "JPY"
        ))
        XCTAssertEqual(exactShares.map(\.money.minorUnits).reduce(0, +), 100)
    }

    func testJPYProgrammaticFractionalCustomSplitIsRejectedWithoutDoubleTolerance() {
        let viewModel = AddTransactionViewModel()
        viewModel.title = "Yen split"
        viewModel.amountText = "100"
        viewModel.isSplit = true
        viewModel.splitMethod = .custom
        viewModel.participants = [BudgetMateTestFixtures.aliceMemberID, BudgetMateTestFixtures.bobMemberID]
        viewModel.customAmounts = [
            BudgetMateTestFixtures.aliceMemberID: "50.5",
            BudgetMateTestFixtures.bobMemberID: "49.5"
        ]

        XCTAssertFalse(viewModel.isSplitValid(currencyCode: "JPY"))
        XCTAssertNil(viewModel.resolvedMoneySplits(
            payerId: BudgetMateTestFixtures.aliceMemberID,
            currencyCode: "JPY"
        ))
    }

    func testBudgetAggregateOverflowIsAnomalyAndNotAnOrdinaryZero() throws {
        let first = BudgetMateTestFixtures.expense(amount: 1, date: BudgetMateTestFixtures.referenceDate)
        let second = BudgetMateTestFixtures.expense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000115")!,
            amount: 1,
            date: BudgetMateTestFixtures.referenceDate
        )
        first.amountMinorUnits = Int64.max
        first.currencyCode = "USD"
        second.amountMinorUnits = 1
        second.currencyCode = "USD"
        let interval = try XCTUnwrap(
            BudgetMateTestFixtures.utcCalendar.dateInterval(of: .month, for: BudgetMateTestFixtures.referenceDate)
        )

        let metrics = BudgetTabMetrics.compute(
            transactions: [first, second],
            settlements: [],
            members: [BudgetMateTestFixtures.alice],
            monthInterval: interval,
            currencyCode: "USD",
            budgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            calendar: BudgetMateTestFixtures.utcCalendar
        )

        XCTAssertEqual(metrics.totalExpenses, 0, accuracy: 0.001)
        XCTAssertTrue(metrics.anomalies.contains {
            $0.sourceID == "budget-total" && $0.reason == .arithmeticOverflow
        })
    }

    func testBudgetCategoryBreakdownCarriesAggregateAnomalyForDrillDownNotice() {
        let first = BudgetMateTestFixtures.expense(amount: 1, category: .groceries)
        let second = BudgetMateTestFixtures.expense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000116")!,
            amount: 1,
            category: .groceries
        )
        first.amountMinorUnits = Int64.max
        first.currencyCode = "USD"
        second.amountMinorUnits = 1
        second.currencyCode = "USD"

        let breakdown = BudgetCategoryTransactionBreakdown(
            categoryRawValue: TransactionCategory.groceries.rawValue,
            budgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            sourceTransactions: [first, second],
            currencyCode: "USD"
        )

        XCTAssertEqual(breakdown.total, 0, accuracy: 0.001)
        XCTAssertTrue(breakdown.anomalies.contains {
            $0.sourceID == "category-groceries" && $0.reason == .arithmeticOverflow
        })
    }

    func testExactCurrencyMismatchIsSurfacedAndExcludedFromTotals() {
        let transaction = BudgetMateTestFixtures.expense(amount: 10)
        transaction.amountMinorUnits = 1_000
        transaction.currencyCode = "JPY"

        let totals = DashboardViewModel.totals(
            transactions: [transaction],
            monthlyBudget: 100,
            currencyCode: "USD"
        )

        XCTAssertEqual(totals.totalExpenses, 0, accuracy: 0.001)
        XCTAssertEqual(totals.anomalies.first?.reason, .currencyMismatch)
        XCTAssertFalse(totals.anomalies.isEmpty)
    }

    func testJPYSettlementSuggestionCarriesMinorUnitsWithoutCentsConversion() {
        let expense = BudgetMateTestFixtures.equalSplitExpense(amount: 100, payerId: BudgetMateTestFixtures.aliceMemberID)
        for split in expense.splits {
            split.amountMinorUnits = 50
            split.currencyCode = "JPY"
        }
        expense.amountMinorUnits = 100
        expense.currencyCode = "JPY"

        let result = DashboardViewModel.settlementsResult(
            splitExpenses: [expense],
            members: [BudgetMateTestFixtures.alice, BudgetMateTestFixtures.bob],
            currencyCode: "JPY"
        )

        XCTAssertEqual(result.suggestions.first?.amountMinorUnits, 50)
        XCTAssertEqual(result.suggestions.first?.currencyCode, "JPY")
        XCTAssertEqual(result.suggestions.first?.amount ?? 0, 50, accuracy: 0.001)
        XCTAssertTrue(result.anomalies.isEmpty)
    }

    func testUTCMinusTwelveMonthSelectionMovesAcrossYearBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -12 * 60 * 60))
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 12, day: 31, hour: 23)))
        let store = MonthSelectionStore(calendar: calendar, referenceDate: referenceDate)

        XCTAssertEqual(store.selectedMonthKey, "2024-12")
        store.moveMonth(by: 1)
        XCTAssertEqual(store.selectedMonthKey, "2025-01")
        store.moveMonth(by: -1)
        XCTAssertEqual(store.selectedMonthKey, "2024-12")
    }

    func testFinancialFingerprintChangesWhenExactMoneyFieldsChange() {
        let transaction = BudgetMateTestFixtures.expense(amount: 10)
        let initial = FinancialDataFingerprint.hash(transactions: [transaction], settlements: [])
        transaction.amountMinorUnits = 1_000
        transaction.currencyCode = "CAD"
        let changed = FinancialDataFingerprint.hash(transactions: [transaction], settlements: [])

        XCTAssertNotEqual(initial, changed)
    }
}

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
        XCTAssertNil(viewModel.splitValidationMessage)

        viewModel.updateCustomAmount("59.98", for: BudgetMateTestFixtures.bobMemberID)
        XCTAssertFalse(viewModel.isSplitValid)
        XCTAssertEqual(viewModel.splitValidationMessage, "Add 0.02 more to match the total.")
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
}

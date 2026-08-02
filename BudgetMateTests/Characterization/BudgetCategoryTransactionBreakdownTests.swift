import XCTest
@testable import BudgetMate

@MainActor
final class BudgetCategoryTransactionBreakdownTests: XCTestCase {
    func testBreakdownIsScopedExpenseOnlyAndIncludesResolvedRecurringOccurrences() throws {
        let scope = BudgetMateTestFixtures.sharedBudgetID.uuidString
        let january = BudgetMateTestFixtures.makeDate(year: 2025, month: 1, day: 15)
        let monthInterval = try XCTUnwrap(BudgetMateTestFixtures.utcCalendar.dateInterval(of: .month, for: january))
        let tieDate = BudgetMateTestFixtures.makeDate(year: 2025, month: 1, day: 20)
        let tieA = BudgetMateTestFixtures.expense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000601")!,
            title: "Coffee",
            amount: 3,
            category: .food,
            date: tieDate
        )
        let tieB = BudgetMateTestFixtures.expense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000602")!,
            title: "Coffee",
            amount: 4,
            category: .food,
            date: tieDate
        )
        let recurring = BudgetMateTestFixtures.expense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000603")!,
            title: "Monthly Food Box",
            amount: 25,
            category: .food,
            date: BudgetMateTestFixtures.makeDate(year: 2024, month: 12, day: 31),
            recurrenceRule: "monthly"
        )
        let currentFood = BudgetMateTestFixtures.expense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000604")!,
            title: "Lunch",
            amount: 10,
            category: .food,
            date: BudgetMateTestFixtures.makeDate(year: 2025, month: 1, day: 10)
        )
        let otherCategory = BudgetMateTestFixtures.expense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000605")!,
            title: "Dinner",
            amount: 90,
            category: .restaurant,
            date: january
        )
        let otherMonth = BudgetMateTestFixtures.expense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000606")!,
            title: "February Food",
            amount: 100,
            category: .food,
            date: BudgetMateTestFixtures.makeDate(year: 2025, month: 2, day: 2)
        )
        let otherYear = BudgetMateTestFixtures.expense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000607")!,
            title: "Prior Year Food",
            amount: 100,
            category: .food,
            date: BudgetMateTestFixtures.makeDate(year: 2024, month: 1, day: 2)
        )
        let otherScope = BudgetMateTestFixtures.expense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000608")!,
            title: "Other Household Food",
            amount: 100,
            category: .food,
            date: january
        )
        otherScope.ownerUserId = BudgetMateTestFixtures.personalBudgetID.uuidString

        let income = Transaction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000609")!,
            title: "Food Refund",
            amount: 200,
            type: .income,
            category: .food,
            createdByMemberId: BudgetMateTestFixtures.aliceMemberID,
            date: january,
            ownerUserId: scope
        )

        let metrics = BudgetTabMetrics.compute(
            transactions: [
                tieA,
                tieB,
                recurring,
                currentFood,
                otherCategory,
                otherMonth,
                otherYear,
                otherScope,
                income
            ],
            settlements: [],
            members: [BudgetMateTestFixtures.alice],
            monthInterval: monthInterval,
            budgetScopeId: scope
        )
        let breakdown = metrics.categoryBreakdown(for: .food, budgetScopeId: scope)

        XCTAssertEqual(breakdown.categoryRawValue, TransactionCategory.food.rawValue)
        XCTAssertEqual(breakdown.budgetScopeId, scope)
        XCTAssertEqual(breakdown.transactions.count, 4)
        XCTAssertEqual(breakdown.total, 42)
        XCTAssertEqual(metrics.spentByCategory[.food], breakdown.total)
        XCTAssertTrue(breakdown.transactions.allSatisfy { $0.ownerUserId == scope && $0.type == .expense })
        XCTAssertFalse(breakdown.transactions.contains { $0.id == otherCategory.id })
        XCTAssertFalse(breakdown.transactions.contains { $0.id == otherMonth.id })
        XCTAssertFalse(breakdown.transactions.contains { $0.id == otherYear.id })
        XCTAssertFalse(breakdown.transactions.contains { $0.id == otherScope.id })
        XCTAssertFalse(breakdown.transactions.contains { $0.id == income.id })

        let recurringOccurrence = try XCTUnwrap(
            breakdown.transactions.first(where: { $0.id == recurring.id })
        )
        XCTAssertTrue(recurringOccurrence.isGeneratedRecurringOccurrence)
        XCTAssertEqual(
            BudgetMateTestFixtures.utcCalendar.component(.day, from: recurringOccurrence.date),
            31
        )
    }

    func testBreakdownSupportsCustomAndEmptyCategories() throws {
        let scope = BudgetMateTestFixtures.sharedBudgetID.uuidString
        let date = BudgetMateTestFixtures.makeDate(year: 2025, month: 1, day: 10)
        let customCategory = TransactionCategory("petCare")
        let customExpense = BudgetMateTestFixtures.expense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000610")!,
            title: "Vet",
            amount: 75,
            category: customCategory,
            date: date
        )
        let interval = try XCTUnwrap(BudgetMateTestFixtures.utcCalendar.dateInterval(of: .month, for: date))
        let metrics = BudgetTabMetrics.compute(
            transactions: [customExpense],
            settlements: [],
            members: [],
            monthInterval: interval,
            budgetScopeId: scope
        )

        let customBreakdown = metrics.categoryBreakdown(for: customCategory, budgetScopeId: scope)
        let emptyBreakdown = metrics.categoryBreakdown(for: .vacation, budgetScopeId: scope)

        XCTAssertEqual(customBreakdown.transactions.map(\.id), [customExpense.id])
        XCTAssertEqual(customBreakdown.total, 75)
        XCTAssertTrue(emptyBreakdown.transactions.isEmpty)
        XCTAssertEqual(emptyBreakdown.total, 0)
    }

    func testCADCategorySummaryMatchesItsVisibleTransactionBreakdown() throws {
        let scope = BudgetMateTestFixtures.sharedBudgetID.uuidString
        let date = BudgetMateTestFixtures.makeDate(year: 2026, month: 7, day: 18)
        let interval = try XCTUnwrap(BudgetMateTestFixtures.utcCalendar.dateInterval(of: .month, for: date))
        let billsExpense = BudgetMateTestFixtures.expense(
            title: "Internet",
            amount: 270.99,
            category: .bills,
            date: date
        )
        billsExpense.amountMinorUnits = 27_099
        billsExpense.currencyCode = "CAD"

        let metrics = BudgetTabMetrics.compute(
            transactions: [billsExpense],
            settlements: [],
            members: [],
            monthInterval: interval,
            currencyCode: "CAD",
            budgetScopeId: scope,
            calendar: BudgetMateTestFixtures.utcCalendar
        )
        let breakdown = metrics.categoryBreakdown(for: .bills, budgetScopeId: scope)
        let categorySpent = try XCTUnwrap(metrics.spentByCategory[.bills])

        XCTAssertEqual(metrics.currencyCode, "CAD")
        XCTAssertEqual(categorySpent, 270.99, accuracy: 0.001)
        XCTAssertEqual(breakdown.total, 270.99, accuracy: 0.001)
        XCTAssertEqual(breakdown.total, categorySpent, accuracy: 0.001)
        XCTAssertEqual(breakdown.transactions.map(\.id), [billsExpense.id])
        XCTAssertTrue(metrics.anomalies.isEmpty)
    }

    func testBreakdownUsesNewestFirstAndStableIdentifierTieBreak() throws {
        let scope = BudgetMateTestFixtures.sharedBudgetID.uuidString
        let date = BudgetMateTestFixtures.makeDate(year: 2025, month: 1, day: 10)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000702")!
        let first = BudgetMateTestFixtures.expense(id: firstID, title: "Same", amount: 1, category: .food, date: date)
        let second = BudgetMateTestFixtures.expense(id: secondID, title: "Same", amount: 2, category: .food, date: date)
        let newer = BudgetMateTestFixtures.expense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000703")!,
            title: "Newer",
            amount: 3,
            category: .food,
            date: date.addingTimeInterval(60)
        )
        let interval = try XCTUnwrap(BudgetMateTestFixtures.utcCalendar.dateInterval(of: .month, for: date))
        let metrics = BudgetTabMetrics.compute(
            transactions: [second, newer, first],
            settlements: [],
            members: [],
            monthInterval: interval,
            budgetScopeId: scope
        )

        let ids = metrics.categoryBreakdown(for: .food, budgetScopeId: scope).transactions.map(\.id)
        XCTAssertEqual(ids, [newer.id, firstID, secondID])
    }
}

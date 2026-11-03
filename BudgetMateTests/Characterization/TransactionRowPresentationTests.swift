import XCTest
@testable import BudgetMate

@MainActor
final class TransactionRowPresentationTests: XCTestCase {
    func testCADTransactionRowAmountsUseDollarWithIncomeExpenseSigns() {
        let locale = Locale(identifier: "en_CA")

        let expense = TransactionRowPresentation.signedAmount(
            amount: 12.34,
            type: .expense,
            currencySymbol: "CA$",
            locale: locale
        )
        let income = TransactionRowPresentation.signedAmount(
            amount: 12.34,
            type: .income,
            currencySymbol: "CA$",
            locale: locale
        )

        XCTAssertEqual(expense, "-$12.34")
        XCTAssertEqual(income, "+$12.34")
        for output in [expense, income] {
            XCTAssertTrue(output.contains("$"))
            XCTAssertFalse(output.contains("CAD"))
            XCTAssertFalse(output.contains("CA$"))
        }
    }

    func testUpcomingClassificationUsesCalendarDaysNotClockTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9)))
        let laterToday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)))
        let tomorrow = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9)))
        let transaction = BudgetMateTestFixtures.expense(title: "Lunch", date: laterToday)

        XCTAssertFalse(transaction.isUpcomingTransaction(on: now, calendar: calendar))
        transaction.date = tomorrow
        XCTAssertTrue(transaction.isUpcomingTransaction(on: now, calendar: calendar))
    }

    func testProjectedPacingUsesFullMonthBudgetWhileActualPacingUsesElapsedBudget() {
        let projectedTarget = DashboardView.pacingTargetSpend(
            monthlyBudget: 500,
            elapsedDays: 2,
            totalDays: 30,
            includesProjectedTransactions: true
        )
        XCTAssertEqual(projectedTarget, 500)
        XCTAssertLessThanOrEqual(
            400,
            projectedTarget,
            "A $400 projection should be on track against the full-month budget."
        )

        let actualTarget = DashboardView.pacingTargetSpend(
            monthlyBudget: 500,
            elapsedDays: 2,
            totalDays: 30,
            includesProjectedTransactions: false
        )
        XCTAssertEqual(
            actualTarget,
            500 * (2.0 / 30.0),
            accuracy: 0.001
        )

        XCTAssertTrue(
            DashboardView.isSpendingFasterThanPlanned(
                actualExpenses: 2_400,
                monthlyBudget: 3_000,
                elapsedDays: 5,
                totalDays: 30
            )
        )
        XCTAssertFalse(
            DashboardView.isSpendingFasterThanPlanned(
                actualExpenses: 0,
                monthlyBudget: 3_000,
                elapsedDays: 5,
                totalDays: 30
            )
        )
    }

    func testCurrentPacingUsesActualExpensesWhenFutureExpensesAreProjected() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9)))
        let futureNetflix = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9)))
        let futureRent = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 9)))

        let actual = BudgetMateTestFixtures.expense(id: UUID(), amount: 2_400, date: now)
        let projectedNetflix = BudgetMateTestFixtures.expense(id: UUID(), amount: 15.99, date: futureNetflix)
        let actualExpenses = DashboardViewModel.totals(
            transactions: [actual, projectedNetflix].filter {
                !$0.isUpcomingTransaction(on: now, calendar: calendar)
            },
            monthlyBudget: 3_000
        ).totalExpenses

        XCTAssertEqual(actualExpenses, 2_400, accuracy: 0.001)
        XCTAssertTrue(
            DashboardView.isSpendingFasterThanPlanned(
                actualExpenses: actualExpenses,
                monthlyBudget: 3_000,
                elapsedDays: 5,
                totalDays: 30
            )
        )

        let projectedRent = BudgetMateTestFixtures.expense(id: UUID(), amount: 2_200, date: futureRent)
        let noActualExpenses = DashboardViewModel.totals(
            transactions: [projectedRent].filter {
                !$0.isUpcomingTransaction(on: now, calendar: calendar)
            },
            monthlyBudget: 3_000
        ).totalExpenses

        XCTAssertEqual(noActualExpenses, 0, accuracy: 0.001)
        XCTAssertFalse(
            DashboardView.isSpendingFasterThanPlanned(
                actualExpenses: noActualExpenses,
                monthlyBudget: 3_000,
                elapsedDays: 5,
                totalDays: 30
            )
        )
    }
}

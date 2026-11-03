import XCTest
@testable import BudgetMate

final class RecurrenceCharacterizationTests: XCTestCase {
    func testMonthlyOccurrenceClampsJanuaryThirtyFirstToFebruaryTwentyEighth() {
        let source = BudgetMateTestFixtures.recurringExpense()
        let interval = DateInterval(start: BudgetMateTestFixtures.februaryFirst, end: BudgetMateTestFixtures.marchFirst)

        let occurrences = RecurringTransactionResolver.transactions(
            in: interval,
            from: [source],
            calendar: BudgetMateTestFixtures.utcCalendar
        )

        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences.first?.recurringSourceId, source.id)
        XCTAssertEqual(
            BudgetMateTestFixtures.utcCalendar.component(.day, from: try! XCTUnwrap(occurrences.first?.date)),
            28
        )
        XCTAssertEqual(
            BudgetMateTestFixtures.utcCalendar.component(.month, from: try! XCTUnwrap(occurrences.first?.date)),
            2
        )
    }

    func testMonthlyOccurrenceStopsAfterFixedEndDate() {
        let source = BudgetMateTestFixtures.recurringExpense(
            endDate: BudgetMateTestFixtures.makeDate(year: 2025, month: 2, day: 15)
        )
        let interval = DateInterval(start: BudgetMateTestFixtures.marchFirst, end: BudgetMateTestFixtures.makeDate(year: 2025, month: 4, day: 1))

        let occurrences = RecurringTransactionResolver.transactions(
            in: interval,
            from: [source],
            calendar: BudgetMateTestFixtures.utcCalendar
        )

        XCTAssertTrue(occurrences.isEmpty)
    }

    func testMonthlyOccurrenceOnStopDateIsIncluded() throws {
        let endDate = BudgetMateTestFixtures.makeDate(year: 2025, month: 3, day: 31)
        let source = BudgetMateTestFixtures.recurringExpense(
            date: BudgetMateTestFixtures.makeDate(year: 2025, month: 1, day: 31, hour: 12),
            endDate: endDate
        )
        let interval = DateInterval(
            start: BudgetMateTestFixtures.makeDate(year: 2025, month: 3, day: 1),
            end: BudgetMateTestFixtures.makeDate(year: 2025, month: 4, day: 1)
        )

        let occurrences = RecurringTransactionResolver.transactions(
            in: interval,
            from: [source],
            calendar: BudgetMateTestFixtures.utcCalendar
        )

        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(
            BudgetMateTestFixtures.utcCalendar.component(.day, from: try XCTUnwrap(occurrences.first?.date)),
            31
        )
    }

    func testFinancialFingerprintChangesForCategoryTypeAndPayerEdits() {
        let transaction = BudgetMateTestFixtures.expense(amount: 10)
        let initial = FinancialDataFingerprint.hash(transactions: [transaction], settlements: [])

        transaction.category = .restaurant
        let categoryChanged = FinancialDataFingerprint.hash(transactions: [transaction], settlements: [])
        XCTAssertNotEqual(initial, categoryChanged)

        transaction.type = .income
        let typeChanged = FinancialDataFingerprint.hash(transactions: [transaction], settlements: [])
        XCTAssertNotEqual(categoryChanged, typeChanged)

        transaction.createdByMemberId = BudgetMateTestFixtures.bobMemberID
        let payerChanged = FinancialDataFingerprint.hash(transactions: [transaction], settlements: [])
        XCTAssertNotEqual(typeChanged, payerChanged)
    }
}

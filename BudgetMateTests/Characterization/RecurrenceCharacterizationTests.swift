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
}

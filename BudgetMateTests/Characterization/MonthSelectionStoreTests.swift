import XCTest
@testable import BudgetMate

@MainActor
final class MonthSelectionStoreTests: XCTestCase {
    func testSelectionMovesFromDecemberToJanuaryAndBackAcrossYears() {
        let calendar = BudgetMateTestFixtures.utcCalendar
        let store = MonthSelectionStore(
            calendar: calendar,
            referenceDate: BudgetMateTestFixtures.makeDate(year: 2024, month: 12, day: 15)
        )

        XCTAssertEqual(store.selectedMonthKey, "2024-12")
        XCTAssertEqual(store.selectedMonthTitle, "December 2024")
        XCTAssertEqual(store.selectedYear, 2024)
        XCTAssertEqual(store.selectedMonthIndex, 11)

        store.moveMonth(by: 1)
        XCTAssertEqual(store.selectedMonthKey, "2025-01")
        XCTAssertEqual(store.selectedMonthTitle, "January 2025")
        XCTAssertEqual(store.selectedYear, 2025)
        XCTAssertEqual(store.selectedMonthIndex, 0)

        store.moveMonth(by: -1)
        XCTAssertEqual(store.selectedMonthKey, "2024-12")
        XCTAssertEqual(store.selectedMonthTitle, "December 2024")
        XCTAssertEqual(store.selectedYear, 2024)
        XCTAssertEqual(store.selectedMonthIndex, 11)
    }

    func testSelectedDateAndIntervalFollowTheYearMonthSelection() throws {
        let calendar = BudgetMateTestFixtures.utcCalendar
        let store = MonthSelectionStore(
            calendar: calendar,
            referenceDate: BudgetMateTestFixtures.makeDate(year: 2024, month: 2, day: 10)
        )

        let selectedComponents = calendar.dateComponents([.year, .month, .day], from: store.selectedMonthDate)
        XCTAssertEqual(selectedComponents.year, 2024)
        XCTAssertEqual(selectedComponents.month, 2)
        XCTAssertEqual(selectedComponents.day, 1)
        XCTAssertEqual(store.selectedMonthTitle, "February 2024")

        let interval = try XCTUnwrap(store.monthInterval())
        let lastDay = try XCTUnwrap(calendar.date(byAdding: .second, value: -1, to: interval.end))
        XCTAssertEqual(calendar.component(.day, from: lastDay), 29)
        XCTAssertEqual(calendar.component(.month, from: interval.start), 2)
        XCTAssertEqual(calendar.component(.year, from: interval.start), 2024)
    }

    func testRefreshIdentityChangesWhenOnlyTheYearChanges() {
        let calendar = BudgetMateTestFixtures.utcCalendar
        let store = MonthSelectionStore(
            calendar: calendar,
            referenceDate: BudgetMateTestFixtures.makeDate(year: 2024, month: 12, day: 15)
        )
        let decemberIdentity = store.selectedMonthKey

        store.moveMonth(by: 12)

        XCTAssertEqual(store.selectedMonthIndex, 11)
        XCTAssertEqual(store.selectedYear, 2025)
        XCTAssertNotEqual(store.selectedMonthKey, decemberIdentity)
        XCTAssertEqual(store.selectedMonthKey, "2025-12")
        XCTAssertEqual(store.selectedMonthTitle, "December 2025")
    }

    func testSelectedMonthTitleUsesInjectedPacificKiritimatiTimeZone() throws {
        let calendar = try calendar(timeZoneIdentifier: "Pacific/Kiritimati")
        let referenceDate = try date(calendar: calendar, year: 2025, month: 1, day: 15)
        let store = MonthSelectionStore(calendar: calendar, referenceDate: referenceDate)

        assertSelection(store, calendar: calendar, year: 2025, month: 1, title: "January 2025")
    }

    func testSelectedMonthTitleUsesInjectedUtcMinusTwelveTimeZone() throws {
        let calendar = try calendar(timeZoneIdentifier: "Etc/GMT+12")
        let referenceDate = try date(calendar: calendar, year: 2024, month: 12, day: 15)
        let store = MonthSelectionStore(calendar: calendar, referenceDate: referenceDate)

        assertSelection(store, calendar: calendar, year: 2024, month: 12, title: "December 2024")
    }

    private func calendar(timeZoneIdentifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZoneIdentifier))
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func date(calendar: Calendar, year: Int, month: Int, day: Int) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: year, month: month, day: day, hour: 12)
            )
        )
    }

    private func assertSelection(
        _ store: MonthSelectionStore,
        calendar: Calendar,
        year: Int,
        month: Int,
        title: String
    ) {
        XCTAssertEqual(store.selectedMonthTitle, title)
        XCTAssertEqual(store.selectedMonthKey, String(format: "%d-%02d", year, month))

        let start = store.selectedMonthDate
        let startComponents = calendar.dateComponents([.year, .month, .day], from: start)
        XCTAssertEqual(startComponents.year, year)
        XCTAssertEqual(startComponents.month, month)
        XCTAssertEqual(startComponents.day, 1)

        let interval = store.monthInterval()
        XCTAssertEqual(interval.map { calendar.component(.year, from: $0.start) }, year)
        XCTAssertEqual(interval.map { calendar.component(.month, from: $0.start) }, month)
    }
}

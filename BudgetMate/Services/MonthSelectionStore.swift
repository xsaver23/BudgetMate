import Foundation

@MainActor
final class MonthSelectionStore: ObservableObject {
    @Published private(set) var selectedMonthIndex: Int
    @Published private(set) var selectedYear: Int

    private let calendar: Calendar
    private let monthTitleFormatter: DateFormatter
    var selectionCalendar: Calendar { calendar }

    init(calendar: Calendar = .current, referenceDate: Date = .now) {
        self.calendar = calendar
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        monthTitleFormatter = formatter
        let components = calendar.dateComponents([.year, .month], from: referenceDate)
        selectedYear = components.year ?? calendar.component(.year, from: referenceDate)
        selectedMonthIndex = max(0, min(11, (components.month ?? 1) - 1))
    }

    var selectedMonthDate: Date {
        let components = DateComponents(year: selectedYear, month: selectedMonthIndex + 1, day: 1)
        return calendar.date(from: components) ?? .now
    }

    /// Stable year-month identity for derived metrics and navigation state.
    var selectedMonthKey: String {
        BudgetSettings.monthKey(for: selectedMonthDate, calendar: calendar)
    }

    var selectedMonthTitle: String {
        monthTitleFormatter.string(from: selectedMonthDate)
    }

    var isCurrentMonth: Bool {
        calendar.isDate(selectedMonthDate, equalTo: .now, toGranularity: .month)
    }

    func updateMonthIndex(_ newValue: Int) {
        moveMonth(by: newValue - selectedMonthIndex)
    }

    func moveMonth(by offset: Int) {
        guard let movedDate = calendar.date(byAdding: .month, value: offset, to: selectedMonthDate) else {
            return
        }
        let components = calendar.dateComponents([.year, .month], from: movedDate)
        selectedYear = components.year ?? selectedYear
        selectedMonthIndex = max(0, min(11, (components.month ?? 1) - 1))
    }

    func monthInterval() -> DateInterval? {
        calendar.dateInterval(of: .month, for: selectedMonthDate)
    }
}

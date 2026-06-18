import Foundation

@MainActor
final class MonthSelectionStore: ObservableObject {
    @Published private(set) var selectedMonthIndex: Int

    private let calendar: Calendar
    private let selectedYear: Int

    init(calendar: Calendar = .current, referenceDate: Date = .now) {
        self.calendar = calendar
        selectedYear = calendar.component(.year, from: referenceDate)
        selectedMonthIndex = max(0, min(11, calendar.component(.month, from: referenceDate) - 1))
    }

    var selectedMonthDate: Date {
        let components = DateComponents(year: selectedYear, month: selectedMonthIndex + 1, day: 1)
        return calendar.date(from: components) ?? .now
    }

    var selectedMonthTitle: String {
        Self.monthTitleFormatter.string(from: selectedMonthDate)
    }

    func updateMonthIndex(_ newValue: Int) {
        selectedMonthIndex = max(0, min(11, newValue))
    }

    func monthInterval() -> DateInterval? {
        calendar.dateInterval(of: .month, for: selectedMonthDate)
    }

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}

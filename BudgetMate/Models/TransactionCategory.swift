import Foundation

struct TransactionCategory: RawRepresentable, Codable, Hashable, Identifiable, CaseIterable {
    static let hiddenCategoryPrefix = "__hiddenCategory__"

    let rawValue: String

    var id: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let food = TransactionCategory("food")
    static let restaurant = TransactionCategory("restaurant")
    static let groceries = TransactionCategory("groceries")
    static let rent = TransactionCategory("rent")
    static let subscription = TransactionCategory("subscription")
    static let health = TransactionCategory("health")
    static let household = TransactionCategory("household")
    static let gift = TransactionCategory("gift")
    static let studentLoans = TransactionCategory("studentLoans")
    static let date = TransactionCategory("date")
    static let vacation = TransactionCategory("vacation")
    static let parking = TransactionCategory("parking")
    static let gas = TransactionCategory("gas")
    static let transportation = TransactionCategory("transportation")
    static let shopping = TransactionCategory("shopping")
    static let entertainment = TransactionCategory("entertainment")
    static let bills = TransactionCategory("bills")
    static let salary = TransactionCategory("salary")
    static let refund = TransactionCategory("refund")
    static let work = TransactionCategory("work")
    static let eTransfer = TransactionCategory("eTransfer")
    static let other = TransactionCategory("other")

    static var allCases: [TransactionCategory] {
        expenseCategories + incomeCategories.filter { !expenseCategories.contains($0) }
    }

    static var expenseCategories: [TransactionCategory] {
        [
            .rent,
            .bills,
            .studentLoans,
            .subscription,
            .food,
            .groceries,
            .health,
            .household,
            .gas,
            .parking,
            .transportation,
            .shopping,
            .restaurant,
            .date,
            .vacation,
            .entertainment,
            .gift,
            .other
        ]
    }

    static var incomeCategories: [TransactionCategory] {
        [.gift, .refund, .work, .eTransfer, .other]
    }

    static var builtInExpenseRawValues: Set<String> {
        Set(expenseCategories.map(\.rawValue))
    }

    static var builtInRawValues: Set<String> {
        Set(allCases.map(\.rawValue))
    }

    static func hiddenMarkerKey(for category: TransactionCategory) -> String {
        hiddenCategoryPrefix + category.rawValue
    }

    static func isHiddenMarkerKey(_ key: String) -> Bool {
        key.hasPrefix(hiddenCategoryPrefix)
    }

    var isBuiltInExpenseCategory: Bool {
        Self.builtInExpenseRawValues.contains(rawValue)
    }

    var isProtectedCategory: Bool {
        self == .other
    }

    var displayName: String {
        switch self {
        case .food:
            return "Food"
        case .restaurant:
            return "Restaurant"
        case .groceries:
            return "Groceries"
        case .rent:
            return "Rent"
        case .subscription:
            return "Subscription"
        case .health:
            return "Health"
        case .household:
            return "Household"
        case .gift:
            return "Gift"
        case .studentLoans:
            return "Student loans"
        case .date:
            return "Date"
        case .vacation:
            return "Vacation"
        case .parking:
            return "Parking"
        case .gas:
            return "Gas"
        case .transportation:
            return "Transportation"
        case .shopping:
            return "Shopping"
        case .entertainment:
            return "Entertainment"
        case .bills:
            return "Bills"
        case .salary:
            return "Salary"
        case .refund:
            return "Refund"
        case .work:
            return "Work"
        case .eTransfer:
            return "E-transfer"
        case .other:
            return "Other"
        default:
            return Self.displayName(forCustomRawValue: rawValue)
        }
    }

    static func customRawValue(from displayName: String) -> String? {
        let words = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard let first = words.first else { return nil }
        let head = first.lowercased()
        let tail = words.dropFirst().map { word in
            let lowered = word.lowercased()
            return lowered.prefix(1).uppercased() + lowered.dropFirst()
        }
        return ([head] + tail).joined()
    }

    private static func displayName(forCustomRawValue rawValue: String) -> String {
        let spaced = rawValue
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        guard let first = spaced.first else { return "Custom" }
        return first.uppercased() + spaced.dropFirst()
    }
}

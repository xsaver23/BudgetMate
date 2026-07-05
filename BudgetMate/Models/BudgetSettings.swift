import Foundation

struct BudgetSettings: Codable, Equatable {
    static let monthBudgetPrefix = "__monthBudget__:"

    var currencyCode: String
    var appearance: AppearanceOption
    var categoryBudgets: [String: Double]
    var categoryEmojis: [String: String]

    var monthlyBudget: Double {
        legacyCategoryBudgets.reduce(0) { total, entry in
            guard !Self.isInternalBudgetKey(entry.key) else { return total }
            return total + max(0, entry.value)
        }
    }

    var currencySymbol: String {
        CurrencyOption.symbol(for: currencyCode)
    }

    static let `default` = BudgetSettings(
        monthlyBudget: 0,
        currencyCode: CurrencyOption.usd.code,
        appearance: .system,
        categoryBudgets: [:],
        categoryEmojis: [:]
    )

    init(
        monthlyBudget: Double,
        currencyCode: String,
        appearance: AppearanceOption = .system,
        categoryBudgets: [String: Double],
        categoryEmojis: [String: String] = [:]
    ) {
        self.currencyCode = CurrencyOption.normalizedCode(currencyCode)
        self.appearance = appearance
        if categoryBudgets.isEmpty, monthlyBudget > 0 {
            self.categoryBudgets = [TransactionCategory.other.rawValue: monthlyBudget]
        } else {
            self.categoryBudgets = categoryBudgets
        }
        self.categoryEmojis = categoryEmojis.filter { $0.value.isSingleEmoji }
    }

    enum CodingKeys: String, CodingKey {
        case monthlyBudget
        case currencyCode
        case currencySymbol
        case appearance
        case categoryBudgets
        case categoryEmojis
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) {
            currencyCode = CurrencyOption.normalizedCode(decodedCode)
        } else {
            let legacySymbol = try container.decodeIfPresent(String.self, forKey: .currencySymbol)
            currencyCode = CurrencyOption.code(forLegacySymbol: legacySymbol)
        }
        appearance = try container.decodeIfPresent(AppearanceOption.self, forKey: .appearance) ?? .system
        let legacyMonthlyBudget = try container.decodeIfPresent(Double.self, forKey: .monthlyBudget) ?? 0
        let decodedCategoryBudgets = try container.decodeIfPresent([String: Double].self, forKey: .categoryBudgets) ?? [:]
        if decodedCategoryBudgets.isEmpty, legacyMonthlyBudget > 0 {
            categoryBudgets = [TransactionCategory.other.rawValue: legacyMonthlyBudget]
        } else {
            categoryBudgets = decodedCategoryBudgets
        }
        let decodedEmojis = try container.decodeIfPresent([String: String].self, forKey: .categoryEmojis) ?? [:]
        categoryEmojis = decodedEmojis.filter { $0.value.isSingleEmoji }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(monthlyBudget, forKey: .monthlyBudget)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(categoryBudgets, forKey: .categoryBudgets)
        try container.encode(categoryEmojis, forKey: .categoryEmojis)
    }

    func emoji(for category: TransactionCategory) -> String? {
        let emoji = categoryEmojis[category.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return emoji?.isSingleEmoji == true ? emoji : nil
    }

    func categoryBudgets(forMonthKey monthKey: String) -> [String: Double] {
        let exact = scopedCategoryBudgets(forMonthKey: monthKey)
        let prior = priorScopedCategoryBudgets(before: monthKey)

        var effective = prior
        for (category, amount) in exact {
            effective[category] = amount
        }
        return effective
    }

    func monthlyBudget(forMonthKey monthKey: String) -> Double {
        categoryBudgets(forMonthKey: monthKey).reduce(0) { total, entry in
            guard !Self.isInternalBudgetKey(entry.key) else { return total }
            return total + max(0, entry.value)
        }
    }

    var legacyCategoryBudgets: [String: Double] {
        categoryBudgets.filter { !Self.isMonthBudgetKey($0.key) }
    }

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? calendar.component(.year, from: date)
        let month = components.month ?? calendar.component(.month, from: date)
        return "\(year)-\(String(format: "%02d", month))"
    }

    static func monthBudgetKey(monthKey: String, categoryRawValue: String) -> String {
        "\(monthBudgetPrefix)\(monthKey):\(categoryRawValue)"
    }

    static func monthAndCategory(from key: String) -> (monthKey: String, categoryRawValue: String)? {
        guard key.hasPrefix(monthBudgetPrefix) else { return nil }
        let value = String(key.dropFirst(monthBudgetPrefix.count))
        guard let separator = value.firstIndex(of: ":") else { return nil }
        let monthKey = String(value[..<separator])
        let categoryRawValue = String(value[value.index(after: separator)...])
        guard !monthKey.isEmpty, !categoryRawValue.isEmpty else { return nil }
        return (monthKey, categoryRawValue)
    }

    static func isMonthBudgetKey(_ key: String) -> Bool {
        key.hasPrefix(monthBudgetPrefix)
    }

    static func isInternalBudgetKey(_ key: String) -> Bool {
        isMonthBudgetKey(key) || TransactionCategory.isHiddenMarkerKey(key)
    }

    private func scopedCategoryBudgets(forMonthKey monthKey: String) -> [String: Double] {
        categoryBudgets.reduce(into: [String: Double]()) { result, entry in
            guard let scopedKey = Self.monthAndCategory(from: entry.key),
                  scopedKey.monthKey == monthKey else {
                return
            }
            result[scopedKey.categoryRawValue] = max(0, entry.value)
        }
    }

    private func priorScopedCategoryBudgets(before monthKey: String) -> [String: Double] {
        let priorEntries = categoryBudgets.compactMap { key, value -> (monthKey: String, categoryRawValue: String, amount: Double)? in
            guard let scopedKey = Self.monthAndCategory(from: key),
                  scopedKey.monthKey < monthKey else {
                return nil
            }
            return (scopedKey.monthKey, scopedKey.categoryRawValue, max(0, value))
        }
        return priorEntries.sorted { $0.monthKey < $1.monthKey }.reduce(into: legacyCategoryBudgets) { result, entry in
            result[entry.categoryRawValue] = entry.amount
        }
    }
}

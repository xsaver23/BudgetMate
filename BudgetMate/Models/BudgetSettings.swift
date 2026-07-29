import Foundation

enum BudgetCategoryVisibility: String, Codable, Equatable, Sendable {
    case visible
    case hidden
}

struct BudgetSettings: Codable, Equatable {
    static let monthBudgetPrefix = "__monthBudget__:"
    static let legacyCodableContractVersion = 1
    static let currentCodableContractVersion = 2

    var currencyCode: String
    var appearance: AppearanceOption
    var categoryBudgets: [String: Double]
    var categoryBudgetsMinorUnits: [String: Int64]
    var categoryVisibility: [String: BudgetCategoryVisibility]
    var categoryEmojis: [String: String]

    var monthlyBudget: Double {
        legacyCategoryBudgets.reduce(0) { total, entry in
            guard !Self.isInternalBudgetKey(entry.key) else { return total }
            return total + max(0, entry.value)
        }
    }

    var currencySymbol: String {
        CurrencyOption.displaySymbol(for: currencyCode)
    }

    /// Compatibility aliases keep the Codable payload's meaning explicit to
    /// callers without changing the legacy dictionary's name or contents.
    var categoryBudgetMinorUnits: [String: Int64] {
        get { categoryBudgetsMinorUnits }
        set { categoryBudgetsMinorUnits = newValue }
    }

    var categoryVisibilityState: [String: BudgetCategoryVisibility] {
        get { categoryVisibility }
        set { categoryVisibility = newValue }
    }

    static let `default` = BudgetSettings(
        monthlyBudget: 0,
        currencyCode: CurrencyOption.usd.code,
        appearance: .system,
        categoryBudgets: [:],
        categoryBudgetsMinorUnits: [:],
        categoryVisibility: [:],
        categoryEmojis: [:]
    )

    init(
        monthlyBudget: Double,
        currencyCode: String,
        appearance: AppearanceOption = .system,
        categoryBudgets: [String: Double],
        categoryBudgetsMinorUnits: [String: Int64] = [:],
        categoryVisibility: [String: BudgetCategoryVisibility] = [:],
        categoryEmojis: [String: String] = [:]
    ) {
        self.currencyCode = CurrencyOption.normalizedCode(currencyCode)
        self.appearance = appearance
        if categoryBudgets.isEmpty, monthlyBudget > 0 {
            self.categoryBudgets = [TransactionCategory.other.rawValue: monthlyBudget]
        } else {
            self.categoryBudgets = categoryBudgets
        }
        self.categoryBudgetsMinorUnits = categoryBudgetsMinorUnits.filter {
            !Self.isHiddenMarkerKey($0.key)
        }
        var resolvedVisibility = categoryVisibility
        for key in self.categoryBudgets.keys {
            if let category = Self.hiddenCategory(fromMarkerKey: key) {
                resolvedVisibility[category] = .hidden
            } else if let category = Self.categoryRawValue(fromBudgetKey: key),
                      resolvedVisibility[category] == nil {
                resolvedVisibility[category] = .visible
            }
        }
        self.categoryVisibility = resolvedVisibility
        self.categoryEmojis = categoryEmojis.filter { $0.value.isSingleEmoji }
    }

    enum CodingKeys: String, CodingKey {
        case monthlyBudget
        case currencyCode
        case currencySymbol
        case appearance
        case categoryBudgets
        case categoryBudgetsMinorUnits
        case categoryVisibility
        case categoryEmojis
        case settingsContractVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let contractVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .settingsContractVersion
        ) ?? Self.legacyCodableContractVersion
        guard contractVersion == Self.legacyCodableContractVersion ||
                contractVersion == Self.currentCodableContractVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .settingsContractVersion,
                in: container,
                debugDescription: "Unsupported BudgetSettings contract version."
            )
        }
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
        let decodedMinorUnits = try container.decodeIfPresent(
            [String: Int64].self,
            forKey: .categoryBudgetsMinorUnits
        ) ?? [:]
        categoryBudgetsMinorUnits = decodedMinorUnits.filter {
            !Self.isHiddenMarkerKey($0.key)
        }
        var resolvedVisibility = try container.decodeIfPresent(
            [String: BudgetCategoryVisibility].self,
            forKey: .categoryVisibility
        ) ?? [:]
        for key in categoryBudgets.keys {
            if let category = Self.hiddenCategory(fromMarkerKey: key) {
                resolvedVisibility[category] = .hidden
            } else if let category = Self.categoryRawValue(fromBudgetKey: key),
                      resolvedVisibility[category] == nil {
                resolvedVisibility[category] = .visible
            }
        }
        categoryVisibility = resolvedVisibility
        let decodedEmojis = try container.decodeIfPresent([String: String].self, forKey: .categoryEmojis) ?? [:]
        categoryEmojis = decodedEmojis.filter { $0.value.isSingleEmoji }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentCodableContractVersion, forKey: .settingsContractVersion)
        try container.encode(monthlyBudget, forKey: .monthlyBudget)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(categoryBudgets, forKey: .categoryBudgets)
        try container.encode(categoryBudgetsMinorUnits, forKey: .categoryBudgetsMinorUnits)
        try container.encode(categoryVisibility, forKey: .categoryVisibility)
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

    static func isHiddenMarkerKey(_ key: String) -> Bool {
        TransactionCategory.isHiddenMarkerKey(key)
    }

    static func isInternalBudgetKey(_ key: String) -> Bool {
        isMonthBudgetKey(key) || TransactionCategory.isHiddenMarkerKey(key)
    }

    private static func hiddenCategory(fromMarkerKey key: String) -> String? {
        guard isHiddenMarkerKey(key) else { return nil }
        let category = String(key.dropFirst(TransactionCategory.hiddenCategoryPrefix.count))
        return category.isEmpty ? nil : category
    }

    private static func categoryRawValue(fromBudgetKey key: String) -> String? {
        if let scoped = monthAndCategory(from: key) {
            return scoped.categoryRawValue
        }
        guard !isInternalBudgetKey(key), !key.isEmpty else { return nil }
        return key
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

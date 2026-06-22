import Foundation

struct BudgetSettings: Codable, Equatable {
    var currencyCode: String
    var appearance: AppearanceOption
    var categoryBudgets: [String: Double]
    var categoryEmojis: [String: String]

    var monthlyBudget: Double {
        categoryBudgets.reduce(0) { total, entry in
            guard !TransactionCategory.isHiddenMarkerKey(entry.key) else { return total }
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
}

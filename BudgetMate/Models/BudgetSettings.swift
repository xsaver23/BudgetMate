import Foundation

struct BudgetSettings: Codable, Equatable {
    var monthlyBudget: Double
    var currencyCode: String
    var appearance: AppearanceOption
    var categoryBudgets: [String: Double]

    var currencySymbol: String {
        CurrencyOption.symbol(for: currencyCode)
    }

    static let `default` = BudgetSettings(
        monthlyBudget: 0,
        currencyCode: CurrencyOption.usd.code,
        appearance: .system,
        categoryBudgets: [:]
    )

    init(
        monthlyBudget: Double,
        currencyCode: String,
        appearance: AppearanceOption = .system,
        categoryBudgets: [String: Double]
    ) {
        self.monthlyBudget = monthlyBudget
        self.currencyCode = CurrencyOption.normalizedCode(currencyCode)
        self.appearance = appearance
        self.categoryBudgets = categoryBudgets
    }

    enum CodingKeys: String, CodingKey {
        case monthlyBudget
        case currencyCode
        case currencySymbol
        case appearance
        case categoryBudgets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monthlyBudget = try container.decodeIfPresent(Double.self, forKey: .monthlyBudget) ?? 0
        if let decodedCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) {
            currencyCode = CurrencyOption.normalizedCode(decodedCode)
        } else {
            let legacySymbol = try container.decodeIfPresent(String.self, forKey: .currencySymbol)
            currencyCode = CurrencyOption.code(forLegacySymbol: legacySymbol)
        }
        appearance = try container.decodeIfPresent(AppearanceOption.self, forKey: .appearance) ?? .system
        categoryBudgets = try container.decodeIfPresent([String: Double].self, forKey: .categoryBudgets) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(monthlyBudget, forKey: .monthlyBudget)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(categoryBudgets, forKey: .categoryBudgets)
    }
}

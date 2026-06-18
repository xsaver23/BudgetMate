import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: BudgetSettings

    private let baseSettingsKey = "budgetmate.settings"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userDefaults: UserDefaults
    private var currentUserScopeId = "local"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        settings = Self.loadSettings(
            userDefaults: userDefaults,
            decoder: decoder,
            key: Self.settingsKey(baseKey: baseSettingsKey, userScopeId: currentUserScopeId)
        )
    }

    func switchUser(to userScopeId: String) {
        guard currentUserScopeId != userScopeId else { return }
        currentUserScopeId = userScopeId
        settings = Self.loadSettings(
            userDefaults: userDefaults,
            decoder: decoder,
            key: Self.settingsKey(baseKey: baseSettingsKey, userScopeId: userScopeId)
        )
    }

    func updateMonthlyBudget(_ amount: Double) {
        settings.monthlyBudget = max(0, amount)
        persist()
    }

    func updateCurrencyCode(_ code: String) {
        settings.currencyCode = CurrencyOption.normalizedCode(code)
        persist()
    }

    func updateAppearance(_ appearance: AppearanceOption) {
        settings.appearance = appearance
        persist()
    }

    func replaceSettings(_ settings: BudgetSettings) {
        self.settings = settings
        persist()
    }

    func budgetAmount(for category: TransactionCategory) -> Double {
        settings.categoryBudgets[category.rawValue] ?? 0
    }

    func hiddenExpenseCategoryRawValues() -> Set<String> {
        Set(
            settings.categoryBudgets.keys.compactMap { key in
                guard TransactionCategory.isHiddenMarkerKey(key) else { return nil }
                return String(key.dropFirst(TransactionCategory.hiddenCategoryPrefix.count))
            }
        )
    }

    func updateCategoryBudget(_ amount: Double, for category: TransactionCategory) {
        settings.categoryBudgets[category.rawValue] = max(0, amount)
        persist()
    }

    func updateCategoryBudgets(_ values: [TransactionCategory: Double]) {
        var mapped: [String: Double] = settings.categoryBudgets
        for (category, amount) in values {
            mapped[category.rawValue] = max(0, amount)
        }
        settings.categoryBudgets = mapped
        persist()
    }

    func upsertCategory(_ category: TransactionCategory, budgetAmount: Double = 0) {
        settings.categoryBudgets[category.rawValue] = max(0, budgetAmount)
        settings.categoryBudgets.removeValue(forKey: TransactionCategory.hiddenMarkerKey(for: category))
        persist()
    }

    func renameCategory(from oldCategory: TransactionCategory, to newCategory: TransactionCategory) {
        guard oldCategory != newCategory else { return }
        let currentBudget = settings.categoryBudgets[oldCategory.rawValue] ?? 0
        settings.categoryBudgets[newCategory.rawValue] = currentBudget

        if oldCategory.isBuiltInExpenseCategory {
            settings.categoryBudgets[TransactionCategory.hiddenMarkerKey(for: oldCategory)] = 1
        } else {
            settings.categoryBudgets.removeValue(forKey: oldCategory.rawValue)
        }

        settings.categoryBudgets.removeValue(forKey: TransactionCategory.hiddenMarkerKey(for: newCategory))
        persist()
    }

    func removeCategory(_ category: TransactionCategory) {
        guard !category.isProtectedCategory else { return }

        if category.isBuiltInExpenseCategory {
            settings.categoryBudgets[TransactionCategory.hiddenMarkerKey(for: category)] = 1
            settings.categoryBudgets[category.rawValue] = 0
        } else {
            settings.categoryBudgets.removeValue(forKey: category.rawValue)
        }

        persist()
    }

    func resetSettings() {
        settings = .default
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(settings) else { return }
        userDefaults.set(data, forKey: Self.settingsKey(baseKey: baseSettingsKey, userScopeId: currentUserScopeId))
    }

    private static func settingsKey(baseKey: String, userScopeId: String) -> String {
        "\(baseKey).\(userScopeId)"
    }

    private static func loadSettings(
        userDefaults: UserDefaults,
        decoder: JSONDecoder,
        key: String
    ) -> BudgetSettings {
        if let data = userDefaults.data(forKey: key),
           let decoded = try? decoder.decode(BudgetSettings.self, from: data) {
            return decoded
        }
        return .default
    }
}

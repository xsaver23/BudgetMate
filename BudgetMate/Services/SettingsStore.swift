import Foundation

struct SettingsCloudSyncToken: Equatable {
    let budgetScopeId: String
    let revision: Int
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: BudgetSettings

    private let baseSettingsKey = "budgetmate.settings"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userDefaults: UserDefaults
    private var currentUserScopeId = "local"
    private let cloudDirtyKey = "budgetmate.settingsCloudDirty"
    private let cloudRevisionKey = "budgetmate.settingsCloudRevision"

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
        // Monthly budget is derived from visible category budgets.
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
        if self.settings != settings {
            self.settings = settings
            persist(markCloudDirty: false)
        } else {
            markCurrentScopeCloudClean()
        }
    }

    var pendingCloudSyncToken: SettingsCloudSyncToken? {
        guard userDefaults.bool(forKey: scopedCloudDirtyKey(for: currentUserScopeId)) else {
            return nil
        }
        return SettingsCloudSyncToken(
            budgetScopeId: currentUserScopeId,
            revision: userDefaults.integer(forKey: scopedCloudRevisionKey(for: currentUserScopeId))
        )
    }

    func markCloudSyncSucceeded(_ token: SettingsCloudSyncToken) {
        let revisionKey = scopedCloudRevisionKey(for: token.budgetScopeId)
        guard userDefaults.integer(forKey: revisionKey) == token.revision else {
            return
        }
        userDefaults.set(false, forKey: scopedCloudDirtyKey(for: token.budgetScopeId))
    }

    func budgetAmount(for category: TransactionCategory) -> Double {
        settings.categoryBudgets[category.rawValue] ?? 0
    }

    func budgetAmount(for category: TransactionCategory, in monthDate: Date) -> Double {
        let monthKey = BudgetSettings.monthKey(for: monthDate)
        return settings.categoryBudgets(forMonthKey: monthKey)[category.rawValue] ?? 0
    }

    func categoryBudgets(in monthDate: Date) -> [String: Double] {
        settings.categoryBudgets(forMonthKey: BudgetSettings.monthKey(for: monthDate))
    }

    func monthlyBudget(in monthDate: Date) -> Double {
        settings.monthlyBudget(forMonthKey: BudgetSettings.monthKey(for: monthDate))
    }

    func categoryEmoji(for category: TransactionCategory) -> String? {
        settings.emoji(for: category)
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

    func updateCategoryBudget(_ amount: Double, for category: TransactionCategory, in monthDate: Date) {
        let monthKey = BudgetSettings.monthKey(for: monthDate)
        settings.categoryBudgets[BudgetSettings.monthBudgetKey(monthKey: monthKey, categoryRawValue: category.rawValue)] = max(0, amount)
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

    func updateCategoryBudgets(_ values: [TransactionCategory: Double], in monthDate: Date) {
        let monthKey = BudgetSettings.monthKey(for: monthDate)
        var mapped = settings.categoryBudgets
        for (category, amount) in values {
            mapped[BudgetSettings.monthBudgetKey(monthKey: monthKey, categoryRawValue: category.rawValue)] = max(0, amount)
        }
        settings.categoryBudgets = mapped
        persist()
    }

    func upsertCategory(_ category: TransactionCategory, budgetAmount: Double = 0, emoji: String? = nil) {
        settings.categoryBudgets[category.rawValue] = max(0, budgetAmount)
        settings.categoryBudgets.removeValue(forKey: TransactionCategory.hiddenMarkerKey(for: category))
        updateCategoryEmojiInMemory(emoji, for: category)
        persist()
    }

    func renameCategory(from oldCategory: TransactionCategory, to newCategory: TransactionCategory, emoji: String? = nil) {
        guard oldCategory != newCategory else { return }
        let currentBudget = settings.categoryBudgets[oldCategory.rawValue] ?? 0
        let currentEmoji = emoji ?? settings.categoryEmojis[oldCategory.rawValue]
        settings.categoryBudgets[newCategory.rawValue] = currentBudget
        for (key, amount) in settings.categoryBudgets {
            guard let scopedKey = BudgetSettings.monthAndCategory(from: key),
                  scopedKey.categoryRawValue == oldCategory.rawValue else {
                continue
            }
            settings.categoryBudgets[BudgetSettings.monthBudgetKey(monthKey: scopedKey.monthKey, categoryRawValue: newCategory.rawValue)] = amount
            settings.categoryBudgets.removeValue(forKey: key)
        }
        updateCategoryEmojiInMemory(currentEmoji, for: newCategory)

        if oldCategory.isBuiltInExpenseCategory {
            settings.categoryBudgets[TransactionCategory.hiddenMarkerKey(for: oldCategory)] = 1
            settings.categoryEmojis.removeValue(forKey: oldCategory.rawValue)
        } else {
            settings.categoryBudgets.removeValue(forKey: oldCategory.rawValue)
            settings.categoryEmojis.removeValue(forKey: oldCategory.rawValue)
        }

        settings.categoryBudgets.removeValue(forKey: TransactionCategory.hiddenMarkerKey(for: newCategory))
        persist()
    }

    func updateCategoryEmoji(_ emoji: String?, for category: TransactionCategory) {
        updateCategoryEmojiInMemory(emoji, for: category)
        persist()
    }

    private func updateCategoryEmojiInMemory(_ emoji: String?, for category: TransactionCategory) {
        let trimmed = emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            settings.categoryEmojis.removeValue(forKey: category.rawValue)
        } else if trimmed.isSingleEmoji {
            settings.categoryEmojis[category.rawValue] = trimmed
        }
    }

    func removeCategory(_ category: TransactionCategory) {
        guard !category.isProtectedCategory else { return }

        if category.isBuiltInExpenseCategory {
            settings.categoryBudgets[TransactionCategory.hiddenMarkerKey(for: category)] = 1
            settings.categoryBudgets[category.rawValue] = 0
            settings.categoryEmojis.removeValue(forKey: category.rawValue)
        } else {
            settings.categoryBudgets.removeValue(forKey: category.rawValue)
            settings.categoryEmojis.removeValue(forKey: category.rawValue)
        }
        settings.categoryBudgets.keys
            .filter { key in
                BudgetSettings.monthAndCategory(from: key)?.categoryRawValue == category.rawValue
            }
            .forEach { settings.categoryBudgets.removeValue(forKey: $0) }

        persist()
    }

    func resetSettings() {
        settings = .default
        persist()
    }

    private func persist(markCloudDirty: Bool = true) {
        guard let data = try? encoder.encode(settings) else { return }
        userDefaults.set(data, forKey: Self.settingsKey(baseKey: baseSettingsKey, userScopeId: currentUserScopeId))
        if markCloudDirty {
            let revisionKey = scopedCloudRevisionKey(for: currentUserScopeId)
            userDefaults.set(userDefaults.integer(forKey: revisionKey) + 1, forKey: revisionKey)
            userDefaults.set(true, forKey: scopedCloudDirtyKey(for: currentUserScopeId))
        } else {
            markCurrentScopeCloudClean()
        }
    }

    private func markCurrentScopeCloudClean() {
        userDefaults.set(false, forKey: scopedCloudDirtyKey(for: currentUserScopeId))
    }

    private func scopedCloudDirtyKey(for scopeId: String) -> String {
        "\(cloudDirtyKey).\(scopeId)"
    }

    private func scopedCloudRevisionKey(for scopeId: String) -> String {
        "\(cloudRevisionKey).\(scopeId)"
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

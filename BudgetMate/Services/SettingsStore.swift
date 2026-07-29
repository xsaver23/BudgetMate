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
    private let verifiedCurrencySource: (any VerifiedCurrencySource)?
    private let anomalyReportURL: URL?
    private(set) var lastMoneyMigrationAnomalyReport = LegacyMoneyAnomalyReport()
    private var currentUserScopeId = "local"
    private var hasEstablishedCurrencyBaseline: Bool
    private let cloudDirtyKey = "budgetmate.settingsCloudDirty"
    private let cloudRevisionKey = "budgetmate.settingsCloudRevision"
    private let currencyCloudBaselineObservedKey = "budgetmate.currencyCloudBaselineObserved"
    private let financialHistoryObservedKey = "budgetmate.financialHistoryObserved"

    init(
        userDefaults: UserDefaults = .standard,
        verifiedCurrencySource: (any VerifiedCurrencySource)? = nil,
        anomalyReportURL: URL? = nil
    ) {
        let resolvedAnomalyReportURL = anomalyReportURL ?? LegacyMoneyAnomalyStore.settingsURL()
        let loaded = Self.loadSettings(
            userDefaults: userDefaults,
            decoder: JSONDecoder(),
            encoder: JSONEncoder(),
            key: Self.settingsKey(baseKey: "budgetmate.settings", userScopeId: "local"),
            currencySource: verifiedCurrencySource,
            anomalyReportURL: resolvedAnomalyReportURL
        )
        self.verifiedCurrencySource = verifiedCurrencySource
        self.anomalyReportURL = resolvedAnomalyReportURL
        self.userDefaults = userDefaults
        settings = loaded.settings ?? .default
        lastMoneyMigrationAnomalyReport = loaded.report
        hasEstablishedCurrencyBaseline = loaded.settings != nil
    }

    func switchUser(to userScopeId: String) {
        guard currentUserScopeId != userScopeId else { return }
        currentUserScopeId = userScopeId
        let loaded = Self.loadSettings(
            userDefaults: userDefaults,
            decoder: decoder,
            encoder: encoder,
            key: Self.settingsKey(baseKey: baseSettingsKey, userScopeId: userScopeId),
            currencySource: verifiedCurrencySource,
            anomalyReportURL: anomalyReportURL
        )
        settings = loaded.settings ?? .default
        lastMoneyMigrationAnomalyReport = loaded.report
        hasEstablishedCurrencyBaseline = loaded.settings != nil
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

    func replaceSettings(
        _ incomingSettings: BudgetSettings,
        preservingEstablishedCurrency shouldPreserveCurrency: Bool
    ) {
        var resolvedSettings = incomingSettings
        let hasCurrencyConflict =
            shouldPreserveCurrency &&
            hasEstablishedCurrencyBaseline &&
            incomingSettings.currencyCode != settings.currencyCode

        if hasCurrencyConflict {
            resolvedSettings.currencyCode = settings.currencyCode
        }

        if settings != resolvedSettings ||
            hasCurrencyConflict ||
            !hasEstablishedCurrencyBaseline {
            settings = resolvedSettings
            // When an older client changed the cloud currency, keep the
            // established local baseline and queue it to repair the cloud row.
            persist(markCloudDirty: hasCurrencyConflict)
        } else {
            markCurrentScopeCloudClean()
        }
    }

    func hasEstablishedCurrencyConflict(with incomingSettings: BudgetSettings) -> Bool {
        hasEstablishedCurrencyBaseline &&
            incomingSettings.currencyCode != settings.currencyCode
    }

    var hasObservedCloudSettingsBaseline: Bool {
        userDefaults.bool(
            forKey: scopedCurrencyCloudBaselineObservedKey(for: currentUserScopeId)
        )
    }

    var hasObservedFinancialHistory: Bool {
        userDefaults.bool(
            forKey: scopedFinancialHistoryObservedKey(for: currentUserScopeId)
        )
    }

    func recordCloudSettingsBaseline(
        _ cloudSettings: BudgetSettings?,
        hasRemoteFinancialRecords: Bool = false
    ) {
        userDefaults.set(
            true,
            forKey: scopedCurrencyCloudBaselineObservedKey(for: currentUserScopeId)
        )
        let hasRemoteFinancialHistory =
            hasRemoteFinancialRecords ||
            cloudSettings?.categoryBudgets.isEmpty == false
        guard hasRemoteFinancialHistory else {
            return
        }

        let hadPendingLocalChanges = pendingCloudSyncToken != nil
        recordFinancialHistoryObserved()
        guard let cloudSettings else {
            return
        }
        guard settings.currencyCode != cloudSettings.currencyCode else {
            return
        }

        // Remote financial records prove that the household already has a
        // currency baseline. Keep unrelated local edits pending, but never let
        // a pre-hydration default or stale currency overwrite that code.
        settings.currencyCode = cloudSettings.currencyCode
        persist(markCloudDirty: hadPendingLocalChanges)
    }

    func recordFinancialHistoryObserved() {
        userDefaults.set(
            true,
            forKey: scopedFinancialHistoryObservedKey(for: currentUserScopeId)
        )
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
        var hidden: Set<String> = Set(
            settings.categoryBudgets.keys.compactMap { key in
                guard TransactionCategory.isHiddenMarkerKey(key) else { return nil }
                return String(key.dropFirst(TransactionCategory.hiddenCategoryPrefix.count))
            }
        )
        hidden.formUnion(
            settings.categoryVisibility.compactMap { category, visibility in
                visibility == .hidden ? category : nil
            }
        )
        return hidden
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
        settings.categoryVisibility[category.rawValue] = .visible
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
            settings.categoryVisibility[oldCategory.rawValue] = .hidden
            settings.categoryEmojis.removeValue(forKey: oldCategory.rawValue)
        } else {
            settings.categoryBudgets.removeValue(forKey: oldCategory.rawValue)
            settings.categoryVisibility.removeValue(forKey: oldCategory.rawValue)
            settings.categoryEmojis.removeValue(forKey: oldCategory.rawValue)
        }

        settings.categoryBudgets.removeValue(forKey: TransactionCategory.hiddenMarkerKey(for: newCategory))
        settings.categoryVisibility[newCategory.rawValue] = .visible
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
            settings.categoryVisibility[category.rawValue] = .hidden
            settings.categoryEmojis.removeValue(forKey: category.rawValue)
        } else {
            settings.categoryBudgets.removeValue(forKey: category.rawValue)
            settings.categoryVisibility.removeValue(forKey: category.rawValue)
            settings.categoryEmojis.removeValue(forKey: category.rawValue)
        }
        settings.categoryBudgets.keys
            .filter { key in
                BudgetSettings.monthAndCategory(from: key)?.categoryRawValue == category.rawValue
            }
            .forEach { settings.categoryBudgets.removeValue(forKey: $0) }

        persist()
    }

    func resetSettings(preservingCurrencyCode: Bool = false) {
        let currentCurrencyCode = settings.currencyCode
        settings = .default
        if preservingCurrencyCode {
            settings.currencyCode = currentCurrencyCode
        }
        persist()
    }

    private func persist(markCloudDirty: Bool = true) {
        let migration = LegacyBudgetSettingsMigrator.migrate(
            settings,
            currencySource: verifiedCurrencySource
        )
        settings = migration.settings
        lastMoneyMigrationAnomalyReport = migration.anomalyReport
        if let anomalyReportURL {
            try? LegacyMoneyAnomalyStore.save(migration.anomalyReport, at: anomalyReportURL)
        }
        guard let data = try? encoder.encode(settings) else { return }
        userDefaults.set(data, forKey: Self.settingsKey(baseKey: baseSettingsKey, userScopeId: currentUserScopeId))
        hasEstablishedCurrencyBaseline = true
        if !settings.categoryBudgets.isEmpty {
            recordFinancialHistoryObserved()
        }
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

    private func scopedCurrencyCloudBaselineObservedKey(for scopeId: String) -> String {
        "\(currencyCloudBaselineObservedKey).\(scopeId)"
    }

    private func scopedFinancialHistoryObservedKey(for scopeId: String) -> String {
        "\(financialHistoryObservedKey).\(scopeId)"
    }

    private static func settingsKey(baseKey: String, userScopeId: String) -> String {
        "\(baseKey).\(userScopeId)"
    }

    private struct SettingsLoad {
        let settings: BudgetSettings?
        let report: LegacyMoneyAnomalyReport
    }

    private static func loadSettings(
        userDefaults: UserDefaults,
        decoder: JSONDecoder,
        encoder: JSONEncoder,
        key: String,
        currencySource: (any VerifiedCurrencySource)?,
        anomalyReportURL: URL?
    ) -> SettingsLoad {
        guard let data = userDefaults.data(forKey: key) else {
            return SettingsLoad(settings: nil, report: LegacyMoneyAnomalyReport())
        }
        guard let decoded = try? decoder.decode(BudgetSettings.self, from: data) else {
            var report = LegacyMoneyAnomalyReport()
            report.append(
                entity: "budgetSettings",
                identifier: key,
                field: "blob",
                reason: .malformedSettingsBlob
            )
            if let anomalyReportURL {
                try? LegacyMoneyAnomalyStore.save(report, at: anomalyReportURL)
            }
            return SettingsLoad(settings: nil, report: report)
        }

        let migration = LegacyBudgetSettingsMigrator.migrate(
            decoded,
            currencySource: currencySource
        )
        if let migratedData = try? encoder.encode(migration.settings) {
            userDefaults.set(migratedData, forKey: key)
        }
        if let anomalyReportURL {
            try? LegacyMoneyAnomalyStore.save(migration.anomalyReport, at: anomalyReportURL)
        }
        return SettingsLoad(settings: migration.settings, report: migration.anomalyReport)
    }
}

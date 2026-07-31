import SwiftData
import SwiftUI

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var memberViewModel: MemberViewModel
    @EnvironmentObject private var monthSelectionStore: MonthSelectionStore
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore
    @EnvironmentObject private var appRefreshStore: AppRefreshStore
    var onOpenSettings: () -> Void = {}
    let budgetScopeId: String

    @Query private var transactions: [Transaction]
    @Query private var settlementRecords: [Settlement]
    @State private var categoryBudgetInputs: [String: String] = [:]
    @State private var isEditingCategories = false
    @State private var categoryBeingEdited: TransactionCategory?
    @State private var isShowingCategoryEditor = false
    @State private var saveMessage: String?
    @State private var tabMetrics = BudgetTabMetrics()

    init(budgetScopeId: String, onOpenSettings: @escaping () -> Void = {}) {
        self.budgetScopeId = budgetScopeId
        self.onOpenSettings = onOpenSettings
        _transactions = Query(
            filter: #Predicate<Transaction> { $0.ownerUserId == budgetScopeId },
            sort: \Transaction.date,
            order: .reverse
        )
        _settlementRecords = Query(
            filter: #Predicate<Settlement> { $0.ownerUserId == budgetScopeId }
        )
    }

    // Queries are already scoped to the active budget in init.
    private var scopedTransactions: [Transaction] { transactions }
    private var scopedSettlementRecords: [Settlement] { settlementRecords }

    private var totalExpenses: Double { tabMetrics.totalExpenses }

    private var remainingBudget: Double {
        monthlyBudget - totalExpenses
    }

    private var budgetProgress: Double {
        guard monthlyBudget > 0 else { return 0 }
        return min(max(totalExpenses / monthlyBudget, 0), 1)
    }

    private var monthlyBudget: Double {
        settingsStore.monthlyBudget(in: monthSelectionStore.selectedMonthDate)
    }

    private var metricsRefreshToken: String {
        let dataHash = FinancialDataFingerprint.hash(
            transactions: scopedTransactions,
            settlements: scopedSettlementRecords
        )
        return "\(dataHash)-\(monthSelectionStore.selectedMonthKey)-\(authStore.currentBudgetScopeId)"
    }

    private var categories: [TransactionCategory] {
        let hiddenRawValues = settingsStore.hiddenExpenseCategoryRawValues()
        let builtInCategories = TransactionCategory.expenseCategories
            .filter { !hiddenRawValues.contains($0.rawValue) }
        let monthBudgets = settingsStore.categoryBudgets(in: monthSelectionStore.selectedMonthDate)
        let customBudgetKeys = Set(settingsStore.settings.legacyCategoryBudgets.keys).union(monthBudgets.keys)
        let customCategories = customBudgetKeys
            .filter { key in
                !TransactionCategory.builtInRawValues.contains(key) &&
                !BudgetSettings.isInternalBudgetKey(key)
            }
            .map(TransactionCategory.init(rawValue:))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        return builtInCategories + customCategories
    }

    private var recordMutationDecision: RecordMutationDecision {
        SharedRecordMutationCapability.decision(
            currentUserScopeId: authStore.currentUserScopeId,
            activeBudgetScopeId: authStore.currentBudgetScopeId,
            recordBudgetScopeId: budgetScopeId,
            members: memberViewModel.members,
            // Gate C governs transaction/settlement mutation only; preserve
            // the existing owner-only settings capability during rollout.
            serverGateEnabled: true
        )
    }

    private var hasConfiguredCategoryBudgets: Bool {
        categories.contains { configuredBudget(for: $0) > 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AppTopBar(
                        member: memberViewModel.activeMember,
                        onProfileTap: onOpenSettings
                    )

                    VStack(spacing: 16) {
                        MonthSliderView()
                        if !tabMetrics.anomalies.isEmpty {
                            Label("Some money records need attention", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BudgetBeaverPalette.amountRed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        monthlyBudgetCard
                        monthlySpentCard
                        categoryBudgetsCard
                        memberSpendingCard
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
            .refreshable {
                await appRefreshStore.refreshCurrentBudget(forceSync: true)
            }
            .background(AppTheme.background)
            .statusBarScrim()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: metricsRefreshToken) {
                refreshTabMetrics()
            }
            .onAppear(perform: loadCategoryBudgetInputs)
            .sheet(isPresented: $isShowingCategoryEditor) {
                CategoryEditorView(
                    mode: categoryBeingEdited == nil ? .add : .edit,
                    initialName: categoryBeingEdited?.displayName ?? "",
                    initialEmoji: categoryBeingEdited.flatMap { settingsStore.categoryEmoji(for: $0) } ?? "",
                    onCancel: {
                        isShowingCategoryEditor = false
                        categoryBeingEdited = nil
                    },
                    onSave: { name, emoji in
                        saveCategoryName(name, emoji: emoji)
                    }
                )
            }
            .alert("Budget", isPresented: saveAlertBinding) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveMessage ?? "")
            }
        }
    }

    private var monthlyBudgetCard: some View {
        beaverCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "calendar.badge.clock")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.brand)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.brandSoft, in: Circle())

                VStack(alignment: .leading, spacing: 8) {
                    Text("MONTHLY BUDGET")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.6))

                    Text(formattedAmount(monthlyBudget))
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(BudgetBeaverPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var monthlySpentCard: some View {
        beaverCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(BudgetBeaverPalette.wood)

                        Text("This Month")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(BudgetBeaverPalette.ink)
                    }

                    Spacer()

                    Text(remainingBudget >= 0 ? "ON TRACK" : "OVER")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(remainingBudget >= 0 ? AppTheme.brand : BudgetBeaverPalette.amountRed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(remainingBudget >= 0 ? AppTheme.incomeTint : AppTheme.expenseTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                HStack(spacing: 12) {
                    budgetSummaryTile(
                        title: "Spent",
                        value: totalExpenses,
                        tint: AppTheme.expense,
                        systemImage: "arrow.up.right"
                    )
                    budgetSummaryTile(
                        title: "Remaining",
                        value: remainingBudget,
                        tint: remainingBudget >= 0 ? AppTheme.income : AppTheme.expense,
                        systemImage: remainingBudget >= 0 ? "checkmark" : "exclamationmark"
                    )
                }

                ProgressView(value: budgetProgress)
                    .tint(remainingBudget >= 0 ? BudgetBeaverPalette.wood : BudgetBeaverPalette.amountRed)
                    .accessibilityLabel("Monthly budget progress")
                    .accessibilityValue(budgetProgressAccessibilityValue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var categoryBudgetsCard: some View {
        beaverCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(BudgetBeaverPalette.wood)

                        Text("Category Budgets")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(BudgetBeaverPalette.ink)
                    }

                    Spacer()

                    Button(isEditingCategories ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isEditingCategories {
                                saveCategoryBudgets(showMessage: false)
                            } else {
                                loadCategoryBudgetInputs()
                            }
                            isEditingCategories.toggle()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.brand)
                    .buttonStyle(PressableButtonStyle(scale: 0.97))
                }

                Text("Spending is tracked month by month.")
                    .font(.caption)
                    .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.7))

                if isEditingCategories, !recordMutationDecision.isAllowed {
                    Label(
                        "Only the household owner can rename or remove shared transaction categories.",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.78))
                    .accessibilityIdentifier("budget.sharedCategoryReadOnly")
                }

                if !hasConfiguredCategoryBudgets && !isEditingCategories {
                    budgetEmptyState(
                        systemImage: "slider.horizontal.below.rectangle",
                        title: "No category budgets yet",
                        message: "Tap Edit to add limits for groceries, restaurants, shopping, and other categories."
                    )
                }

                ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                    if isEditingCategories {
                        categoryBudgetRow(for: category)
                    } else {
                        categoryNavigationRow(for: category)
                    }

                    if index < categories.count - 1 {
                        Divider()
                    }
                }

                if isEditingCategories {
                    Button {
                        categoryBeingEdited = nil
                        isShowingCategoryEditor = true
                    } label: {
                        Label("Add Category", systemImage: "plus.circle.fill")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.brand)
                    .buttonStyle(PressableButtonStyle(scale: 0.97))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func categoryBudgetRow(for category: TransactionCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CategoryIconView(
                    category: category,
                    emoji: settingsStore.categoryEmoji(for: category),
                    size: 28
                )

                if isEditingCategories {
                    if recordMutationDecision.isAllowed {
                        Button {
                            categoryBeingEdited = category
                            isShowingCategoryEditor = true
                        } label: {
                            HStack(spacing: 6) {
                                Text(category.displayName)
                                    .font(.subheadline.weight(.bold))
                                Image(systemName: "pencil")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(BudgetBeaverPalette.ink)
                        }
                        .buttonStyle(.plain)
                        .buttonStyle(PressableButtonStyle(scale: 0.97))
                    } else {
                        Text(category.displayName)
                            .font(.subheadline.weight(.bold))
                        .foregroundStyle(BudgetBeaverPalette.ink)
                    }
                } else {
                    Text(category.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BudgetBeaverPalette.ink)
                }

                Spacer()

                if isEditingCategories,
                   !category.isProtectedCategory,
                   recordMutationDecision.isAllowed {
                    Button(role: .destructive) {
                        removeCategory(category)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .buttonStyle(PressableButtonStyle(scale: 0.9))
                }

                if isEditingCategories {
                    TextField(
                        CurrencyFormatter.numberString(
                            0,
                            currencyCode: settingsStore.settings.currencyCode
                        ),
                        text: budgetBinding(for: category)
                    )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 96)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(budgetDisplayValue(for: category))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(configuredBudget(for: category) > 0 ? BudgetBeaverPalette.ink : BudgetBeaverPalette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 96, alignment: .trailing)
                }
            }

            HStack {
                Text("Spent: \(formattedAmount(monthlySpent(for: category)))")
                    .font(.caption)
                    .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.7))
                Spacer()
                Text("Remaining: \(formattedAmount(remainingAmount(for: category)))")
                    .font(.caption)
                    .foregroundStyle(remainingAmount(for: category) >= 0 ? BudgetBeaverPalette.wood.opacity(0.7) : BudgetBeaverPalette.amountRed)
            }

            ProgressView(value: budgetProgress(for: category))
                .tint(remainingAmount(for: category) >= 0 ? CategoryColor.color(for: category) : BudgetBeaverPalette.amountRed)
                .accessibilityLabel("\(category.displayName) budget progress")
                .accessibilityValue(categoryProgressAccessibilityValue(for: category))
        }
        .padding(.vertical, 4)
    }

    private func categoryNavigationRow(for category: TransactionCategory) -> some View {
        NavigationLink {
            BudgetCategoryTransactionListView(
                categoryRawValue: category.rawValue,
                budgetScopeId: budgetScopeId,
                selectedMonthKey: monthSelectionStore.selectedMonthKey,
                selectedMonthTitle: monthSelectionStore.selectedMonthTitle,
                emoji: settingsStore.categoryEmoji(for: category),
                breakdown: tabMetrics.categoryBreakdown(
                    for: category,
                    budgetScopeId: budgetScopeId,
                    currencyCode: settingsStore.settings.currencyCode
                ),
                currencyCode: settingsStore.settings.currencyCode
            )
        } label: {
            categoryBudgetRow(for: category)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.displayName) budget category")
        .accessibilityValue(
            "\(formattedAmount(monthlySpent(for: category))) spent, " +
                "\(formattedAmount(configuredBudget(for: category))) budget"
        )
        .accessibilityHint(
            "Double-tap to view \(category.displayName.lowercased()) expenses for " +
                "\(monthSelectionStore.selectedMonthTitle.lowercased())"
        )
    }

    private var memberSpendingCard: some View {
        beaverCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(BudgetBeaverPalette.wood)

                    Text("Member Spending")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(BudgetBeaverPalette.ink)

                    Spacer()

                    Text("THIS MONTH")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.warningTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                ForEach(tabMetrics.expensesByMember, id: \.member.id) { entry in
                    HStack(spacing: 10) {
                        MemberInitialsBadge(
                            initials: entry.member.displayInitials,
                            colorHex: entry.member.colorHex,
                            size: 20,
                            accessibilityLabel: "Member \(entry.member.displayName)"
                        )

                        Text(entry.member.displayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BudgetBeaverPalette.ink)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(formattedAmount(entry.total))
                                .font(.subheadline.weight(.black))
                                .foregroundStyle(BudgetBeaverPalette.ink)
                            if let balance = balanceCaption(for: entry.member) {
                                Text(balance.text)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(balance.color)
                            }
                        }
                    }
                    .padding(12)
                    .background(BudgetBeaverPalette.bank, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(BudgetBeaverPalette.border, lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func beaverCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .background(BudgetBeaverPalette.paper, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(BudgetBeaverPalette.border, lineWidth: 1)
            )
    }

    private func budgetSummaryTile(
        title: String,
        value: Double,
        tint: Color,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: systemImage)
                .font(.headline.weight(.black))
                .foregroundStyle(AppTheme.brand)
                .frame(width: 40, height: 40)
                .background(AppTheme.brandSoft, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.ink)

                Text(formattedAmount(value))
                    .font(.title3.weight(.black))
                    .foregroundStyle(BudgetBeaverPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.surfaceStroke, lineWidth: 1)
        )
    }

    private func refreshTabMetrics() {
        tabMetrics = BudgetTabMetrics.compute(
            transactions: scopedTransactions,
            settlements: scopedSettlementRecords,
            members: memberViewModel.members,
            monthInterval: monthSelectionStore.monthInterval(),
            currencyCode: settingsStore.settings.currencyCode,
            budgetScopeId: budgetScopeId,
            calendar: monthSelectionStore.selectionCalendar
        )
    }

    private func balanceCaption(for member: BudgetMember) -> (text: String, color: Color)? {
        let minorUnits = tabMetrics.netBalances[member.id] ?? 0
        guard minorUnits != 0 else { return nil }
        let value = MoneyAccounting.formatted(
            minorUnits: minorUnits == Int64.min ? Int64.max : abs(minorUnits),
            currencyCode: settingsStore.settings.currencyCode
        ) ?? formattedAmount(0)
        if minorUnits > 0 {
            return ("owed \(value)", BudgetBeaverPalette.forest)
        } else {
            return ("owes \(value)", BudgetBeaverPalette.amountRed)
        }
    }

    private func loadCategoryBudgetInputs() {
        var values: [String: String] = [:]
        for category in categories {
            let budget = configuredBudget(for: category)
            values[category.rawValue] = budget > 0
                ? CurrencyFormatter.numberString(
                    budget,
                    currencyCode: settingsStore.settings.currencyCode,
                    locale: Locale(identifier: "en_US_POSIX")
                )
                : ""
        }
        categoryBudgetInputs = values
    }

    private func saveCategoryBudgets(showMessage: Bool = true) {
        var updates: [TransactionCategory: Double] = [:]
        for category in categories {
            let raw = categoryBudgetInputs[category.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty {
                updates[category] = 0
            } else if let value = Double(raw) {
                updates[category] = value
            }
        }

        settingsStore.updateCategoryBudgets(updates, in: monthSelectionStore.selectedMonthDate)
        loadCategoryBudgetInputs()
        saveSettingsToCloud()
        if showMessage {
            saveMessage = "Category budgets updated."
        }
    }

    private func saveCategoryName(_ name: String, emoji: String?) {
        guard let rawValue = TransactionCategory.customRawValue(from: name) else {
            saveMessage = "Enter a category name."
            return
        }
        let normalizedEmoji = emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard normalizedEmoji.isEmpty || normalizedEmoji.isSingleEmoji else {
            saveMessage = "Use one emoji for the category icon."
            return
        }

        let newCategory = TransactionCategory(rawValue: rawValue)
        let oldCategory = categoryBeingEdited
        if let oldCategory,
           oldCategory != newCategory,
           !recordMutationDecision.isAllowed {
            saveMessage = recordMutationDecision.readOnlyMessage
            return
        }
        let duplicate = categories.contains { category in
            category != oldCategory &&
            (
                category.rawValue.localizedCaseInsensitiveCompare(newCategory.rawValue) == .orderedSame ||
                category.displayName.localizedCaseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            )
        }
        guard !duplicate else {
            saveMessage = "That category already exists."
            return
        }

        if let oldCategory, oldCategory == newCategory {
            settingsStore.updateCategoryEmoji(normalizedEmoji.isEmpty ? nil : normalizedEmoji, for: oldCategory)
        } else if let oldCategory {
            settingsStore.renameCategory(from: oldCategory, to: newCategory, emoji: normalizedEmoji.isEmpty ? nil : normalizedEmoji)
            reassignTransactions(from: oldCategory, to: newCategory)
        } else {
            settingsStore.upsertCategory(newCategory, emoji: normalizedEmoji.isEmpty ? nil : normalizedEmoji)
        }

        loadCategoryBudgetInputs()
        syncSettingsAndChangedTransactions()
        categoryBeingEdited = nil
        isShowingCategoryEditor = false
    }

    private func removeCategory(_ category: TransactionCategory) {
        guard !category.isProtectedCategory else { return }
        guard recordMutationDecision.isAllowed else {
            saveMessage = recordMutationDecision.readOnlyMessage
            return
        }

        settingsStore.removeCategory(category)
        categoryBudgetInputs.removeValue(forKey: category.rawValue)
        reassignTransactions(from: category, to: .other)
        syncSettingsAndChangedTransactions()
        saveMessage = "\(category.displayName) was removed. Existing transactions moved to Other."
    }

    private func reassignTransactions(from oldCategory: TransactionCategory, to newCategory: TransactionCategory) {
        let changedTransactions = scopedTransactions.filter { $0.category == oldCategory }
        changedTransactions.forEach { transaction in
            transaction.category = newCategory
        }
        cloudSyncStore.saveTransactions(
            changedTransactions,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
        do {
            try modelContext.save()
        } catch {
            cloudSyncStore.recordSyncIssue(error, context: "Saving reassigned categories")
        }
        refreshTabMetrics()
    }

    private func syncSettingsAndChangedTransactions() {
        saveSettingsToCloud()
    }

    private func saveSettingsToCloud() {
        guard settingsStore.hasObservedCloudSettingsBaseline else {
            return
        }

        let syncToken = settingsStore.pendingCloudSyncToken
        cloudSyncStore.saveSettings(
            settingsStore.settings,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId,
            onSuccess: {
                if let syncToken {
                    settingsStore.markCloudSyncSucceeded(syncToken)
                }
            }
        )
    }

    private func budgetBinding(for category: TransactionCategory) -> Binding<String> {
        Binding(
            get: { categoryBudgetInputs[category.rawValue] ?? "" },
            set: {
                categoryBudgetInputs[category.rawValue] = Self.sanitizedMoneyText(
                    $0,
                    currencyCode: settingsStore.settings.currencyCode
                )
            }
        )
    }

    private static func sanitizedMoneyText(_ text: String, currencyCode: String) -> String {
        let maximumFractionDigits = (try? CurrencyMetadata(code: currencyCode))?.fractionDigits ?? 2
        var result = ""
        var hasDecimalSeparator = false
        var fractionalDigitCount = 0

        for character in text {
            if character.isNumber {
                if hasDecimalSeparator {
                    guard maximumFractionDigits > 0,
                          fractionalDigitCount < maximumFractionDigits else { continue }
                    fractionalDigitCount += 1
                }
                result.append(character)
            } else if character == "." || character == "," {
                if maximumFractionDigits == 0 {
                    hasDecimalSeparator = true
                    continue
                }
                guard !hasDecimalSeparator else { continue }
                hasDecimalSeparator = true
                result.append(".")
            }
        }

        return result
    }

    private func budgetDisplayValue(for category: TransactionCategory) -> String {
        CurrencyFormatter.numberString(
            configuredBudget(for: category),
            currencyCode: settingsStore.settings.currencyCode
        )
    }

    private func monthlySpent(for category: TransactionCategory) -> Double {
        tabMetrics
            .categoryBreakdown(for: category, budgetScopeId: budgetScopeId)
            .total
    }

    private func configuredBudget(for category: TransactionCategory) -> Double {
        settingsStore.budgetAmount(for: category, in: monthSelectionStore.selectedMonthDate)
    }

    private func remainingAmount(for category: TransactionCategory) -> Double {
        configuredBudget(for: category) - monthlySpent(for: category)
    }

    private func budgetProgress(for category: TransactionCategory) -> Double {
        let budget = configuredBudget(for: category)
        guard budget > 0 else { return 0 }
        return min(max(monthlySpent(for: category) / budget, 0), 1)
    }

    private var budgetProgressAccessibilityValue: String {
        (budgetProgress * 100).formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    private func categoryProgressAccessibilityValue(for category: TransactionCategory) -> String {
        (budgetProgress(for: category) * 100).formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    private func formattedAmount(_ amount: Double) -> String {
        CurrencyFormatter.amountString(
            amount,
            currencyCode: settingsStore.settings.currencyCode
        )
    }

    private var saveAlertBinding: Binding<Bool> {
        Binding(
            get: { saveMessage != nil },
            set: { isPresented in
                if !isPresented {
                    saveMessage = nil
                }
            }
        )
    }

    private func budgetEmptyState(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppTheme.brand)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BudgetBeaverPalette.ink)
            Text(message)
                .font(.caption)
                .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(BudgetBeaverPalette.bank, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    BudgetView(budgetScopeId: "local")
        .environmentObject(SettingsStore())
        .environmentObject(MemberViewModel())
        .environmentObject(MonthSelectionStore())
        .environmentObject(AuthSessionStore())
        .environmentObject(CloudSyncStore())
        .environmentObject(AppRefreshStore())
        .modelContainer(PreviewContainer.seeded)
}

private struct CategoryEditorView: View {
    enum Mode {
        case add
        case edit

        var title: String {
            switch self {
            case .add:
                return "Add Category"
            case .edit:
                return "Edit Category"
            }
        }

        var saveTitle: String {
            switch self {
            case .add:
                return "Add"
            case .edit:
                return "Save"
            }
        }
    }

    let mode: Mode
    let initialName: String
    let initialEmoji: String
    let onCancel: () -> Void
    let onSave: (String, String?) -> Void

    @State private var name: String
    @State private var emoji: String
    @State private var validationMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case emoji
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validationMessage == nil
    }

    init(
        mode: Mode,
        initialName: String,
        initialEmoji: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, String?) -> Void
    ) {
        self.mode = mode
        self.initialName = initialName
        self.initialEmoji = initialEmoji
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _emoji = State(initialValue: initialEmoji)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Category")
                            .font(.roundedBold(26))
                            .foregroundStyle(BudgetBeaverPalette.wood)

                        VStack(spacing: 0) {
                            TextField("Category name", text: $name)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(BudgetBeaverPalette.ink)
                                .focused($focusedField, equals: .name)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onSubmit(save)
                                .frame(minHeight: 58)
                                .padding(.horizontal, 16)

                            Divider()
                                .padding(.horizontal, 16)

                            TextField("Emoji icon", text: $emoji)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(BudgetBeaverPalette.ink)
                                .focused($focusedField, equals: .emoji)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .onSubmit(save)
                                .frame(minHeight: 58)
                                .padding(.horizontal, 16)
                                .onChange(of: emoji) { _, value in
                                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if trimmed.isEmpty || trimmed.isSingleEmoji {
                                        validationMessage = nil
                                    } else {
                                        validationMessage = "Use one emoji, or leave it blank."
                                    }
                                }
                        }
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                                .stroke(AppTheme.surfaceStroke, lineWidth: 1)
                        )

                        if let validationMessage {
                            Text(validationMessage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.danger)
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(AppTheme.brand)
                }
            }
            .task {
                await Task.yield()
                focusedField = .name
            }
        }
    }

    private var header: some View {
        ZStack {
            Text(mode.title)
                .font(.roundedBold(22))
                .foregroundStyle(BudgetBeaverPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.88)

            HStack {
                Button("Cancel", action: onCancel)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(BudgetBeaverPalette.wood)
                    .frame(width: 92, height: 52)
                    .background(AppTheme.surface, in: Capsule())
                    .buttonStyle(PressableButtonStyle(scale: 0.96))

                Spacer()

                Button(mode.saveTitle, action: save)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(canSave ? AppTheme.brand : BudgetBeaverPalette.wood.opacity(0.45))
                    .frame(width: 92, height: 52)
                    .background(AppTheme.surface, in: Capsule())
                    .buttonStyle(PressableButtonStyle(scale: 0.96))
                    .disabled(!canSave)
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmoji.isEmpty || trimmedEmoji.isSingleEmoji else {
            validationMessage = "Use one emoji, or leave it blank."
            return
        }
        onSave(name, trimmedEmoji.isEmpty ? nil : trimmedEmoji)
    }
}

struct BudgetCategoryTransactionListView: View {
    let categoryRawValue: String
    let budgetScopeId: String
    let selectedMonthKey: String
    let selectedMonthTitle: String
    let emoji: String?
    let breakdown: BudgetCategoryTransactionBreakdown
    let currencyCode: String

    private var category: TransactionCategory { TransactionCategory(rawValue: categoryRawValue) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !breakdown.anomalies.isEmpty {
                    Label(
                        "Some category money records need attention",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BudgetBeaverPalette.amountRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Some category money records need attention")
                }
                summaryCard
                if breakdown.transactions.isEmpty { emptyCard } else { transactionCard }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("\(category.displayName) Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(
            "budget-category-transaction-list-\(categoryRawValue)-\(selectedMonthKey)"
        )
    }

    private var summaryCard: some View {
        CardContainer(showsShadow: false) {
            HStack(spacing: 14) {
                CategoryIconView(category: category, emoji: emoji, size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedMonthTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BudgetBeaverPalette.wood)
                    Text("Spent")
                        .font(.roundedBold(24))
                        .foregroundStyle(BudgetBeaverPalette.ink)
                    Text("\(breakdown.transactions.count) expense\(breakdown.transactions.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(BudgetBeaverPalette.wood)
                }
                Spacer(minLength: 8)
                Text(formattedAmount(breakdown.total))
                    .font(.roundedBold(26))
                    .monospacedDigit()
                    .foregroundStyle(BudgetBeaverPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.displayName) spending for \(selectedMonthTitle)")
        .accessibilityValue(
            "\(breakdown.transactions.count) expenses, \(formattedAmount(breakdown.total)) spent"
        )
    }

    private var transactionCard: some View {
        CardContainer(showsShadow: false) {
            VStack(spacing: 0) {
                ForEach(Array(breakdown.transactions.enumerated()), id: \.element.id) { index, transaction in
                    HStack(spacing: 12) {
                        CategoryIconView(category: category, emoji: emoji, size: 34)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(transaction.title)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(BudgetBeaverPalette.ink)
                                .lineLimit(2)
                            Text(transaction.date.formatted(.dateTime.month(.abbreviated).day().year()))
                                .font(.subheadline)
                                .foregroundStyle(BudgetBeaverPalette.wood)
                        }
                        Spacer(minLength: 8)
                        Text(formattedAmount(transaction))
                            .font(.roundedBold(19))
                            .monospacedDigit()
                            .foregroundStyle(BudgetBeaverPalette.amountDark)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .padding(.vertical, 15)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(transaction.title), \(transaction.date.formatted(.dateTime.month(.wide).day().year())), " +
                            "\(formattedAmount(transaction))"
                    )
                    .accessibilityIdentifier("budget-category-transaction-\(transaction.id.uuidString)")
                    if index < breakdown.transactions.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
    }

    private var emptyCard: some View {
        CardContainer(showsShadow: false) {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(CategoryColor.color(for: category))
                Text("No \(category.displayName.lowercased()) expenses")
                    .font(.roundedBold(19))
                    .foregroundStyle(BudgetBeaverPalette.ink)
                Text("There are no expenses in this category for \(selectedMonthTitle.lowercased()).")
                    .font(.subheadline)
                    .foregroundStyle(BudgetBeaverPalette.wood)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private func formattedAmount(_ amount: Double) -> String {
        CurrencyFormatter.amountString(amount, currencyCode: currencyCode)
    }

    private func formattedAmount(_ transaction: Transaction) -> String {
        if let money = MoneyAccounting.amount(for: transaction, fallbackCurrencyCode: currencyCode) {
            return CurrencyFormatter.amountString(money)
        }
        return formattedAmount(transaction.amount)
    }
}

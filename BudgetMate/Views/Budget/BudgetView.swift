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

    @Query private var transactions: [Transaction]
    @Query private var settlementRecords: [Settlement]
    @State private var categoryBudgetInputs: [String: String] = [:]
    @State private var isEditingCategories = false
    @State private var categoryBeingEdited: TransactionCategory?
    @State private var isShowingCategoryEditor = false
    @State private var saveMessage: String?
    @State private var tabMetrics = BudgetTabMetrics()

    private var scopedTransactions: [Transaction] {
        transactions.filter { $0.ownerUserId == authStore.currentBudgetScopeId }
    }

    private var scopedSettlementRecords: [Settlement] {
        settlementRecords.filter { $0.ownerUserId == authStore.currentBudgetScopeId }
    }

    private var totalExpenses: Double { tabMetrics.totalExpenses }

    private var remainingBudget: Double {
        settingsStore.settings.monthlyBudget - totalExpenses
    }

    private var budgetProgress: Double {
        guard settingsStore.settings.monthlyBudget > 0 else { return 0 }
        return min(max(totalExpenses / settingsStore.settings.monthlyBudget, 0), 1)
    }

    private var metricsRefreshToken: String {
        let dataHash = FinancialDataFingerprint.hash(
            transactions: scopedTransactions,
            settlements: scopedSettlementRecords
        )
        return "\(dataHash)-\(monthSelectionStore.selectedMonthIndex)-\(authStore.currentBudgetScopeId)"
    }

    private var categories: [TransactionCategory] {
        let hiddenRawValues = settingsStore.hiddenExpenseCategoryRawValues()
        let builtInCategories = TransactionCategory.expenseCategories
            .filter { !hiddenRawValues.contains($0.rawValue) }
        let customCategories = settingsStore.settings.categoryBudgets.keys
            .filter { key in
                !TransactionCategory.builtInRawValues.contains(key) &&
                !TransactionCategory.isHiddenMarkerKey(key)
            }
            .map(TransactionCategory.init(rawValue:))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        return builtInCategories + customCategories
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
                    onCancel: {
                        isShowingCategoryEditor = false
                        categoryBeingEdited = nil
                    },
                    onSave: { name in
                        saveCategoryName(name)
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
                    .foregroundStyle(BudgetBeaverPalette.wood)
                    .frame(width: 44, height: 44)
                    .background(BudgetBeaverPalette.bank, in: Circle())

                VStack(alignment: .leading, spacing: 8) {
                    Text("MONTHLY BUDGET")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.6))

                    Text(formattedAmount(settingsStore.settings.monthlyBudget))
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(BudgetBeaverPalette.water)
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
                        .foregroundStyle(remainingBudget >= 0 ? BudgetBeaverPalette.forest : BudgetBeaverPalette.amountRed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(BudgetBeaverPalette.bank, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                HStack(spacing: 12) {
                    budgetSummaryTile(
                        title: "Spent",
                        value: totalExpenses,
                        tint: BudgetBeaverPalette.clay,
                        systemImage: "arrow.up.right"
                    )
                    budgetSummaryTile(
                        title: "Remaining",
                        value: remainingBudget,
                        tint: remainingBudget >= 0 ? BudgetBeaverPalette.forest : BudgetBeaverPalette.amountRed,
                        systemImage: remainingBudget >= 0 ? "checkmark" : "exclamationmark"
                    )
                }

                ProgressView(value: budgetProgress)
                    .tint(remainingBudget >= 0 ? BudgetBeaverPalette.water : BudgetBeaverPalette.amountRed)
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
                            if !isEditingCategories {
                                loadCategoryBudgetInputs()
                            }
                            isEditingCategories.toggle()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BudgetBeaverPalette.water)
                }

                Text("Spending is tracked month by month.")
                    .font(.caption)
                    .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.7))

                ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                    categoryBudgetRow(for: category)

                    if index < categories.count - 1 {
                        Divider()
                    }
                }

                if isEditingCategories {
                    Button("Save Category Budgets") {
                        saveCategoryBudgets()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(BudgetBeaverPalette.water, in: Capsule())
                    .buttonStyle(.plain)

                    Button {
                        categoryBeingEdited = nil
                        isShowingCategoryEditor = true
                    } label: {
                        Label("Add Category", systemImage: "plus.circle.fill")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BudgetBeaverPalette.water)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func categoryBudgetRow(for category: TransactionCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if isEditingCategories {
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
                } else {
                    Text(category.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BudgetBeaverPalette.ink)
                }

                Spacer()

                if isEditingCategories, !category.isProtectedCategory {
                    Button(role: .destructive) {
                        removeCategory(category)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }

                if isEditingCategories {
                    TextField("0.00", text: budgetBinding(for: category))
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
                .tint(remainingAmount(for: category) >= 0 ? BudgetBeaverPalette.water : BudgetBeaverPalette.amountRed)
        }
        .padding(.vertical, 4)
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
                        .background(BudgetBeaverPalette.bank, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                ForEach(tabMetrics.expensesByMember, id: \.member.id) { entry in
                    HStack(spacing: 10) {
                        MemberInitialsBadge(
                            initials: entry.member.initials,
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
                    .background(BudgetBeaverPalette.bank.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
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
            .background(BudgetBeaverPalette.paper, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(BudgetBeaverPalette.border, lineWidth: 1)
            )
    }

    private func budgetSummaryTile(
        title: String,
        value: Double,
        tint: Color,
        systemImage: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.7))

                Text(formattedAmount(value))
                    .font(.title3.weight(.black))
                    .foregroundStyle(BudgetBeaverPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BudgetBeaverPalette.bank.opacity(0.6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BudgetBeaverPalette.border, lineWidth: 1)
        )
    }

    private func refreshTabMetrics() {
        tabMetrics = BudgetTabMetrics.compute(
            transactions: scopedTransactions,
            settlements: scopedSettlementRecords,
            members: memberViewModel.members,
            monthInterval: monthSelectionStore.monthInterval()
        )
    }

    private func balanceCaption(for member: BudgetMember) -> (text: String, color: Color)? {
        let cents = tabMetrics.netBalances[member.id] ?? 0
        guard cents != 0 else { return nil }
        let value = Double(abs(cents)) / 100
        if cents > 0 {
            return ("owed \(formattedAmount(value))", BudgetBeaverPalette.forest)
        } else {
            return ("owes \(formattedAmount(value))", BudgetBeaverPalette.amountRed)
        }
    }

    private func loadCategoryBudgetInputs() {
        var values: [String: String] = [:]
        for category in categories {
            let budget = settingsStore.budgetAmount(for: category)
            values[category.rawValue] = budget > 0 ? String(format: "%.2f", budget) : ""
        }
        categoryBudgetInputs = values
    }

    private func saveCategoryBudgets() {
        var updates: [TransactionCategory: Double] = [:]
        for category in categories {
            let raw = categoryBudgetInputs[category.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty {
                updates[category] = 0
            } else if let value = Double(raw) {
                updates[category] = value
            }
        }

        settingsStore.updateCategoryBudgets(updates)
        loadCategoryBudgetInputs()
        cloudSyncStore.saveSettings(
            settingsStore.settings,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
        saveMessage = "Category budgets updated."
    }

    private func saveCategoryName(_ name: String) {
        guard let rawValue = TransactionCategory.customRawValue(from: name) else {
            saveMessage = "Enter a category name."
            return
        }

        let newCategory = TransactionCategory(rawValue: rawValue)
        let oldCategory = categoryBeingEdited
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

        if let oldCategory {
            settingsStore.renameCategory(from: oldCategory, to: newCategory)
            reassignTransactions(from: oldCategory, to: newCategory)
        } else {
            settingsStore.upsertCategory(newCategory)
        }

        loadCategoryBudgetInputs()
        syncSettingsAndChangedTransactions()
        categoryBeingEdited = nil
        isShowingCategoryEditor = false
    }

    private func removeCategory(_ category: TransactionCategory) {
        guard !category.isProtectedCategory else { return }

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
            cloudSyncStore.saveTransaction(
                transaction,
                userScopeId: authStore.currentUserScopeId,
                budgetScopeId: authStore.currentBudgetScopeId
            )
        }
        try? modelContext.save()
        refreshTabMetrics()
    }

    private func syncSettingsAndChangedTransactions() {
        cloudSyncStore.saveSettings(
            settingsStore.settings,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
    }

    private func budgetBinding(for category: TransactionCategory) -> Binding<String> {
        Binding(
            get: { categoryBudgetInputs[category.rawValue] ?? "" },
            set: { categoryBudgetInputs[category.rawValue] = $0 }
        )
    }

    private func budgetDisplayValue(for category: TransactionCategory) -> String {
        String(format: "%.2f", configuredBudget(for: category))
    }

    private func monthlySpent(for category: TransactionCategory) -> Double {
        tabMetrics.spentByCategory[category] ?? 0
    }

    private func configuredBudget(for category: TransactionCategory) -> Double {
        settingsStore.budgetAmount(for: category)
    }

    private func remainingAmount(for category: TransactionCategory) -> Double {
        configuredBudget(for: category) - monthlySpent(for: category)
    }

    private func budgetProgress(for category: TransactionCategory) -> Double {
        let budget = configuredBudget(for: category)
        guard budget > 0 else { return 0 }
        return min(max(monthlySpent(for: category) / budget, 0), 1)
    }

    private func formattedAmount(_ amount: Double) -> String {
        CurrencyFormatter.amountString(amount, symbol: settingsStore.settings.currencySymbol)
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
}

#Preview {
    BudgetView()
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
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var name: String
    @FocusState private var nameFocused: Bool

    init(
        mode: Mode,
        initialName: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.mode = mode
        self.initialName = initialName
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Category name", text: $name)
                        .focused($nameFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(save)
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.saveTitle, action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    nameFocused = true
                }
            }
        }
    }

    private func save() {
        onSave(name)
    }
}

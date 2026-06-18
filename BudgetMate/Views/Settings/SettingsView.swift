import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var memberViewModel: MemberViewModel
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [Transaction]
    @Query private var settlements: [Settlement]

    @State private var monthlyBudgetText: String = ""
    @State private var isShowingClearConfirmation = false
    @State private var isShowingLeaveBudgetConfirmation = false
    @State private var isShowingProfileEditor = false
    @State private var clearFeedbackMessage: String?
    @State private var pendingInvites: [BudgetInvite] = []
    @State private var memberships: [BudgetMembership] = []
    @State private var isLoadingInvites = false

    private var scopedTransactions: [Transaction] {
        transactions.filter { $0.ownerUserId == authStore.currentBudgetScopeId }
    }

    private var scopedSettlements: [Settlement] {
        settlements.filter { $0.ownerUserId == authStore.currentBudgetScopeId }
    }

    private var recurringExpenses: [Transaction] {
        scopedTransactions
            .filter { transaction in
                guard transaction.type == .expense,
                      transaction.isMonthlyRecurring else {
                    return false
                }

                if let endDate = transaction.recurrenceEndDate {
                    return Calendar.current.startOfDay(for: endDate) >= Calendar.current.startOfDay(for: .now)
                }

                return true
            }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.title < rhs.title
                }
                return lhs.date < rhs.date
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                AppTopBar(
                    member: memberViewModel.activeMember
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section("Budget") {
                    TextField("Monthly Budget", text: $monthlyBudgetText)
                        .keyboardType(.decimalPad)
                        .onSubmit {
                            applyMonthlyBudget()
                        }
                }

                Section("Currency") {
                    Picker("Household Currency", selection: currencySelection) {
                        ForEach(CurrencyOption.allCases) { option in
                            Text(option.pickerLabel).tag(option.code)
                        }
                    }

                    Text("Changing currency updates the symbol only. Saved amounts are not converted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Appearance") {
                    Picker("Mode", selection: appearanceSelection) {
                        ForEach(AppearanceOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Account") {
                    HStack {
                        Text("Signed in as")
                        Spacer()
                        Text(authStore.userEmail ?? "Unknown")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Profile name")
                        Spacer()
                        Text(profileDisplayName)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    Button("Update Profile Name") {
                        isShowingProfileEditor = true
                    }

                    Button("Sign Out", role: .destructive) {
                        Task {
                            await authStore.signOut()
                        }
                    }
                }

                #if DEBUG
                Section("Developer Testing") {
                    Picker("Using app as", selection: $memberViewModel.activeMemberId) {
                        ForEach(memberViewModel.members) { member in
                            Text(member.displayName).tag(member.id)
                        }
                    }

                    Text("Preview the app as another member. This section is hidden in release builds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Load Sample Data (Only Me)") {
                        loadSampleData(mode: .currentUserOnly)
                    }
                    .tint(AppTheme.brand)

                    Button("Load Sample Data (Demo Household)") {
                        loadSampleData(mode: .household)
                    }
                    .tint(AppTheme.brand)
                }
                #endif

                Section("Shared Budget") {
                    if !memberships.isEmpty {
                        Picker("Viewing", selection: activeBudgetSelection) {
                            ForEach(memberships) { membership in
                                Text(membership.displayName(currentUserId: authStore.currentUserScopeId))
                                    .tag(membership.budgetId.uuidString)
                            }
                        }
                    }

                    NavigationLink("Budget Members") {
                        BudgetMembersView()
                    }

                    if canLeaveCurrentBudget {
                        Button("Leave Shared Budget", role: .destructive) {
                            isShowingLeaveBudgetConfirmation = true
                        }
                    }

                    if isLoadingInvites {
                        HStack {
                            Text("Checking invites")
                            Spacer()
                            ProgressView()
                        }
                    } else if pendingInvites.isEmpty {
                        Text("No pending invites.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pendingInvites) { invite in
                            pendingInviteRow(invite)
                        }
                    }
                }

                Section("Recurring Expenses") {
                    if recurringExpenses.isEmpty {
                        Text("No recurring expenses right now.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recurringExpenses) { transaction in
                            recurringExpenseRow(transaction)
                        }
                    }
                }

                Section("Sync") {
                    HStack {
                        Text("Device data")
                        Spacer()
                        Text(memberViewModel.syncMode.displayName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(syncBadgeColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(syncBadgeColor)
                    }

                    HStack {
                        Text("Cloud backup")
                        Spacer()
                        Text(cloudSyncStatusText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(cloudSyncStore.lastErrorMessage == nil ? .secondary : AppTheme.expense)
                    }

                    if let lastErrorMessage = cloudSyncStore.lastErrorMessage {
                        Text("Last sync failed: \(lastErrorMessage)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.expense)
                    }

                    Button {
                        Task {
                            await syncCloudData()
                        }
                    } label: {
                        if cloudSyncStore.isSyncing {
                            Label("Syncing", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Sync Now", systemImage: "icloud.and.arrow.up")
                        }
                    }
                    .disabled(cloudSyncStore.isSyncing)
                }

                Section("Data") {
                    Button("Reset Settings") {
                        settingsStore.resetSettings()
                        syncFieldsFromStore()
                        cloudSyncStore.saveSettings(
                            settingsStore.settings,
                            userScopeId: authStore.currentUserScopeId,
                            budgetScopeId: authStore.currentBudgetScopeId
                        )
                    }

                    Button("Clear All Transactions", role: .destructive) {
                        isShowingClearConfirmation = true
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .statusBarScrim()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                syncFieldsFromStore()
                Task {
                    await refreshSharedBudgetSection()
                }
            }
            .task(id: "\(authStore.userEmail ?? "")-\(authStore.currentBudgetScopeId)") {
                await refreshSharedBudgetSection()
            }
            .fullScreenCover(isPresented: $isShowingClearConfirmation) {
                ClearTransactionsConfirmationView(
                    onCancel: {
                        isShowingClearConfirmation = false
                    },
                    onConfirm: {
                        isShowingClearConfirmation = false
                        clearAllTransactions()
                    }
                )
            }
            .sheet(isPresented: $isShowingProfileEditor) {
                EditProfileNameView(
                    currentName: profileDisplayName,
                    onCancel: {
                        isShowingProfileEditor = false
                    },
                    onSave: { name in
                        updateProfileName(name)
                    }
                )
            }
            .confirmationDialog(
                "Leave this shared budget?",
                isPresented: $isShowingLeaveBudgetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Leave Shared Budget", role: .destructive) {
                    leaveCurrentBudget()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You will no longer see this shared budget. The budget and its transactions will stay available for the other members.")
            }
            .alert("Transactions", isPresented: clearFeedbackAlertBinding) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(clearFeedbackMessage ?? "")
            }
        }
    }

    private func syncFieldsFromStore() {
        monthlyBudgetText = String(format: "%.2f", settingsStore.settings.monthlyBudget)
    }

    private func applyMonthlyBudget() {
        guard let value = Double(monthlyBudgetText) else { return }
        settingsStore.updateMonthlyBudget(value)
        syncFieldsFromStore()
        cloudSyncStore.saveSettings(
            settingsStore.settings,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
    }

    private var profileDisplayName: String {
        memberViewModel.profileMember(
            userScopeId: authStore.currentUserScopeId,
            email: authStore.userEmail
        )?.displayName ?? memberViewModel.activeMember.displayName
    }

    private var currentMembership: BudgetMembership? {
        memberships.first { $0.budgetId.uuidString == authStore.currentBudgetScopeId }
    }

    private var canLeaveCurrentBudget: Bool {
        authStore.currentBudgetScopeId != authStore.currentUserScopeId &&
        currentMembership?.role != "owner"
    }

    private func updateProfileName(_ name: String) {
        guard memberViewModel.updateProfileName(name, userScopeId: authStore.currentUserScopeId) else {
            clearFeedbackMessage = "Enter a profile name to save."
            return
        }

        cloudSyncStore.saveMembers(
            memberViewModel.members,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
        isShowingProfileEditor = false
        clearFeedbackMessage = "Profile name updated."
    }

    private func loadSampleData(mode: SampleDataSeeder.Mode) {
        if mode == .household {
            memberViewModel.replaceMembers(with: BudgetSampleData.householdMembers(owner: memberViewModel.activeMember))
        }

        settingsStore.updateMonthlyBudget(BudgetSampleData.monthlyBudget)
        settingsStore.updateCategoryBudgets(BudgetSampleData.categoryBudgets)
        syncFieldsFromStore()
        cloudSyncStore.saveSettings(
            settingsStore.settings,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )

        let sampleMembers: [BudgetMember]
        switch mode {
        case .currentUserOnly:
            sampleMembers = [memberViewModel.activeMember]
        case .household:
            sampleMembers = memberViewModel.members
        }

        let count = SampleDataSeeder.seed(
            into: modelContext,
            members: sampleMembers,
            ownerUserId: authStore.currentBudgetScopeId,
            mode: mode
        )
        try? modelContext.save()
        if mode == .household {
            let memberCount = memberViewModel.members.count
            cloudSyncStore.saveMembers(
                memberViewModel.members,
                userScopeId: authStore.currentUserScopeId,
                budgetScopeId: authStore.currentBudgetScopeId
            )
            clearFeedbackMessage = "Added \(count) sample transaction\(count == 1 ? "" : "s"), sample budgets, and \(memberCount) demo member\(memberCount == 1 ? "" : "s")."
        } else {
            clearFeedbackMessage = "Added \(count) sample transaction\(count == 1 ? "" : "s") and sample budgets for \(memberViewModel.activeMember.displayName)."
        }
    }

    private func clearAllTransactions() {
        let transactionCount = scopedTransactions.count
        let settlementCount = scopedSettlements.count

        cloudSyncStore.deleteAllBudgetData(
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
        scopedTransactions.forEach { modelContext.delete($0) }
        scopedSettlements.forEach { modelContext.delete($0) }
        try? modelContext.save()

        if transactionCount == 0 && settlementCount == 0 {
            clearFeedbackMessage = "Nothing to clear."
        } else {
            var parts: [String] = []
            if transactionCount > 0 {
                parts.append("\(transactionCount) transaction\(transactionCount == 1 ? "" : "s")")
            }
            if settlementCount > 0 {
                parts.append("\(settlementCount) settle-up record\(settlementCount == 1 ? "" : "s")")
            }
            clearFeedbackMessage = "Cleared " + parts.joined(separator: " and ") + "."
        }
    }

    private func leaveCurrentBudget() {
        let sharedBudgetScopeId = authStore.currentBudgetScopeId
        guard canLeaveCurrentBudget else {
            clearFeedbackMessage = "You cannot leave your personal budget."
            return
        }

        Task {
            do {
                try await cloudSyncStore.leaveBudget(
                    userScopeId: authStore.currentUserScopeId,
                    budgetScopeId: sharedBudgetScopeId
                )
                memberships.removeAll { $0.budgetId.uuidString == sharedBudgetScopeId }
                authStore.switchBudgetScope(to: authStore.currentUserScopeId)
                settingsStore.switchUser(to: authStore.currentUserScopeId)
                await loadMemberships()
                await syncCloudData()
                clearFeedbackMessage = "You left the shared budget. You are now viewing your personal budget."
            } catch {
                clearFeedbackMessage = "Could not leave shared budget: \(error.localizedDescription)"
            }
        }
    }

    private func syncCloudData() async {
        do {
            let summary = try await cloudSyncStore.sync(
                settings: settingsStore.settings,
                members: memberViewModel.members,
                transactions: scopedTransactions,
                settlements: scopedSettlements,
                into: modelContext,
                userScopeId: authStore.currentUserScopeId,
                budgetScopeId: authStore.currentBudgetScopeId
            )
            if let cloudSettings = try await cloudSyncStore.fetchSettings(
                userScopeId: authStore.currentUserScopeId,
                budgetScopeId: authStore.currentBudgetScopeId
            ) {
                settingsStore.replaceSettings(cloudSettings)
                syncFieldsFromStore()
            }
            let cloudMembers = try await cloudSyncStore.fetchMembers(
                userScopeId: authStore.currentUserScopeId,
                budgetScopeId: authStore.currentBudgetScopeId
            )
            memberViewModel.replaceMembers(with: cloudMembers)
            clearFeedbackMessage = summary.message
        } catch {
            clearFeedbackMessage = cloudSyncErrorMessage(for: error)
        }
    }

    private func loadPendingInvites() async {
        guard let email = authStore.userEmail else {
            pendingInvites = []
            return
        }

        isLoadingInvites = true
        defer { isLoadingInvites = false }

        do {
            pendingInvites = try await cloudSyncStore.fetchPendingInvites(email: email)
        } catch {
            pendingInvites = []
        }
    }

    private func loadMemberships() async {
        do {
            memberships = try await cloudSyncStore.fetchMemberships(userScopeId: authStore.currentUserScopeId)
        } catch {
            memberships = []
        }
    }

    private func refreshSharedBudgetSection() async {
        await loadPendingInvites()
        await loadMemberships()
    }

    private var activeBudgetSelection: Binding<String> {
        Binding(
            get: { authStore.currentBudgetScopeId },
            set: { budgetScopeId in
                authStore.switchBudgetScope(to: budgetScopeId)
                settingsStore.switchUser(to: budgetScopeId)
                clearFeedbackMessage = "Switched budget. Syncing now."
                Task {
                    await syncCloudData()
                    await refreshSharedBudgetSection()
                }
            }
        )
    }

    private func acceptInvite(_ invite: BudgetInvite) {
        Task {
            do {
                try await cloudSyncStore.acceptInvite(invite, userScopeId: authStore.currentUserScopeId)
                authStore.switchBudgetScope(to: invite.budgetId.uuidString)
                settingsStore.switchUser(to: invite.budgetId.uuidString)
                pendingInvites.removeAll { $0.id == invite.id }
                await refreshSharedBudgetSection()
                await syncCloudData()
                clearFeedbackMessage = "Invite accepted. You are now viewing the shared budget."
            } catch {
                clearFeedbackMessage = "Could not accept invite: \(error.localizedDescription)"
            }
        }
    }

    private var syncBadgeColor: Color {
        switch memberViewModel.syncMode {
        case .local:
            return .orange
        case .cloudPlaceholder:
            return .blue
        }
    }

    private var cloudSyncStatusText: String {
        if cloudSyncStore.isSyncing {
            return "Syncing..."
        }

        if cloudSyncStore.lastErrorMessage != nil {
            return "Needs attention"
        }

        if let lastSyncedAt = cloudSyncStore.lastSyncedAt {
            return lastSyncedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }

        return "Not synced yet"
    }

    private func cloudSyncErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("budget_transactions") ||
            message.localizedCaseInsensitiveContains("Could not find the table") {
            return "Supabase tables are not set up yet. Run the budgetmate_schema.sql file in Supabase first."
        }
        return "Cloud sync failed: \(message)"
    }

    private func recurringExpenseRow(_ transaction: Transaction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.brand)
                .frame(width: 30, height: 30)
                .background(Circle().fill(AppTheme.brandSoft))

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(recurringExpenseSubtitle(for: transaction))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Text(formattedAmount(transaction.amount))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }

    private func pendingInviteRow(_ invite: BudgetInvite) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.brand)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(AppTheme.brandSoft))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Budget invite for \(invite.displayName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(invite.email)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()
            }

            Button("Accept Invite") {
                acceptInvite(invite)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.brand)
        }
        .padding(.vertical, 4)
    }

    private func recurringExpenseSubtitle(for transaction: Transaction) -> String {
        let start = transaction.date.formatted(.dateTime.month(.abbreviated).day().year())
        let stop = transaction.recurrenceEndDate?
            .formatted(.dateTime.month(.abbreviated).day().year()) ?? "No stop date"
        return "\(transaction.category.displayName) · Started \(start) · \(stop)"
    }

    private func formattedAmount(_ amount: Double) -> String {
        CurrencyFormatter.amountString(amount, symbol: settingsStore.settings.currencySymbol)
    }

    private var clearFeedbackAlertBinding: Binding<Bool> {
        Binding(
            get: { clearFeedbackMessage != nil },
            set: { isPresented in
                if !isPresented {
                    clearFeedbackMessage = nil
                }
            }
        )
    }

    private var currencySelection: Binding<String> {
        Binding(
            get: { settingsStore.settings.currencyCode },
            set: {
                settingsStore.updateCurrencyCode($0)
                cloudSyncStore.saveSettings(
                    settingsStore.settings,
                    userScopeId: authStore.currentUserScopeId,
                    budgetScopeId: authStore.currentBudgetScopeId
                )
            }
        )
    }

    private var appearanceSelection: Binding<AppearanceOption> {
        Binding(
            get: { settingsStore.settings.appearance },
            set: {
                settingsStore.updateAppearance($0)
                cloudSyncStore.saveSettings(
                    settingsStore.settings,
                    userScopeId: authStore.currentUserScopeId,
                    budgetScopeId: authStore.currentBudgetScopeId
                )
            }
        )
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
        .environmentObject(MemberViewModel())
        .environmentObject(AuthSessionStore())
        .environmentObject(CloudSyncStore())
        .modelContainer(PreviewContainer.seeded)
}

private struct ClearTransactionsConfirmationView: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()

                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(.red)

                VStack(spacing: 10) {
                    Text("Clear All Transactions?")
                        .font(.title2.weight(.bold))

                    Text("This will permanently remove all transactions and settle-up records.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    Button("Clear All Transactions", role: .destructive) {
                        onConfirm()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("Confirm Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        onCancel()
                    }
                }
            }
        }
    }
}

private struct EditProfileNameView: View {
    let currentName: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var name: String
    @State private var validationMessage: String?
    @FocusState private var isFocused: Bool

    init(currentName: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.currentName = currentName
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: currentName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Profile name", text: $name)
                        .textContentType(.name)
                        .focused($isFocused)

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.expense)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Profile Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else {
            validationMessage = "Enter a profile name."
            return
        }

        onSave(trimmedName)
    }
}

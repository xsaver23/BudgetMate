import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var memberViewModel: MemberViewModel
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore
    @EnvironmentObject private var appRefreshStore: AppRefreshStore
    @Environment(\.modelContext) private var modelContext
    let budgetScopeId: String
    @Query private var transactions: [Transaction]
    @Query private var settlements: [Settlement]

    init(budgetScopeId: String) {
        self.budgetScopeId = budgetScopeId
        _transactions = Query(
            filter: #Predicate<Transaction> { $0.ownerUserId == budgetScopeId }
        )
        _settlements = Query(
            filter: #Predicate<Settlement> { $0.ownerUserId == budgetScopeId }
        )
    }

    @State private var isShowingClearConfirmation = false
    @State private var isShowingLeaveBudgetConfirmation = false
    @State private var isShowingProfileEditor = false
    @State private var clearFeedbackMessage: String?
    @State private var pendingInvites: [BudgetInvite] = []
    @State private var memberships: [BudgetMembership] = []
    @State private var isLoadingInvites = false

    // Queries are already scoped to the active budget in init.
    private var scopedTransactions: [Transaction] { transactions }
    private var scopedSettlements: [Settlement] { settlements }

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
            ScrollView {
                VStack(spacing: 18) {
                    AppTopBar(member: memberViewModel.activeMember)
                        .padding(.horizontal, -16)

                    settingsSection("Currency") {
                        settingsRow("Household Currency") {
                            Menu {
                                ForEach(CurrencyOption.allCases) { option in
                                    Button {
                                        updateCurrencyCode(option.code)
                                    } label: {
                                        if option.code == settingsStore.settings.currencyCode {
                                            Label(option.pickerLabel, systemImage: "checkmark")
                                        } else {
                                            Text(option.pickerLabel)
                                        }
                                    }
                                }
                            } label: {
                                settingsValue(settingsStore.settings.currencyCode)
                            }
                        }

                        Divider()

                        Text("Changing currency updates the symbol only. Saved amounts are not converted.")
                            .font(settingsHelperFont)
                            .foregroundStyle(BudgetBeaverPalette.wood)
                    }

                    settingsSection("Appearance") {
                        Picker("Mode", selection: appearanceSelection) {
                            ForEach(AppearanceOption.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(AppTheme.brand)
                    }

                    settingsSection("Account") {
                        settingsRow("Signed in as") {
                            Text(authStore.userEmail ?? "Unknown")
                                .font(settingsCompactValueFont)
                                .foregroundStyle(BudgetBeaverPalette.wood)
                                .multilineTextAlignment(.trailing)
                        }

                        Divider()

                        settingsRow("Profile name") {
                            Text(profileDisplayName)
                                .font(settingsRowValueFont)
                                .foregroundStyle(BudgetBeaverPalette.ink)
                        }

                        Divider()

                        rowButton("Update Profile Name", tint: AppTheme.brand) {
                            isShowingProfileEditor = true
                        }

                        Divider()

                        rowButton("Sign Out", tint: AppTheme.danger) {
                            Task {
                                await authStore.signOut()
                            }
                        }
                    }

                    settingsSection("Shared Budget") {
                        if !memberships.isEmpty {
                            settingsRow("Viewing") {
                                if memberships.count > 1 {
                                    Menu {
                                        ForEach(memberships) { membership in
                                            let displayName = membership.displayName(currentUserId: authStore.currentUserScopeId)
                                            Button {
                                                switchActiveBudget(to: membership.budgetId.uuidString)
                                            } label: {
                                                if membership.budgetId.uuidString == authStore.currentBudgetScopeId {
                                                    Label(displayName, systemImage: "checkmark")
                                                } else {
                                                    Text(displayName)
                                                }
                                            }
                                        }
                                    } label: {
                                        settingsValue(activeBudgetDisplayName)
                                    }
                                } else {
                                    settingsStaticValue(activeBudgetDisplayName)
                                }
                            }
                            Divider()
                        }

                        NavigationLink {
                            BudgetMembersView()
                        } label: {
                            HStack(spacing: 14) {
                                MemberAvatarCluster(members: memberViewModel.members, size: 32, maxVisible: 4)
                                Text("\(memberViewModel.members.count) member\(memberViewModel.members.count == 1 ? "" : "s")")
                                    .font(settingsRowValueFont)
                                    .foregroundStyle(BudgetBeaverPalette.ink)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(settingsRowValueFont)
                                    .foregroundStyle(BudgetBeaverPalette.wood)
                            }
                        }
                        .buttonStyle(.plain)

                        if canLeaveCurrentBudget {
                            Divider()
                            rowButton("Leave Shared Budget", tint: AppTheme.danger) {
                                isShowingLeaveBudgetConfirmation = true
                            }
                        }

                        if isLoadingInvites {
                            Divider()
                            HStack {
                                Text("Checking invites")
                                    .font(settingsRowLabelFont)
                                    .foregroundStyle(BudgetBeaverPalette.ink)
                                Spacer()
                                ProgressView()
                            }
                        } else if pendingInvites.isEmpty {
                            Divider()
                            Text("No pending invites.")
                                .font(settingsHelperFont)
                                .foregroundStyle(BudgetBeaverPalette.wood)
                        } else if !pendingInvites.isEmpty {
                            Divider()
                            ForEach(pendingInvites) { invite in
                                pendingInviteRow(invite)
                            }
                        }
                    }

                    settingsSection("Recurring Expenses") {
                        if recurringExpenses.isEmpty {
                            Text("No recurring expenses right now.")
                                .font(settingsRowLabelFont)
                                .foregroundStyle(BudgetBeaverPalette.wood)
                        } else {
                            ForEach(recurringExpenses) { transaction in
                                recurringExpenseRow(transaction)
                            }
                        }
                    }

                    settingsSection("Sync") {
                        settingsRow("Device data") {
                            Text(memberViewModel.syncMode.displayName)
                                .font(settingsBadgeFont)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(syncBadgeColor.opacity(0.20), in: Capsule())
                                .foregroundStyle(syncBadgeColor)
                        }

                        Divider()

                        settingsRow("Cloud backup") {
                            Text(cloudSyncStore.statusText())
                                .font(settingsCompactValueFont)
                                .foregroundStyle(cloudSyncStore.hasSyncIssue ? AppTheme.danger : BudgetBeaverPalette.wood)
                        }

                        Text(cloudSyncStore.syncHelpText)
                            .font(settingsHelperFont)
                            .foregroundStyle(cloudSyncStore.hasSyncIssue ? AppTheme.danger : BudgetBeaverPalette.wood)

                        Button {
                            Task {
                                await refreshAllData(showFeedback: true, forceSync: true)
                            }
                        } label: {
                            Label(syncButtonTitle, systemImage: "icloud.and.arrow.up")
                                .font(settingsActionFont)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(AppTheme.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.98))
                        .disabled(cloudSyncStore.isSyncing)
                    }

                    settingsSection("Data") {
                        rowButton("Reset Settings", tint: AppTheme.brand) {
                            settingsStore.resetSettings()
                            syncFieldsFromStore()
                            cloudSyncStore.saveSettings(
                                settingsStore.settings,
                                userScopeId: authStore.currentUserScopeId,
                                budgetScopeId: authStore.currentBudgetScopeId
                            )
                        }

                        Divider()

                        rowButton("Clear All Transactions", tint: AppTheme.danger) {
                            isShowingClearConfirmation = true
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .refreshable {
                await refreshAllData(showFeedback: false, forceSync: true)
            }
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
            .alert("BudgetMate", isPresented: clearFeedbackAlertBinding) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(clearFeedbackMessage ?? "")
            }
        }
    }

    private var syncButtonTitle: String {
        if cloudSyncStore.isSyncing {
            return "Syncing Now"
        }
        return cloudSyncStore.hasSyncIssue ? "Retry Sync" : "Sync Now"
    }

    private var settingsSectionTitleFont: Font {
        .system(size: 24, weight: .black, design: .rounded)
    }

    private var settingsRowLabelFont: Font {
        .system(size: 18, weight: .bold, design: .rounded)
    }

    private var settingsRowValueFont: Font {
        .system(size: 18, weight: .bold, design: .rounded)
    }

    private var settingsCompactValueFont: Font {
        .system(size: 15, weight: .bold, design: .rounded)
    }

    private var settingsHelperFont: Font {
        .system(size: 14, weight: .medium, design: .rounded)
    }

    private var settingsBadgeFont: Font {
        .system(size: 12, weight: .black, design: .rounded)
    }

    private var settingsActionFont: Font {
        .system(size: 18, weight: .bold, design: .rounded)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(settingsSectionTitleFont)
                .foregroundStyle(BudgetBeaverPalette.wood)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsRow<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(settingsRowLabelFont)
                .foregroundStyle(BudgetBeaverPalette.wood)
            Spacer(minLength: 12)
            trailing()
        }
    }

    private func settingsValue(_ value: String) -> some View {
        HStack(spacing: 6) {
            Text(value)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .black, design: .rounded))
        }
        .font(settingsRowValueFont)
        .foregroundStyle(BudgetBeaverPalette.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func settingsStaticValue(_ value: String) -> some View {
        Text(value)
            .font(settingsRowValueFont)
            .foregroundStyle(BudgetBeaverPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func rowButton(
        _ title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(settingsActionFont)
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.985))
    }

    private func syncFieldsFromStore() {
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

    private var activeBudgetDisplayName: String {
        currentMembership?.displayName(currentUserId: authStore.currentUserScopeId) ?? "Personal Budget"
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

    private func clearAllTransactions() {
        let transactionCount = scopedTransactions.count
        let settlementCount = scopedSettlements.count

        Task {
            do {
                try await cloudSyncStore.deleteAllBudgetDataNow(
                    userScopeId: authStore.currentUserScopeId,
                    budgetScopeId: authStore.currentBudgetScopeId
                )
                scopedTransactions.forEach { modelContext.delete($0) }
                scopedSettlements.forEach { modelContext.delete($0) }
                do {
                    try modelContext.save()
                } catch {
                    cloudSyncStore.recordSyncIssue(error, context: "Clearing local budget data")
                }

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
            } catch {
                clearFeedbackMessage = cloudSyncStore.userFacingMessage(for: error)
            }
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
                await refreshAllData(showFeedback: false, forceSync: true)
                clearFeedbackMessage = "You left the shared budget. You are now viewing your personal budget."
            } catch {
                clearFeedbackMessage = "Could not leave shared budget: \(error.localizedDescription)"
            }
        }
    }

    private func refreshAllData(showFeedback: Bool, forceSync: Bool) async {
        do {
            if forceSync {
                let summary = try await cloudSyncStore.sync(
                    settings: settingsStore.settings,
                    members: memberViewModel.members,
                    transactions: scopedTransactions,
                    settlements: scopedSettlements,
                    into: modelContext,
                    userScopeId: authStore.currentUserScopeId,
                    userEmail: authStore.userEmail,
                    budgetScopeId: authStore.currentBudgetScopeId
                )

                if showFeedback {
                    clearFeedbackMessage = summary.message
                }
            } else {
                await appRefreshStore.refreshCurrentBudget(forceSync: false)
            }

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
            await refreshSharedBudgetSection()
        } catch {
            if showFeedback {
                clearFeedbackMessage = cloudSyncErrorMessage(for: error)
            }
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

    private func switchActiveBudget(to budgetScopeId: String) {
        authStore.switchBudgetScope(to: budgetScopeId)
        settingsStore.switchUser(to: budgetScopeId)
        clearFeedbackMessage = "Switched budget. Syncing now."
        Task {
            await refreshAllData(showFeedback: false, forceSync: true)
        }
    }

    private func acceptInvite(_ invite: BudgetInvite) {
        Task {
            do {
                try await cloudSyncStore.acceptInvite(invite, userScopeId: authStore.currentUserScopeId)
                authStore.switchBudgetScope(to: invite.budgetId.uuidString)
                settingsStore.switchUser(to: invite.budgetId.uuidString)
                pendingInvites.removeAll { $0.id == invite.id }
                await refreshAllData(showFeedback: false, forceSync: true)
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

    private func cloudSyncErrorMessage(for error: Error) -> String {
        cloudSyncStore.userFacingMessage(for: error)
    }

    private func recurringExpenseRow(_ transaction: Transaction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(settingsBadgeFont)
                .foregroundStyle(AppTheme.brand)
                .frame(width: 30, height: 30)
                .background(Circle().fill(AppTheme.brandSoft))

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title)
                    .font(settingsRowLabelFont)
                    .foregroundStyle(AppTheme.textPrimary)

                Text(recurringExpenseSubtitle(for: transaction))
                    .font(settingsHelperFont)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Text(formattedAmount(transaction.amount))
                .font(settingsCompactValueFont)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }

    private func pendingInviteRow(_ invite: BudgetInvite) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.2.badge.plus")
                    .font(settingsBadgeFont)
                    .foregroundStyle(AppTheme.brand)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(AppTheme.brandSoft))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Budget invite for \(invite.displayName)")
                        .font(settingsRowLabelFont)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(invite.email)
                        .font(settingsHelperFont)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()
            }

            Button("Accept Invite") {
                acceptInvite(invite)
            }
            .font(settingsActionFont)
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
                updateCurrencyCode($0)
            }
        )
    }

    private func updateCurrencyCode(_ code: String) {
        settingsStore.updateCurrencyCode(code)
        cloudSyncStore.saveSettings(
            settingsStore.settings,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
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
    SettingsView(budgetScopeId: "local")
        .environmentObject(SettingsStore())
        .environmentObject(MemberViewModel())
        .environmentObject(AuthSessionStore())
        .environmentObject(CloudSyncStore())
        .environmentObject(AppRefreshStore())
        .modelContainer(PreviewContainer.seeded)
}

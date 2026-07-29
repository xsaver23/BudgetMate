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
    @Query private var settlementRecords: [Settlement]
    @Query private var transactionSplits: [TransactionSplit]

    init(budgetScopeId: String) {
        self.budgetScopeId = budgetScopeId
    }

    @State private var isShowingProfileEditor = false
    @State private var clearFeedbackMessage: String?
    @State private var pendingInvites: [BudgetInvite] = []
    @State private var memberships: [BudgetMembership] = []
    @State private var isLoadingInvites = false
    @State private var currencyHistoryValidatedBudgetScopeId: String?

    private var scopedTransactions: [Transaction] {
        transactions.filter { $0.ownerUserId == budgetScopeId }
    }

    private var currencyFinancialHistory: CurrencyFinancialHistorySnapshot {
        CurrencyFinancialHistorySnapshot(
            budgetScopeId: budgetScopeId,
            transactionOwnerScopeIds: transactions.map(\.ownerUserId),
            splitTransactionOwnerScopeIds: transactionSplits.map { $0.transaction?.ownerUserId },
            settlementOwnerScopeIds: settlementRecords.map(\.ownerUserId),
            categoryBudgetKeys: Array(settingsStore.settings.categoryBudgets.keys),
            hasPreviouslyObservedFinancialHistory: settingsStore.hasObservedFinancialHistory
        )
    }

    private var currencyChangeDecision: CurrencyChangeDecision {
        CurrencyChangeGuardrail.decision(
            activeBudgetScopeId: authStore.currentBudgetScopeId,
            presentedBudgetScopeId: budgetScopeId,
            isHistoryValidated:
                currencyHistoryValidatedBudgetScopeId == budgetScopeId &&
                !cloudSyncStore.hasSyncIssue &&
                settingsStore.pendingCloudSyncToken == nil &&
                settingsStore.hasObservedCloudSettingsBaseline,
            isSyncing: cloudSyncStore.isSyncing,
            history: currencyFinancialHistory
        )
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
                                HStack(spacing: 6) {
                                    settingsValue(settingsStore.settings.currencyCode)
                                    if !currencyChangeDecision.isAllowed {
                                        Image(systemName: "lock.fill")
                                            .font(.caption.weight(.semibold))
                                    }
                                }
                            }
                            .disabled(!currencyChangeDecision.isAllowed)
                            .accessibilityIdentifier("settings.householdCurrency")
                            .accessibilityHint(currencyHelperText)
                        }

                        Divider()

                        Text(currencyHelperText)
                            .font(settingsHelperFont)
                            .foregroundStyle(
                                currencyChangeDecision.isAllowed
                                    ? BudgetBeaverPalette.wood
                                    : AppTheme.warningText
                            )
                            .accessibilityIdentifier("settings.currencyGuardrailMessage")
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

                        Divider()
                        unavailableActionRow(DestructiveActionGuardrails.leaveSharedBudget)

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

                    settingsSection("Privacy & Support") {
                        Text("BudgetMate keeps local budget data on this device. Shared-budget data syncs only when cloud sync is configured. Support archives can contain budget data; review an archive before sharing it.")
                            .font(settingsHelperFont)
                            .foregroundStyle(BudgetBeaverPalette.wood)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settings.privacySupportDisclosure")

                        Text("Privacy policy and support contact links are not configured in this beta. Do not include sensitive data when sharing a support archive.")
                            .font(settingsHelperFont)
                            .foregroundStyle(AppTheme.warningText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settings.missingPrivacySupportLinks")
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
                            let currentDecision = freshCurrencyChangeDecision()
                            settingsStore.resetSettings(
                                preservingCurrencyCode: !currentDecision.isAllowed
                            )
                            syncFieldsFromStore()
                            saveCurrentSettingsToCloud()
                        }

                        Divider()

                        unavailableActionRow(DestructiveActionGuardrails.clearAll)
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
            }
            .task(id: "\(authStore.userEmail ?? "")-\(authStore.currentBudgetScopeId)") {
                currencyHistoryValidatedBudgetScopeId = nil
                await refreshAllData(showFeedback: false, forceSync: true)
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
            .alert("BudgetMate", isPresented: clearFeedbackAlertBinding) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(clearFeedbackMessage ?? "")
            }
        }
    }

    private var syncButtonTitle: String {
        if cloudSyncStore.isSyncing {
            return "Syncing…"
        }
        return cloudSyncStore.hasSyncIssue ? "Retry Sync" : "Sync Now"
    }

    private var settingsSectionTitleFont: Font {
        .system(size: 20, weight: .bold, design: .rounded)
    }

    private var settingsRowLabelFont: Font {
        .system(size: 16, weight: .semibold, design: .rounded)
    }

    private var settingsRowValueFont: Font {
        .system(size: 16, weight: .semibold, design: .rounded)
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
        .system(size: 16, weight: .semibold, design: .rounded)
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
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(AppTheme.surfaceStroke, lineWidth: 1)
            )
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

    private func unavailableActionRow(_ restriction: RestrictedDestructiveAction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(settingsActionFont)
                .foregroundStyle(AppTheme.danger)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(restriction.title)
                    .font(settingsActionFont)
                    .foregroundStyle(AppTheme.danger)

                Text(restriction.message)
                    .font(settingsHelperFont)
                    .foregroundStyle(BudgetBeaverPalette.wood)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(restriction.title). \(restriction.message)")
        .accessibilityIdentifier(restriction.accessibilityIdentifier)
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

    private var activeBudgetDisplayName: String {
        currentMembership?.displayName(currentUserId: authStore.currentUserScopeId) ?? "Personal Budget"
    }

    private func updateProfileName(_ name: String) {
        guard memberViewModel.updateProfileName(name, userScopeId: authStore.currentUserScopeId) else {
            clearFeedbackMessage = "Enter a profile name to save."
            return
        }

        saveCurrentMembersToCloud()
        isShowingProfileEditor = false
        clearFeedbackMessage = "Profile name updated."
    }

    @discardableResult
    private func refreshAllData(showFeedback: Bool, forceSync: Bool) async -> Bool {
        let userScopeId = authStore.currentUserScopeId
        let budgetScopeId = authStore.currentBudgetScopeId

        guard budgetScopeId == self.budgetScopeId else {
            return false
        }
        currencyHistoryValidatedBudgetScopeId = nil

        do {
            if !settingsStore.hasObservedCloudSettingsBaseline {
                let baseline = try await cloudSyncStore.fetchCurrencyBaseline(
                    userScopeId: userScopeId,
                    budgetScopeId: budgetScopeId
                )
                guard authStore.currentUserScopeId == userScopeId,
                      authStore.currentBudgetScopeId == budgetScopeId,
                      budgetScopeId == self.budgetScopeId else {
                    return false
                }
                settingsStore.recordCloudSettingsBaseline(
                    baseline.settings,
                    hasRemoteFinancialRecords:
                        baseline.hasTransactionOrSplit ||
                        baseline.hasSettlement
                )
            }

            if forceSync {
                let transactionDescriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { $0.ownerUserId == budgetScopeId }
                )
                let settlementDescriptor = FetchDescriptor<Settlement>(
                    predicate: #Predicate { $0.ownerUserId == budgetScopeId }
                )
                let syncTransactions = try modelContext.fetch(transactionDescriptor)
                let syncSettlements = try modelContext.fetch(settlementDescriptor)
                let settingsSyncToken = settingsStore.pendingCloudSyncToken
                let memberSyncToken = memberViewModel.pendingCloudSyncToken
                let summary = try await cloudSyncStore.sync(
                    settings: settingsStore.settings,
                    shouldPushSettings: settingsSyncToken != nil,
                    members: memberViewModel.members,
                    shouldPushMembers: memberSyncToken != nil,
                    transactions: syncTransactions,
                    settlements: syncSettlements,
                    into: modelContext,
                    userScopeId: userScopeId,
                    userEmail: authStore.userEmail,
                    budgetScopeId: budgetScopeId
                )

                // The sync already observed cloud settings and members;
                // reuse them instead of two extra fetches.
                if summary.pushedSettings, let settingsSyncToken {
                    settingsStore.markCloudSyncSucceeded(settingsSyncToken)
                }
                if summary.pushedMembers > 0, let memberSyncToken {
                    memberViewModel.markCloudSyncSucceeded(memberSyncToken)
                }

                guard authStore.currentUserScopeId == userScopeId,
                      authStore.currentBudgetScopeId == budgetScopeId else {
                    return false
                }

                if showFeedback {
                    clearFeedbackMessage = summary.message
                }
                if settingsStore.pendingCloudSyncToken == nil,
                   let cloudSettings = summary.settings {
                    settingsStore.replaceSettings(
                        cloudSettings,
                        preservingEstablishedCurrency: currencyProtectionRequired(
                            including: cloudSettings
                        )
                    )
                    syncFieldsFromStore()
                }
                if memberViewModel.pendingCloudSyncToken == nil {
                    memberViewModel.replaceMembers(with: summary.members)
                }
            } else {
                await appRefreshStore.refreshCurrentBudget(forceSync: false)

                guard authStore.currentUserScopeId == userScopeId,
                      authStore.currentBudgetScopeId == budgetScopeId else {
                    return false
                }

                if settingsStore.pendingCloudSyncToken == nil,
                   let cloudSettings = try await cloudSyncStore.fetchSettings(
                    userScopeId: userScopeId,
                    budgetScopeId: budgetScopeId
                ) {
                    guard authStore.currentUserScopeId == userScopeId,
                          authStore.currentBudgetScopeId == budgetScopeId else {
                        return false
                    }
                    settingsStore.replaceSettings(
                        cloudSettings,
                        preservingEstablishedCurrency: currencyProtectionRequired(
                            including: cloudSettings
                        )
                    )
                    syncFieldsFromStore()
                }
                if memberViewModel.pendingCloudSyncToken == nil {
                    let cloudMembers = try await cloudSyncStore.fetchMembers(
                        userScopeId: userScopeId,
                        budgetScopeId: budgetScopeId
                    )
                    guard authStore.currentUserScopeId == userScopeId,
                          authStore.currentBudgetScopeId == budgetScopeId else {
                        return false
                    }
                    memberViewModel.replaceMembers(with: cloudMembers)
                }
            }
            await refreshSharedBudgetSection()
            guard authStore.currentUserScopeId == userScopeId,
                  authStore.currentBudgetScopeId == budgetScopeId,
                  budgetScopeId == self.budgetScopeId else {
                return false
            }
            recordFinancialHistoryIfPresent()
            if budgetScopeId == self.budgetScopeId,
               settingsStore.hasObservedCloudSettingsBaseline,
               settingsStore.pendingCloudSyncToken == nil,
               !cloudSyncStore.hasSyncIssue {
                currencyHistoryValidatedBudgetScopeId = budgetScopeId
            }
            return true
        } catch {
            if showFeedback {
                clearFeedbackMessage = cloudSyncErrorMessage(for: error)
            }
            return false
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
        memberViewModel.switchUser(
            to: authStore.currentUserScopeId,
            budgetScopeId: budgetScopeId,
            email: authStore.userEmail
        )
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
                memberViewModel.switchUser(
                    to: authStore.currentUserScopeId,
                    budgetScopeId: invite.budgetId.uuidString,
                    email: authStore.userEmail
                )
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
            return AppTheme.warningText
        case .cloudPlaceholder:
            return AppTheme.brand
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
        let normalizedCode = CurrencyOption.normalizedCode(code)
        guard normalizedCode != settingsStore.settings.currencyCode else {
            return
        }
        let currentDecision = freshCurrencyChangeDecision()
        guard currentDecision.isAllowed else {
            clearFeedbackMessage = currentDecision.restrictionMessage
            return
        }

        settingsStore.updateCurrencyCode(normalizedCode)
        saveCurrentSettingsToCloud()
    }

    private var currencyHelperText: String {
        currencyChangeDecision.restrictionMessage ??
            "Choose the household currency before adding financial activity. Saved amounts are not converted later."
    }

    private func currencyProtectionRequired(
        including incomingSettings: BudgetSettings
    ) -> Bool {
        guard settingsStore.hasEstablishedCurrencyConflict(with: incomingSettings) else {
            return false
        }

        do {
            return try CurrencyChangeGuardrail.snapshot(
                in: modelContext,
                budgetScopeId: budgetScopeId,
                categoryBudgetKeys: Array(
                    Set(settingsStore.settings.categoryBudgets.keys)
                        .union(incomingSettings.categoryBudgets.keys)
                ),
                hasPreviouslyObservedFinancialHistory: settingsStore.hasObservedFinancialHistory
            ).state != .knownEmpty
        } catch {
            // A failed local read cannot prove that the household is empty.
            return true
        }
    }

    private func freshCurrencyChangeDecision() -> CurrencyChangeDecision {
        let history: CurrencyFinancialHistorySnapshot
        do {
            history = try CurrencyChangeGuardrail.snapshot(
                in: modelContext,
                budgetScopeId: budgetScopeId,
                categoryBudgetKeys: Array(settingsStore.settings.categoryBudgets.keys),
                hasPreviouslyObservedFinancialHistory: settingsStore.hasObservedFinancialHistory
            )
        } catch {
            return CurrencyChangeDecision(reason: .unverifiedHistory)
        }

        if history.state == .populated,
           authStore.currentBudgetScopeId == budgetScopeId {
            settingsStore.recordFinancialHistoryObserved()
        }

        return CurrencyChangeGuardrail.decision(
            activeBudgetScopeId: authStore.currentBudgetScopeId,
            presentedBudgetScopeId: budgetScopeId,
            isHistoryValidated:
                currencyHistoryValidatedBudgetScopeId == budgetScopeId &&
                !cloudSyncStore.hasSyncIssue &&
                settingsStore.pendingCloudSyncToken == nil &&
                settingsStore.hasObservedCloudSettingsBaseline,
            isSyncing: cloudSyncStore.isSyncing,
            history: history
        )
    }

    private var appearanceSelection: Binding<AppearanceOption> {
        Binding(
            get: { settingsStore.settings.appearance },
            set: {
                settingsStore.updateAppearance($0)
                saveCurrentSettingsToCloud()
            }
        )
    }

    private func saveCurrentSettingsToCloud() {
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

    private func recordFinancialHistoryIfPresent() {
        guard !settingsStore.hasObservedFinancialHistory,
              let history = try? CurrencyChangeGuardrail.snapshot(
                in: modelContext,
                budgetScopeId: budgetScopeId,
                categoryBudgetKeys: Array(settingsStore.settings.categoryBudgets.keys)
              ),
              history.state == .populated else {
            return
        }
        settingsStore.recordFinancialHistoryObserved()
    }

    private func saveCurrentMembersToCloud() {
        let syncToken = memberViewModel.pendingCloudSyncToken
        cloudSyncStore.saveMembers(
            memberViewModel.members,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId,
            onSuccess: {
                if let syncToken {
                    memberViewModel.markCloudSyncSucceeded(syncToken)
                }
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

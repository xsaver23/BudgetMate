import OSLog
import SwiftData
import SwiftUI

@main
struct BudgetMateApp: App {
    @AppStorage("budgetmate.hasSeenIntro") private var hasSeenIntro = false
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var memberViewModel: MemberViewModel
    @StateObject private var transactionFlow = TransactionFlowCoordinator()
    @StateObject private var monthSelectionStore = MonthSelectionStore()
    @StateObject private var authStore = AuthSessionStore()
    @StateObject private var cloudSyncStore = CloudSyncStore()
    @StateObject private var appRefreshStore = AppRefreshStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var appliedUserScopeId: String?
    @State private var lastAutoSyncedAtByScope: [String: Date] = [:]
    @State private var autoSyncFailureCountByScope: [String: Int] = [:]
    @State private var nextAutoSyncAllowedAtByScope: [String: Date] = [:]
    @State private var autoSyncScopesInFlight: Set<String> = []
    @State private var deferredAutoSyncScopes: Set<String> = []
    @State private var duplicatePruningCompletedScopes: Set<String> = []
    @State private var launchBootstrapPreparedScopes: Set<String> = []
    @State private var loggedLaunchMilestones: Set<String> = []
    @State private var foregroundRefreshTask: Task<Void, Never>?
    @State private var checkedCloudProfileUserScopeId: String?
    @State private var isCheckingCloudProfile = false
    private let activeSyncInterval: Duration = .seconds(60)
    private let minimumPassiveSyncInterval: TimeInterval = 60
    private let launchInteractionGracePeriod: Duration = .seconds(2)
    private let launchStartedAtUptime = ProcessInfo.processInfo.systemUptime
    private let persistenceController = PersistenceController.shared
    private static let launchLogger = Logger(subsystem: "BudgetMate", category: "Launch")
    private static let launchSignposter = OSSignposter(subsystem: "BudgetMate", category: "Launch")

    init() {
        // Keep local repository for v1. Swap to CloudKitBudgetRepository
        // later without changing view/view-model wiring.
        let budgetRepository: BudgetRepository = LocalBudgetRepository()
        // let budgetRepository: BudgetRepository = CloudKitBudgetRepository()
        _memberViewModel = StateObject(
            wrappedValue: MemberViewModel(repository: budgetRepository)
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenIntro {
                    if authStore.isLoading {
                        ProgressView("Loading BudgetMate")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(AppTheme.background)
                            .preferredColorScheme(settingsStore.settings.appearance.colorScheme)
                    } else if authStore.isAuthenticated {
                        authenticatedContent
                            .transition(.opacity)
                            .preferredColorScheme(settingsStore.settings.appearance.colorScheme)
                            .task(id: "\(authStore.currentUserScopeId)|\(authStore.currentBudgetScopeId)|\(memberViewModel.isProfileComplete)") {
                                applyUserScope(authStore.currentUserScopeId, budgetScopeId: authStore.currentBudgetScopeId)
                                await restoreCloudProfileIfNeeded(authStore.currentUserScopeId)
                                guard !Task.isCancelled else { return }
                                // Reveal the app with on-device data as soon as the
                                // profile is known, instead of blocking the tabs on the
                                // shared-budget lookup and full sync that follow.
                                appliedUserScopeId = authStore.currentUserScopeId
                                if recordLaunchMilestone("Local UI ready") {
                                    Self.launchSignposter.emitEvent("Local UI Ready")
                                }

                                guard memberViewModel.isProfileComplete,
                                      await waitForLaunchInteractionWindow(
                                          userScopeId: authStore.currentUserScopeId,
                                          budgetScopeId: authStore.currentBudgetScopeId
                                      ),
                                      await selectSharedBudgetIfNeeded(authStore.currentUserScopeId) else {
                                    return
                                }
                                guard !Task.isCancelled else { return }
                                applyUserScope(authStore.currentUserScopeId, budgetScopeId: authStore.currentBudgetScopeId)
                                let syncKey = makeSyncKey(
                                    userScopeId: authStore.currentUserScopeId,
                                    budgetScopeId: authStore.currentBudgetScopeId
                                )
                                launchBootstrapPreparedScopes.insert(syncKey)
                                if recordLaunchMilestone("Bootstrap sync started") {
                                    Self.launchSignposter.emitEvent("Bootstrap Sync Started")
                                }
                                await autoSyncAuthenticatedUser(
                                    authStore.currentUserScopeId,
                                    budgetScopeId: authStore.currentBudgetScopeId,
                                    force: true,
                                    allowWhileEditing: false
                                )
                                if recordLaunchMilestone("Bootstrap sync attempt finished") {
                                    Self.launchSignposter.emitEvent("Bootstrap Sync Attempt Finished")
                                }
                            }
                            .task(id: "auto-sync-\(authStore.currentUserScopeId)-\(authStore.currentBudgetScopeId)-\(memberViewModel.isProfileComplete)-\(scenePhase)") {
                                await runAutoSyncLoop(
                                    userScopeId: authStore.currentUserScopeId,
                                    budgetScopeId: authStore.currentBudgetScopeId
                                )
                            }
                    } else {
                        LoginView()
                            .transition(.opacity)
                            .preferredColorScheme(settingsStore.settings.appearance.colorScheme)
                    }
                } else {
                    FirstRunIntroView {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            hasSeenIntro = true
                        }
                    }
                    .transition(.opacity)
                    .preferredColorScheme(settingsStore.settings.appearance.colorScheme)
                }
            }
            .onAppear {
                appRefreshStore.configure { forceSync in
                    await refreshCurrentBudget(forceSync: forceSync)
                }
            }
        }
        .environmentObject(settingsStore)
        .environmentObject(memberViewModel)
        .environmentObject(transactionFlow)
        .environmentObject(monthSelectionStore)
        .environmentObject(authStore)
        .environmentObject(cloudSyncStore)
        .environmentObject(appRefreshStore)
        .modelContainer(persistenceController.container)
        .onChange(of: scenePhase) { _, phase in
            // A rapid inactive/active transition can otherwise leave several
            // foreground refresh callers waiting on the same retained cloud
            // operation. Keep only the latest scene-owned caller alive.
            foregroundRefreshTask?.cancel()
            foregroundRefreshTask = nil

            guard phase == .active,
                  authStore.isAuthenticated,
                  launchBootstrapPreparedScopes.contains(currentSyncKey) else {
                return
            }

            foregroundRefreshTask = Task { @MainActor in
                await refreshCurrentBudget(forceSync: false)
            }
        }
        .onChange(of: transactionFlow.isTransactionEditorActive) { _, isActive in
            guard !isActive,
                  scenePhase == .active,
                  authStore.isAuthenticated,
                  launchBootstrapPreparedScopes.contains(currentSyncKey) else {
                return
            }

            // If a foreground or timer refresh was deferred to keep typing
            // responsive, catch up as soon as the editor has left the screen.
            foregroundRefreshTask?.cancel()
            foregroundRefreshTask = Task { @MainActor in
                await refreshCurrentBudget(forceSync: false)
            }
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        if appliedUserScopeId != authStore.currentUserScopeId || isCheckingCloudProfile {
            ProgressView("Preparing your budget")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background)
        } else if memberViewModel.isProfileComplete {
            RootTabView()
        } else {
            ProfileSetupView()
        }
    }

    @MainActor
    private func applyUserScope(_ userScopeId: String, budgetScopeId: String) {
        settingsStore.switchUser(to: budgetScopeId)
        memberViewModel.switchUser(
            to: userScopeId,
            budgetScopeId: budgetScopeId,
            email: authStore.userEmail
        )
    }

    @MainActor
    private func refreshCurrentBudget(forceSync: Bool) async {
        guard authStore.isAuthenticated else { return }

        applyUserScope(
            authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )

        await autoSyncAuthenticatedUser(
            authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId,
            force: forceSync,
            allowWhileEditing: forceSync
        )
    }

    @MainActor
    private func selectSharedBudgetIfNeeded(_ userScopeId: String) async -> Bool {
        guard memberViewModel.isProfileComplete else {
            return false
        }

        do {
            let memberships = try await cloudSyncStore.fetchMemberships(userScopeId: userScopeId)
            // The user may open the editor while this request is in flight.
            // Never switch the selected budget underneath an active draft.
            guard await waitUntilBootstrapCanContinue(userScopeId: userScopeId) else {
                return false
            }
            let currentScopeId = authStore.currentBudgetScopeId
            let canAccessCurrentScope = currentScopeId == userScopeId || memberships.contains {
                $0.budgetId.uuidString == currentScopeId
            }
            if !canAccessCurrentScope {
                authStore.switchBudgetScope(to: userScopeId)
                return false
            }

            guard !authStore.hasSelectedBudgetScope else { return true }
            if let sharedMembership = memberships.first(where: { $0.budgetId.uuidString != userScopeId }) {
                authStore.switchBudgetScope(to: sharedMembership.budgetId.uuidString)
                return false
            }
            return true
        } catch {
            cloudSyncStore.recordSyncIssue(error, context: "Selecting shared budget")
            // A transient network failure must not block the local budget.
            // Membership validation retries on the next scope initialization.
            return true
        }
    }

    @MainActor
    private func restoreCloudProfileIfNeeded(_ userScopeId: String) async {
        guard !memberViewModel.isProfileComplete,
              checkedCloudProfileUserScopeId != userScopeId else {
            return
        }

        isCheckingCloudProfile = true
        defer { isCheckingCloudProfile = false }

        do {
            let cloudMembers = try await cloudSyncStore.fetchMembers(
                userScopeId: userScopeId,
                budgetScopeId: userScopeId
            )
            _ = memberViewModel.restoreProfileIfPresent(
                from: cloudMembers,
                userScopeId: userScopeId,
                email: authStore.userEmail
            )
            checkedCloudProfileUserScopeId = userScopeId
        } catch {
            cloudSyncStore.recordSyncIssue(error, context: "Restoring cloud profile")
        }
    }

    @MainActor
    private func autoSyncAuthenticatedUser(
        _ userScopeId: String,
        budgetScopeId: String,
        force: Bool,
        allowWhileEditing: Bool = false
    ) async {
        let syncKey = makeSyncKey(userScopeId: userScopeId, budgetScopeId: budgetScopeId)
        guard memberViewModel.isProfileComplete else { return }

        // A full pull merges SwiftData on the main actor. Defer passive pulls
        // and the automatic launch pull while transaction UI owns the keyboard.
        // Immediate saves and an explicit user-requested refresh remain allowed.
        if !allowWhileEditing {
            // Give any pending tap/focus event one scheduler turn before the
            // synchronous SwiftData fetch begins on the main actor.
            await Task.yield()
            if isTransactionEntryActive {
                deferredAutoSyncScopes.insert(syncKey)
                return
            }
        }

        // Cached authentication can make scenePhase become active before the
        // local-first bootstrap task is ready. Do not let that callback sneak
        // a full pull into the launch grace period.
        if !force,
           !launchBootstrapPreparedScopes.contains(syncKey) {
            deferredAutoSyncScopes.insert(syncKey)
            return
        }

        let isCatchingUpDeferredSync = deferredAutoSyncScopes.contains(syncKey)
        guard shouldRunAutoSync(syncKey: syncKey, force: force || isCatchingUpDeferredSync),
              !autoSyncScopesInFlight.contains(syncKey) else {
            return
        }
        deferredAutoSyncScopes.remove(syncKey)
        // Coalesce before fetching SwiftData. CloudSyncStore also coalesces its
        // network operation, but by then each caller has already fetched and
        // sorted the complete local budget on the main actor.
        autoSyncScopesInFlight.insert(syncKey)
        defer { autoSyncScopesInFlight.remove(syncKey) }

        let context = persistenceController.container.mainContext
        let transactions: [Transaction]
        let settlements: [Settlement]

        do {
            let transactionDescriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.ownerUserId == budgetScopeId }
            )
            let settlementDescriptor = FetchDescriptor<Settlement>(
                predicate: #Predicate { $0.ownerUserId == budgetScopeId }
            )
            let fetchedTransactions = try context.fetch(transactionDescriptor)
            let fetchedSettlements = try context.fetch(settlementDescriptor)
            if duplicatePruningCompletedScopes.contains(syncKey) {
                transactions = fetchedTransactions
                settlements = fetchedSettlements
            } else {
                // UUID duplication is legacy-store repair work, not something
                // that should sort every transaction during each periodic sync.
                transactions = pruneDuplicateTransactions(fetchedTransactions, in: context)
                settlements = pruneDuplicateSettlements(fetchedSettlements, in: context)
                duplicatePruningCompletedScopes.insert(syncKey)
            }
        } catch {
            cloudSyncStore.recordSyncIssue(error, context: "Loading local data for sync")
            return
        }

        let settingsSyncToken = settingsStore.pendingCloudSyncToken
        let memberSyncToken = memberViewModel.pendingCloudSyncToken
        guard let summary = await cloudSyncStore.syncIfPossible(
            settings: settingsStore.settings,
            shouldPushSettings: settingsSyncToken != nil,
            members: memberViewModel.members,
            shouldPushMembers: memberSyncToken != nil,
            transactions: transactions,
            settlements: settlements,
            into: context,
            userScopeId: userScopeId,
            userEmail: authStore.userEmail,
            budgetScopeId: budgetScopeId
        ) else {
            guard !Task.isCancelled else { return }
            recordAutoSyncFailure(for: syncKey)
            return
        }
        lastAutoSyncedAtByScope[syncKey] = .now
        autoSyncFailureCountByScope.removeValue(forKey: syncKey)
        nextAutoSyncAllowedAtByScope.removeValue(forKey: syncKey)

        // The sync already observed cloud settings and members; reuse them
        // instead of issuing two more fetches per cycle.
        if summary.pushedSettings, let settingsSyncToken {
            settingsStore.markCloudSyncSucceeded(settingsSyncToken)
        }
        if summary.pushedMembers > 0, let memberSyncToken {
            memberViewModel.markCloudSyncSucceeded(memberSyncToken)
        }

        // A retained cloud task may finish after the user switches budgets.
        // Its scoped model merge is still valid, but its settings/member
        // summary must never be applied to the newly selected scope.
        guard authStore.currentUserScopeId == userScopeId,
              authStore.currentBudgetScopeId == budgetScopeId else {
            return
        }

        if settingsStore.pendingCloudSyncToken == nil,
           let cloudSettings = summary.settings {
            settingsStore.replaceSettings(cloudSettings)
        }
        if memberViewModel.pendingCloudSyncToken == nil,
           !summary.members.isEmpty {
            memberViewModel.replaceMembers(with: summary.members)
        }
    }

    private func shouldRunAutoSync(syncKey: String, force: Bool) -> Bool {
        guard !force else { return true }
        if let nextAllowedAt = nextAutoSyncAllowedAtByScope[syncKey],
           Date.now < nextAllowedAt {
            return false
        }
        guard let lastSyncedAt = lastAutoSyncedAtByScope[syncKey] else { return true }
        return Date().timeIntervalSince(lastSyncedAt) > minimumPassiveSyncInterval
    }

    private func recordAutoSyncFailure(for syncKey: String) {
        let failureCount = autoSyncFailureCountByScope[syncKey, default: 0] + 1
        autoSyncFailureCountByScope[syncKey] = failureCount
        let delay = min(300, 15 * pow(2, Double(min(failureCount - 1, 5))))
        nextAutoSyncAllowedAtByScope[syncKey] = .now.addingTimeInterval(delay)
    }

    private var currentSyncKey: String {
        makeSyncKey(
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
    }

    private var isTransactionEntryActive: Bool {
        transactionFlow.shouldPresentAddTransaction || transactionFlow.isTransactionEditorActive
    }

    private func makeSyncKey(userScopeId: String, budgetScopeId: String) -> String {
        "\(userScopeId)-\(budgetScopeId)"
    }

    @MainActor
    private func waitForLaunchInteractionWindow(userScopeId: String, budgetScopeId: String) async -> Bool {
        do {
            // Reserve the first two seconds for local rendering, tab setup,
            // and UIKit's first keyboard initialization on older devices.
            try await Task.sleep(for: launchInteractionGracePeriod)
        } catch {
            return false
        }

        return await waitUntilBootstrapCanContinue(
            userScopeId: userScopeId,
            budgetScopeId: budgetScopeId
        )
    }

    @MainActor
    private func waitUntilBootstrapCanContinue(
        userScopeId: String,
        budgetScopeId: String? = nil
    ) async -> Bool {
        while scenePhase != .active || isTransactionEntryActive {
            guard !Task.isCancelled,
                  authStore.isAuthenticated,
                  authStore.currentUserScopeId == userScopeId,
                  budgetScopeId == nil || authStore.currentBudgetScopeId == budgetScopeId else {
                return false
            }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return false
            }
        }

        return !Task.isCancelled
            && authStore.isAuthenticated
            && authStore.currentUserScopeId == userScopeId
            && (budgetScopeId == nil || authStore.currentBudgetScopeId == budgetScopeId)
    }

    @MainActor
    @discardableResult
    private func recordLaunchMilestone(_ milestone: String) -> Bool {
        guard loggedLaunchMilestones.insert(milestone).inserted else { return false }
        let elapsed = ProcessInfo.processInfo.systemUptime - launchStartedAtUptime
        Self.launchLogger.notice("\(milestone, privacy: .public) after \(elapsed, privacy: .public) seconds")
        return true
    }

    @MainActor
    private func pruneDuplicateTransactions(_ transactions: [Transaction], in context: ModelContext) -> [Transaction] {
        var keptTransactions: [UUID: Transaction] = [:]

        for transaction in transactions.sorted(by: newestTransactionFirst) {
            if keptTransactions[transaction.id] == nil {
                keptTransactions[transaction.id] = transaction
            } else {
                context.delete(transaction)
            }
        }

        return keptTransactions.values.sorted(by: newestTransactionFirst)
    }

    private func newestTransactionFirst(_ lhs: Transaction, _ rhs: Transaction) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    @MainActor
    private func pruneDuplicateSettlements(_ settlements: [Settlement], in context: ModelContext) -> [Settlement] {
        var keptSettlements: [UUID: Settlement] = [:]

        for settlement in settlements.sorted(by: { $0.date > $1.date }) {
            if keptSettlements[settlement.id] == nil {
                keptSettlements[settlement.id] = settlement
            } else {
                context.delete(settlement)
            }
        }

        return keptSettlements.values.sorted { $0.date > $1.date }
    }

    @MainActor
    private func runAutoSyncLoop(userScopeId: String, budgetScopeId: String) async {
        guard memberViewModel.isProfileComplete,
              scenePhase == .active else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: activeSyncInterval)
            } catch {
                return
            }

            guard scenePhase == .active,
                  authStore.isAuthenticated,
                  authStore.currentUserScopeId == userScopeId,
                  authStore.currentBudgetScopeId == budgetScopeId else {
                continue
            }

            await autoSyncAuthenticatedUser(userScopeId, budgetScopeId: budgetScopeId, force: false)
        }
    }
}

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
    @State private var checkedCloudProfileUserScopeId: String?
    @State private var isCheckingCloudProfile = false
    private let persistenceController = PersistenceController.shared

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
                            .task(id: authStore.currentUserScopeId + authStore.currentBudgetScopeId + String(memberViewModel.isProfileComplete)) {
                                applyUserScope(authStore.currentUserScopeId, budgetScopeId: authStore.currentBudgetScopeId)
                                await restoreCloudProfileIfNeeded(authStore.currentUserScopeId)
                                // Reveal the app with on-device data as soon as the
                                // profile is known, instead of blocking the tabs on the
                                // shared-budget lookup and full sync that follow.
                                appliedUserScopeId = authStore.currentUserScopeId
                                await selectSharedBudgetIfNeeded(authStore.currentUserScopeId)
                                applyUserScope(authStore.currentUserScopeId, budgetScopeId: authStore.currentBudgetScopeId)
                                await autoSyncAuthenticatedUser(
                                    authStore.currentUserScopeId,
                                    budgetScopeId: authStore.currentBudgetScopeId,
                                    force: true
                                )
                            }
                            .task(id: "auto-sync-\(authStore.currentUserScopeId)-\(authStore.currentBudgetScopeId)-\(memberViewModel.isProfileComplete)") {
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
            guard phase == .active,
                  authStore.isAuthenticated else {
                return
            }

            Task {
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
        memberViewModel.switchUser(to: userScopeId, email: authStore.userEmail)
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
            force: forceSync
        )
    }

    @MainActor
    private func selectSharedBudgetIfNeeded(_ userScopeId: String) async {
        guard memberViewModel.isProfileComplete,
              !authStore.hasSelectedBudgetScope else {
            return
        }

        do {
            let memberships = try await cloudSyncStore.fetchMemberships(userScopeId: userScopeId)
            if let sharedMembership = memberships.first(where: { $0.budgetId.uuidString != userScopeId }) {
                authStore.switchBudgetScope(to: sharedMembership.budgetId.uuidString)
            }
        } catch {
            cloudSyncStore.recordSyncIssue(error, context: "Selecting shared budget")
        }
    }

    @MainActor
    private func restoreCloudProfileIfNeeded(_ userScopeId: String) async {
        guard !memberViewModel.isProfileComplete,
              checkedCloudProfileUserScopeId != userScopeId else {
            return
        }

        checkedCloudProfileUserScopeId = userScopeId
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
        } catch {
            cloudSyncStore.recordSyncIssue(error, context: "Restoring cloud profile")
        }
    }

    @MainActor
    private func autoSyncAuthenticatedUser(_ userScopeId: String, budgetScopeId: String, force: Bool) async {
        let syncKey = "\(userScopeId)-\(budgetScopeId)"
        guard memberViewModel.isProfileComplete,
              shouldRunAutoSync(syncKey: syncKey, force: force) else {
            return
        }

        lastAutoSyncedAtByScope[syncKey] = .now

        let context = persistenceController.container.mainContext
        let transactions: [Transaction]
        let settlements: [Settlement]

        do {
            transactions = try context.fetch(FetchDescriptor<Transaction>())
                .filter { $0.ownerUserId == budgetScopeId }
            settlements = try context.fetch(FetchDescriptor<Settlement>())
                .filter { $0.ownerUserId == budgetScopeId }
        } catch {
            cloudSyncStore.recordSyncIssue(error, context: "Loading local data for sync")
            return
        }

        let didRunSync = await cloudSyncStore.syncIfPossible(
            settings: settingsStore.settings,
            members: memberViewModel.members,
            transactions: transactions,
            settlements: settlements,
            into: context,
            userScopeId: userScopeId,
            userEmail: authStore.userEmail,
            budgetScopeId: budgetScopeId
        )
        guard didRunSync else { return }

        do {
            if let cloudSettings = try await cloudSyncStore.fetchSettings(userScopeId: userScopeId, budgetScopeId: budgetScopeId) {
                settingsStore.replaceSettings(cloudSettings)
            }
        } catch {
            cloudSyncStore.recordSyncIssue(error, context: "Refreshing cloud settings")
        }

        do {
            let cloudMembers = try await cloudSyncStore.fetchMembers(userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            if !cloudMembers.isEmpty {
                memberViewModel.replaceMembers(with: cloudMembers)
            }
        } catch {
            cloudSyncStore.recordSyncIssue(error, context: "Refreshing cloud members")
        }
    }

    private func shouldRunAutoSync(syncKey: String, force: Bool) -> Bool {
        guard !force else { return true }
        guard let lastSyncedAt = lastAutoSyncedAtByScope[syncKey] else { return true }
        return Date().timeIntervalSince(lastSyncedAt) > 45
    }

    @MainActor
    private func runAutoSyncLoop(userScopeId: String, budgetScopeId: String) async {
        guard memberViewModel.isProfileComplete else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(60))
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

import Foundation
import OSLog
import SwiftData

@MainActor
final class AppRefreshStore: ObservableObject {
    typealias RefreshAction = (_ forceSync: Bool) async -> Void

    private var refreshAction: RefreshAction?

    func configure(refreshAction: @escaping RefreshAction) {
        self.refreshAction = refreshAction
    }

    func refreshCurrentBudget(forceSync: Bool = true) async {
        guard let refreshAction else { return }
        await refreshAction(forceSync)
    }
}

@MainActor
final class CloudSyncStore: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastDiagnosticMessage: String?

    private let service: SupabaseBudgetSyncService
    private let logger = Logger(subsystem: "BudgetMate", category: "CloudSync")
    private let maxRetryAttempts = 3
    private var pendingFullSyncRequest: FullSyncRequest?

    init(service: SupabaseBudgetSyncService = SupabaseBudgetSyncService()) {
        self.service = service
    }

    var hasSyncIssue: Bool {
        userFacingLastErrorMessage != nil
    }

    var syncHelpText: String {
        if isSyncing {
            return "Saving your latest changes to the cloud."
        }

        if let userFacingLastErrorMessage {
            return userFacingLastErrorMessage
        }

        if lastSyncedAt == nil {
            return "Your data is saved on this device. Tap Sync Now to back it up."
        }

        return "Your latest changes are backed up."
    }

    var userFacingLastErrorMessage: String? {
        guard let lastErrorMessage else { return nil }
        return friendlyMessage(for: lastErrorMessage)
    }

    func statusText(referenceDate: Date = .now) -> String {
        if isSyncing {
            return "Syncing now"
        }

        if hasSyncIssue {
            return "Needs attention"
        }

        guard let lastSyncedAt else {
            return "Ready to sync"
        }

        let elapsed = referenceDate.timeIntervalSince(lastSyncedAt)
        guard elapsed >= 60 else {
            return "Synced just now"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Synced " + formatter.localizedString(for: lastSyncedAt, relativeTo: referenceDate)
    }

    func userFacingMessage(for error: Error) -> String {
        friendlyMessage(for: error.localizedDescription)
    }

    func sync(
        settings: BudgetSettings,
        members: [BudgetMember],
        transactions: [Transaction],
        settlements: [Settlement],
        into context: ModelContext,
        userScopeId: String,
        userEmail: String? = nil,
        budgetScopeId: String? = nil
    ) async throws -> CloudBudgetSyncSummary {
        let request = FullSyncRequest(
            settings: settings,
            members: members,
            transactions: transactions,
            settlements: settlements,
            context: context,
            userScopeId: userScopeId,
            userEmail: userEmail,
            budgetScopeId: budgetScopeId
        )

        guard !isSyncing else {
            pendingFullSyncRequest = request
            throw CloudSyncStoreError.syncAlreadyRunning
        }

        let summary = try await performFullSync(request)
        await drainPendingFullSyncRequests()
        return summary
    }

    private func performFullSync(_ request: FullSyncRequest) async throws -> CloudBudgetSyncSummary {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let summary = try await runWithRetry {
                try await self.service.sync(
                    settings: request.settings,
                    members: request.members,
                    transactions: request.transactions,
                    settlements: request.settlements,
                    into: request.context,
                    userScopeId: request.userScopeId,
                    userEmail: request.userEmail,
                    budgetScopeId: request.budgetScopeId
                )
            }
            do {
                try request.context.save()
            } catch {
                markFailed(error, context: "Saving merged cloud data")
                throw error
            }
            markSynced()
            return summary
        } catch {
            markFailed(error, context: "Full sync")
            throw error
        }
    }

    private func drainPendingFullSyncRequests() async {
        while let request = pendingFullSyncRequest {
            pendingFullSyncRequest = nil

            do {
                _ = try await performFullSync(request)
            } catch {
                markFailed(error, context: "Queued full sync")
                return
            }
        }
    }

    @discardableResult
    func syncIfPossible(
        settings: BudgetSettings,
        members: [BudgetMember],
        transactions: [Transaction],
        settlements: [Settlement],
        into context: ModelContext,
        userScopeId: String,
        userEmail: String? = nil,
        budgetScopeId: String? = nil
    ) async -> Bool {
        let request = FullSyncRequest(
            settings: settings,
            members: members,
            transactions: transactions,
            settlements: settlements,
            context: context,
            userScopeId: userScopeId,
            userEmail: userEmail,
            budgetScopeId: budgetScopeId
        )

        guard !isSyncing else {
            pendingFullSyncRequest = request
            return false
        }

        do {
            _ = try await performFullSync(request)
            await drainPendingFullSyncRequests()
            return true
        } catch {
            guard !(error is CloudSyncStoreError) else { return false }
            markFailed(error, context: "Background sync")
            return false
        }
    }

    func ensureSharedBudget(name: String, userScopeId: String) async throws -> BudgetSummary {
        do {
            let budget = try await runWithRetry {
                try await self.service.ensureSharedBudget(name: name, userScopeId: userScopeId)
            }
            markSynced()
            return budget
        } catch {
            markFailed(error, context: "Creating shared budget")
            throw error
        }
    }

    func fetchOwnedBudgets(userScopeId: String) async throws -> [BudgetSummary] {
        do {
            return try await runWithRetry {
                try await self.service.fetchOwnedBudgets(userScopeId: userScopeId)
            }
        } catch {
            markFailed(error, context: "Fetching households")
            throw error
        }
    }

    func inviteMember(displayName: String, email: String, userScopeId: String, budgetId: UUID) async throws {
        do {
            try await runWithRetry {
                try await self.service.createInvite(
                    displayName: displayName,
                    email: email,
                    userScopeId: userScopeId,
                    budgetId: budgetId
                )
            }
            markSynced()
        } catch {
            markFailed(error, context: "Inviting member")
            throw error
        }
    }

    func fetchPendingInvites(email: String) async throws -> [BudgetInvite] {
        do {
            return try await runWithRetry {
                try await self.service.fetchPendingInvites(email: email)
            }
        } catch {
            markFailed(error, context: "Fetching invites")
            throw error
        }
    }

    func fetchMemberships(userScopeId: String) async throws -> [BudgetMembership] {
        do {
            return try await runWithRetry {
                try await self.service.fetchMemberships(userScopeId: userScopeId)
            }
        } catch {
            markFailed(error, context: "Fetching memberships")
            throw error
        }
    }

    func repairMemberProfileIfNeeded(userScopeId: String, userEmail: String?, budgetScopeId: String? = nil) async {
        guard let userEmail else { return }

        do {
            try await service.repairMemberProfileIfNeeded(
                userScopeId: userScopeId,
                userEmail: userEmail,
                budgetScopeId: budgetScopeId
            )
        } catch {
            markFailed(error, context: "Repairing member profile")
        }
    }

    func acceptInvite(_ invite: BudgetInvite, userScopeId: String) async throws {
        do {
            try await runWithRetry {
                try await self.service.acceptInvite(invite, userScopeId: userScopeId)
            }
            markSynced()
        } catch {
            markFailed(error, context: "Accepting invite")
            throw error
        }
    }

    func leaveBudget(userScopeId: String, budgetScopeId: String) async throws {
        do {
            try await runWithRetry {
                try await self.service.leaveBudget(userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            }
            markSynced()
        } catch {
            markFailed(error, context: "Leaving budget")
            throw error
        }
    }

    private func markSynced() {
        lastErrorMessage = nil
        lastDiagnosticMessage = nil
        lastSyncedAt = .now
    }

    func fetchSettings(userScopeId: String, budgetScopeId: String? = nil) async throws -> BudgetSettings? {
        do {
            return try await runWithRetry {
                try await self.service.fetchSettings(userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            }
        } catch {
            markFailed(error, context: "Fetching settings")
            throw error
        }
    }

    func saveSettings(_ settings: BudgetSettings, userScopeId: String, budgetScopeId: String? = nil) {
        Task {
            await runSave {
                try await self.service.upsertSettings(settings, userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            }
        }
    }

    func fetchMembers(userScopeId: String, budgetScopeId: String? = nil) async throws -> [BudgetMember] {
        do {
            return try await runWithRetry {
                try await self.service.fetchMembers(userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            }
        } catch {
            markFailed(error, context: "Fetching members")
            throw error
        }
    }

    func saveMembers(_ members: [BudgetMember], userScopeId: String, budgetScopeId: String? = nil) {
        Task {
            await runSave {
                try await self.service.upsertMembers(members, userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            }
        }
    }

    func deleteMember(_ member: BudgetMember, userScopeId: String, budgetScopeId: String? = nil) {
        Task {
            await runSave {
                try await self.service.deleteMember(member, userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            }
        }
    }

    func revokeMembership(memberUserId: UUID, userScopeId: String, budgetScopeId: String? = nil) {
        Task {
            await runSave {
                try await self.service.revokeMembership(
                    memberUserId: memberUserId,
                    userScopeId: userScopeId,
                    budgetScopeId: budgetScopeId
                )
            }
        }
    }

    func deleteTransaction(_ transaction: Transaction, userScopeId: String, budgetScopeId: String? = nil) {
        Task {
            await runSave {
                try await self.service.deleteTransaction(transaction, userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            }
        }
    }

    func saveTransaction(_ transaction: Transaction, userScopeId: String, budgetScopeId: String? = nil) {
        Task {
            await runSave {
                try await self.service.upsertTransaction(transaction, userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            }
        }
    }

    func saveSettlement(_ settlement: Settlement, userScopeId: String, budgetScopeId: String? = nil) {
        Task {
            await runSave {
                try await self.service.upsertSettlement(settlement, userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            }
        }
    }

    func deleteSettlement(_ settlement: Settlement, userScopeId: String, budgetScopeId: String? = nil) {
        Task {
            await runSave {
                try await self.service.deleteSettlement(settlement, userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            }
        }
    }

    func deleteAllBudgetData(userScopeId: String, budgetScopeId: String? = nil) {
        Task {
            await runSave {
                try await self.service.deleteAllBudgetData(userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            }
        }
    }

    func deleteAllBudgetDataNow(userScopeId: String, budgetScopeId: String? = nil) async throws {
        do {
            try await runWithRetry {
                try await self.service.deleteAllBudgetData(userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            }
            markSynced()
        } catch {
            markFailed(error, context: "Clearing cloud budget data")
            throw error
        }
    }

    private func runSave(_ operation: @escaping () async throws -> Void) async {
        do {
            try await runWithRetry(operation)
            markSynced()
        } catch {
            markFailed(error, context: "Saving cloud change")
        }
    }

    func recordSyncIssue(_ error: Error, context: String) {
        markFailed(error, context: context)
    }

    private func runWithRetry<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        var attempt = 1

        while true {
            do {
                return try await operation()
            } catch {
                if error is CancellationError || attempt >= maxRetryAttempts {
                    throw error
                }

                let delayNanoseconds = UInt64(pow(2.0, Double(attempt - 1)) * 500_000_000)
                try await Task.sleep(nanoseconds: delayNanoseconds)
                attempt += 1
            }
        }
    }

    private func markFailed(_ error: Error, context: String) {
        if error is CancellationError {
            return
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        guard !message.localizedCaseInsensitiveContains("cancelled"),
              !message.localizedCaseInsensitiveContains("canceled") else {
            return
        }

        let diagnostic = "\(context): \(message)"
        logger.error("\(diagnostic, privacy: .private)")
        lastDiagnosticMessage = diagnostic
        lastErrorMessage = message
    }

    private func friendlyMessage(for message: String) -> String {
        if message.localizedCaseInsensitiveContains("cancelled") ||
            message.localizedCaseInsensitiveContains("canceled") {
            return "Sync was stopped before it finished. Try again when you are ready."
        }

        if message.localizedCaseInsensitiveContains("row-level security") {
            return "We couldn't save to this shared budget yet. Check your access or try syncing again."
        }

        if message.localizedCaseInsensitiveContains("ON CONFLICT DO UPDATE") ||
            message.localizedCaseInsensitiveContains("cannot affect row a second time") {
            return "We found duplicate local rows while syncing. Tap Retry Sync to clean them up and try again."
        }

        if message.localizedCaseInsensitiveContains("Could not find the table") ||
            message.localizedCaseInsensitiveContains("budget_transactions") {
            return "Cloud tables are not ready yet. Finish the Supabase setup, then sync again."
        }

        if message.localizedCaseInsensitiveContains("internet connection") ||
            message.localizedCaseInsensitiveContains("network") {
            return "We couldn't reach the cloud right now. Check your connection and try again."
        }

        return message
    }
}

enum CloudSyncStoreError: LocalizedError {
    case syncAlreadyRunning

    var errorDescription: String? {
        switch self {
        case .syncAlreadyRunning:
            return "Sync is already running."
        }
    }
}

private struct FullSyncRequest {
    let settings: BudgetSettings
    let members: [BudgetMember]
    let transactions: [Transaction]
    let settlements: [Settlement]
    let context: ModelContext
    let userScopeId: String
    let userEmail: String?
    let budgetScopeId: String?
}

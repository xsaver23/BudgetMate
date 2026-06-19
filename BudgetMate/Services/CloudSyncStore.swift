import Foundation
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

    private let service: SupabaseBudgetSyncService

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
        isSyncing = true
        defer { isSyncing = false }

        do {
            let summary = try await service.sync(
                settings: settings,
                members: members,
                transactions: transactions,
                settlements: settlements,
                into: context,
                userScopeId: userScopeId,
                userEmail: userEmail,
                budgetScopeId: budgetScopeId
            )
            try? context.save()
            markSynced()
            return summary
        } catch {
            markFailed(error)
            throw error
        }
    }

    func syncIfPossible(
        settings: BudgetSettings,
        members: [BudgetMember],
        transactions: [Transaction],
        settlements: [Settlement],
        into context: ModelContext,
        userScopeId: String,
        userEmail: String? = nil,
        budgetScopeId: String? = nil
    ) async {
        do {
            _ = try await sync(
                settings: settings,
                members: members,
                transactions: transactions,
                settlements: settlements,
                into: context,
                userScopeId: userScopeId,
                userEmail: userEmail,
                budgetScopeId: budgetScopeId
            )
        } catch {
            markFailed(error)
        }
    }

    func inviteMember(displayName: String, email: String, userScopeId: String) async throws {
        do {
            try await service.createInvite(displayName: displayName, email: email, userScopeId: userScopeId)
            markSynced()
        } catch {
            markFailed(error)
            throw error
        }
    }

    func fetchPendingInvites(email: String) async throws -> [BudgetInvite] {
        do {
            return try await service.fetchPendingInvites(email: email)
        } catch {
            markFailed(error)
            throw error
        }
    }

    func fetchMemberships(userScopeId: String) async throws -> [BudgetMembership] {
        do {
            return try await service.fetchMemberships(userScopeId: userScopeId)
        } catch {
            markFailed(error)
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
            markFailed(error)
        }
    }

    func acceptInvite(_ invite: BudgetInvite, userScopeId: String) async throws {
        do {
            try await service.acceptInvite(invite, userScopeId: userScopeId)
            markSynced()
        } catch {
            markFailed(error)
            throw error
        }
    }

    func leaveBudget(userScopeId: String, budgetScopeId: String) async throws {
        do {
            try await service.leaveBudget(userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            markSynced()
        } catch {
            markFailed(error)
            throw error
        }
    }

    private func markSynced() {
        lastErrorMessage = nil
        lastSyncedAt = .now
    }

    func fetchSettings(userScopeId: String, budgetScopeId: String? = nil) async throws -> BudgetSettings? {
        try await service.fetchSettings(userScopeId: userScopeId, budgetScopeId: budgetScopeId)
    }

    func saveSettings(_ settings: BudgetSettings, userScopeId: String, budgetScopeId: String? = nil) {
        Task {
            await runSave {
                try await self.service.upsertSettings(settings, userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            }
        }
    }

    func fetchMembers(userScopeId: String, budgetScopeId: String? = nil) async throws -> [BudgetMember] {
        try await service.fetchMembers(userScopeId: userScopeId, budgetScopeId: budgetScopeId)
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

    private func runSave(_ operation: @escaping () async throws -> Void) async {
        do {
            try await operation()
            markSynced()
        } catch {
            markFailed(error)
        }
    }

    private func markFailed(_ error: Error) {
        if error is CancellationError {
            return
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        guard !message.localizedCaseInsensitiveContains("cancelled"),
              !message.localizedCaseInsensitiveContains("canceled") else {
            return
        }

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

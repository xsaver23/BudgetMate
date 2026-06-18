import Foundation
import SwiftData

@MainActor
final class CloudSyncStore: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastErrorMessage: String?

    private let service: SupabaseBudgetSyncService

    init(service: SupabaseBudgetSyncService = SupabaseBudgetSyncService()) {
        self.service = service
    }

    func sync(
        settings: BudgetSettings,
        members: [BudgetMember],
        transactions: [Transaction],
        settlements: [Settlement],
        into context: ModelContext,
        userScopeId: String,
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
        lastErrorMessage = error.localizedDescription
    }
}

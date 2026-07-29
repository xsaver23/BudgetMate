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
    private let userDefaults: UserDefaults
    // Internal so the test foundation can verify the durable codec without
    // reaching into a live Supabase client or exposing a public API.
    static let pendingCloudDeletionsKey = "budgetmate.pendingCloudDeletions"
    static let pendingCloudDeletionSafetyVersionKey = "budgetmate.pendingCloudDeletions.safetyVersion"
    static let currentPendingCloudDeletionSafetyVersion = 2
    private var activeFullSync: ActiveFullSync?
    private var pendingMutationTask: Task<Void, Never>?
    private var pendingMutationToken: UUID?
    private var transactionSaveRevisions: [UUID: Int] = [:]
    private var settlementSaveRevisions: [UUID: Int] = [:]
    private var pendingCloudDeletions: [PendingCloudDeletion]

    init(service: SupabaseBudgetSyncService? = nil, userDefaults: UserDefaults = .standard) {
        self.service = service ?? SupabaseBudgetSyncService()
        self.userDefaults = userDefaults
        pendingCloudDeletions = Self.loadPendingCloudDeletions(
            from: userDefaults,
            key: Self.pendingCloudDeletionsKey
        )
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
            return "Syncing"
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

        return "Synced " + Self.relativeDateFormatter.localizedString(for: lastSyncedAt, relativeTo: referenceDate)
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    func userFacingMessage(for error: Error) -> String {
        friendlyMessage(for: error.localizedDescription)
    }

    func sync(
        settings: BudgetSettings,
        shouldPushSettings: Bool = false,
        members: [BudgetMember],
        shouldPushMembers: Bool = false,
        transactions: [Transaction],
        settlements: [Settlement],
        into context: ModelContext,
        userScopeId: String,
        userEmail: String? = nil,
        budgetScopeId: String? = nil
    ) async throws -> CloudBudgetSyncSummary {
        let request = FullSyncRequest(
            settings: settings,
            shouldPushSettings: shouldPushSettings,
            members: members,
            shouldPushMembers: shouldPushMembers,
            transactions: transactions,
            settlements: settlements,
            context: context,
            userScopeId: userScopeId,
            userEmail: userEmail,
            budgetScopeId: budgetScopeId
        )

        return try await coalescedFullSync(request)
    }

    private func coalescedFullSync(_ request: FullSyncRequest) async throws -> CloudBudgetSyncSummary {
        if let activeFullSync {
            if activeFullSync.scopeKey == request.scopeKey {
                let summary = try await activeFullSync.task.value
                try Task.checkCancellation()
                return summary
            }

            _ = try? await activeFullSync.task.value
            try Task.checkCancellation()
            return try await coalescedFullSync(request)
        }

        let token = UUID()
        let precedingMutation = pendingMutationTask
        let task = Task { @MainActor [weak self] () throws -> CloudBudgetSyncSummary in
            guard let self else { throw CancellationError() }
            await precedingMutation?.value
            try Task.checkCancellation()
            defer { self.finishFullSync(token: token) }
            return try await self.performFullSync(request)
        }
        activeFullSync = ActiveFullSync(token: token, scopeKey: request.scopeKey, task: task)
        let summary = try await task.value
        try Task.checkCancellation()
        return summary
    }

    private func finishFullSync(token: UUID) {
        guard activeFullSync?.token == token else { return }
        activeFullSync = nil
    }

    private func performFullSync(_ request: FullSyncRequest) async throws -> CloudBudgetSyncSummary {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let summary = try await runWithRetry {
                try await self.flushPendingCloudDeletions(for: request.userScopeId)
                return try await self.service.sync(
                    settings: request.settings,
                    shouldPushSettings: request.shouldPushSettings,
                    members: request.members,
                    shouldPushMembers: request.shouldPushMembers,
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
            if SupabaseBudgetSyncService.shouldDeferFinancialWrites(
                transactions: request.transactions,
                settlements: request.settlements
            ) {
                markFailed(
                    SupabaseBudgetSyncError.sharedDataSafetyDisabled,
                    context: "Shared-data changes remain local while safety is disabled"
                )
            } else {
                markSynced()
            }
            return summary
        } catch {
            markFailed(error, context: "Full sync")
            throw error
        }
    }

    @discardableResult
    func syncIfPossible(
        settings: BudgetSettings,
        shouldPushSettings: Bool = false,
        members: [BudgetMember],
        shouldPushMembers: Bool = false,
        transactions: [Transaction],
        settlements: [Settlement],
        into context: ModelContext,
        userScopeId: String,
        userEmail: String? = nil,
        budgetScopeId: String? = nil
    ) async -> CloudBudgetSyncSummary? {
        let request = FullSyncRequest(
            settings: settings,
            shouldPushSettings: shouldPushSettings,
            members: members,
            shouldPushMembers: shouldPushMembers,
            transactions: transactions,
            settlements: settlements,
            context: context,
            userScopeId: userScopeId,
            userEmail: userEmail,
            budgetScopeId: budgetScopeId
        )

        do {
            return try await coalescedFullSync(request)
        } catch {
            markFailed(error, context: "Background sync")
            return nil
        }
    }

    func ensureSharedBudget(name: String, userScopeId: String) async throws -> BudgetSummary {
        guard GateDControlledBetaPolicy.allowsSharedBudgetInvites else {
            throw SupabaseBudgetSyncError.sharedBudgetInvitesUnavailable
        }

        // Keep ids stable across retry attempts so the atomic database function
        // is idempotent even if its response is lost after the commit.
        let budgetId = UUID()
        let ownerMemberId = UUID()
        do {
            let budget = try await runWithRetry {
                try await self.service.ensureSharedBudget(
                    name: name,
                    userScopeId: userScopeId,
                    budgetId: budgetId,
                    ownerMemberId: ownerMemberId
                )
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
        guard GateDControlledBetaPolicy.allowsSharedBudgetInvites else {
            throw SupabaseBudgetSyncError.sharedBudgetInvitesUnavailable
        }

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
        guard GateDControlledBetaPolicy.allowsSharedBudgetLeave else {
            throw SupabaseBudgetSyncError.sharedBudgetLeaveUnavailable
        }

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

    func fetchCurrencyBaseline(
        userScopeId: String,
        budgetScopeId: String? = nil
    ) async throws -> CloudCurrencyBaselineSnapshot {
        do {
            return try await runWithRetry {
                try await self.service.fetchCurrencyBaseline(
                    userScopeId: userScopeId,
                    budgetScopeId: budgetScopeId
                )
            }
        } catch {
            markFailed(error, context: "Fetching currency baseline")
            throw error
        }
    }

    func saveSettings(
        _ settings: BudgetSettings,
        userScopeId: String,
        budgetScopeId: String? = nil,
        onSuccess: (() -> Void)? = nil
    ) {
        enqueueSave(
            operation: {
                try await self.service.upsertSettings(settings, userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            },
            onSuccess: onSuccess
        )
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

    func saveMembers(
        _ members: [BudgetMember],
        userScopeId: String,
        budgetScopeId: String? = nil,
        onSuccess: (() -> Void)? = nil
    ) {
        enqueueSave(
            operation: {
                try await self.service.upsertMembers(members, userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            },
            onSuccess: onSuccess
        )
    }

    func deleteMember(_ member: BudgetMember, userScopeId: String, budgetScopeId: String? = nil) {
        let deletion = PendingCloudDeletion(
            entity: .member,
            recordId: member.id,
            userScopeId: userScopeId,
            budgetScopeId: budgetScopeId ?? userScopeId
        )
        recordPendingCloudDeletion(deletion)
        enqueueSave(
            operation: {
                try await self.service.deleteMember(
                    id: member.id,
                    userScopeId: userScopeId,
                    budgetScopeId: budgetScopeId
                )
            },
            onSuccess: { [weak self] in self?.clearPendingCloudDeletion(deletion) }
        )
    }

    func revokeMembership(memberUserId: UUID, userScopeId: String, budgetScopeId: String? = nil) {
        let deletion = PendingCloudDeletion(
            entity: .membership,
            recordId: memberUserId,
            userScopeId: userScopeId,
            budgetScopeId: budgetScopeId ?? userScopeId
        )
        recordPendingCloudDeletion(deletion)
        enqueueSave(
            operation: {
                try await self.service.revokeMembership(
                    memberUserId: memberUserId,
                    userScopeId: userScopeId,
                    budgetScopeId: budgetScopeId
                )
            },
            onSuccess: { [weak self] in self?.clearPendingCloudDeletion(deletion) }
        )
    }

    func deleteTransaction(_ transaction: Transaction, userScopeId: String, budgetScopeId: String? = nil) {
        let transactionId = transaction.id
        let deletion = PendingCloudDeletion(
            entity: .transaction,
            recordId: transactionId,
            userScopeId: userScopeId,
            budgetScopeId: budgetScopeId ?? userScopeId,
            expectedRowVersion: transaction.rowVersion,
            mutationId: UUID()
        )
        transactionSaveRevisions[transactionId, default: 0] += 1
        recordPendingCloudDeletion(deletion)
        guard SharedDataSafetyGate.isEnabled else {
            markFailed(SupabaseBudgetSyncError.sharedDataSafetyDisabled, context: "Deleting transaction in the cloud")
            return
        }
        enqueueSave(
            operation: {
                do {
                    _ = try await self.service.deleteTransactionSafely(
                        id: transactionId,
                        expectedRowVersion: deletion.expectedRowVersion,
                        userScopeId: userScopeId,
                        budgetScopeId: budgetScopeId,
                        mutationId: deletion.mutationId ?? UUID()
                    )
                } catch SupabaseBudgetSyncError.remoteDeleted {
                    self.clearPendingCloudDeletion(deletion)
                    throw SupabaseBudgetSyncError.remoteDeleted
                }
            },
            onSuccess: { [weak self] in self?.clearPendingCloudDeletion(deletion) }
        )
    }

    func saveTransaction(_ transaction: Transaction, userScopeId: String, budgetScopeId: String? = nil) {
        saveTransactions([transaction], userScopeId: userScopeId, budgetScopeId: budgetScopeId)
    }

    func saveTransactions(
        _ transactions: [Transaction],
        userScopeId: String,
        budgetScopeId: String? = nil
    ) {
        guard !transactions.isEmpty else { return }

        guard SharedDataSafetyGate.isEnabled else {
            transactions.forEach { $0.needsSync = true }
            markFailed(SupabaseBudgetSyncError.sharedDataSafetyDisabled, context: "Saving transactions to the cloud")
            return
        }

        let revisions = transactions.map { transaction -> (transaction: Transaction, id: UUID, revision: Int, mutationId: UUID) in
            transaction.needsSync = true
            let transactionId = transaction.id
            let revision = transactionSaveRevisions[transactionId, default: 0] + 1
            transactionSaveRevisions[transactionId] = revision
            let mutationId = UUID()
            transaction.lastMutationId = mutationId
            return (transaction, transactionId, revision, mutationId)
        }
        enqueueSave(
            operation: {
                do {
                    for transaction in transactions {
                        let result = try await self.service.mutateTransaction(
                            transaction,
                            operation: transaction.rowVersion == nil ? "insert" : "update",
                            userScopeId: userScopeId,
                            budgetScopeId: budgetScopeId,
                            mutationId: revisions.first(where: { $0.id == transaction.id })?.mutationId ?? UUID()
                        )
                        transaction.rowVersion = result.rowVersion
                    }
                } catch SupabaseBudgetSyncError.remoteDeleted {
                    for entry in revisions
                    where self.transactionSaveRevisions[entry.id] == entry.revision {
                        entry.transaction.needsSync = false
                        self.transactionSaveRevisions.removeValue(forKey: entry.id)
                    }
                    throw SupabaseBudgetSyncError.remoteDeleted
                }
            },
            onSuccess: { [weak self] in
                guard let self else { return }
                for entry in revisions
                where self.transactionSaveRevisions[entry.id] == entry.revision {
                    entry.transaction.needsSync = false
                    self.transactionSaveRevisions.removeValue(forKey: entry.id)
                }
            }
        )
    }

    func saveSettlement(_ settlement: Settlement, userScopeId: String, budgetScopeId: String? = nil) {
        guard SharedDataSafetyGate.isEnabled else {
            settlement.needsSync = true
            markFailed(SupabaseBudgetSyncError.sharedDataSafetyDisabled, context: "Saving settlement to the cloud")
            return
        }
        settlement.needsSync = true
        let settlementId = settlement.id
        let revision = settlementSaveRevisions[settlementId, default: 0] + 1
        settlementSaveRevisions[settlementId] = revision
        let mutationId = UUID()
        settlement.lastMutationId = mutationId
        enqueueSave(
            operation: {
                do {
                    let result = try await self.service.mutateSettlement(
                        settlement,
                        operation: settlement.rowVersion == nil ? "insert" : "update",
                        userScopeId: userScopeId,
                        budgetScopeId: budgetScopeId,
                        mutationId: mutationId
                    )
                    settlement.rowVersion = result.rowVersion
                    settlement.lastMutationId = mutationId
                } catch SupabaseBudgetSyncError.remoteDeleted {
                    if self.settlementSaveRevisions[settlementId] == revision {
                        settlement.needsSync = false
                        self.settlementSaveRevisions.removeValue(forKey: settlementId)
                    }
                    throw SupabaseBudgetSyncError.remoteDeleted
                }
            },
            onSuccess: { [weak self, weak settlement] in
                guard let self,
                      let settlement,
                      self.settlementSaveRevisions[settlementId] == revision else { return }
                settlement.needsSync = false
                self.settlementSaveRevisions.removeValue(forKey: settlementId)
            }
        )
    }

    func deleteSettlement(_ settlement: Settlement, userScopeId: String, budgetScopeId: String? = nil) {
        let settlementId = settlement.id
        let deletion = PendingCloudDeletion(
            entity: .settlement,
            recordId: settlementId,
            userScopeId: userScopeId,
            budgetScopeId: budgetScopeId ?? userScopeId,
            expectedRowVersion: settlement.rowVersion,
            mutationId: UUID()
        )
        settlementSaveRevisions[settlementId, default: 0] += 1
        recordPendingCloudDeletion(deletion)
        guard SharedDataSafetyGate.isEnabled else {
            markFailed(SupabaseBudgetSyncError.sharedDataSafetyDisabled, context: "Deleting settlement in the cloud")
            return
        }
        enqueueSave(
            operation: {
                do {
                    _ = try await self.service.deleteSettlementSafely(
                        id: settlementId,
                        expectedRowVersion: deletion.expectedRowVersion,
                        userScopeId: userScopeId,
                        budgetScopeId: budgetScopeId,
                        mutationId: deletion.mutationId ?? UUID()
                    )
                } catch SupabaseBudgetSyncError.remoteDeleted {
                    self.clearPendingCloudDeletion(deletion)
                    throw SupabaseBudgetSyncError.remoteDeleted
                }
            },
            onSuccess: { [weak self] in self?.clearPendingCloudDeletion(deletion) }
        )
    }

    func deleteAllBudgetData(userScopeId: String, budgetScopeId: String? = nil) {
        enqueueSave {
                try await self.service.deleteAllBudgetData(userScopeId: userScopeId, budgetScopeId: budgetScopeId)
        }
    }

    func deleteAllBudgetDataNow(userScopeId: String, budgetScopeId: String? = nil) async throws {
        do {
            try await performSerializedMutation {
                try await self.service.deleteAllBudgetData(userScopeId: userScopeId, budgetScopeId: budgetScopeId)
            }
        } catch {
            markFailed(error, context: "Clearing cloud budget data")
            throw error
        }
    }

    private func enqueueSave(
        operation: @escaping () async throws -> Void,
        onSuccess: (() -> Void)? = nil
    ) {
        let precedingMutation = pendingMutationTask
        let activeSync = activeFullSync?.task
        let token = UUID()
        let task = Task { @MainActor [weak self] in
            if let activeSync {
                _ = try? await activeSync.value
            }
            await precedingMutation?.value
            guard let self else { return }
            defer { self.finishMutation(token: token) }
            if await self.runSave(operation) {
                onSuccess?()
            }
        }
        pendingMutationToken = token
        pendingMutationTask = task
    }

    private func finishMutation(token: UUID) {
        guard pendingMutationToken == token else { return }
        pendingMutationToken = nil
        pendingMutationTask = nil
    }

    private func performSerializedMutation<T>(
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        let precedingMutation = pendingMutationTask
        let activeSync = activeFullSync?.task

        return try await withCheckedThrowingContinuation { continuation in
            let token = UUID()
            let task = Task { @MainActor [weak self] in
                if let activeSync {
                    _ = try? await activeSync.value
                }
                await precedingMutation?.value
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                defer { self.finishMutation(token: token) }

                do {
                    let value = try await self.runWithRetry(operation)
                    self.markSynced()
                    continuation.resume(returning: value)
                } catch {
                    self.markFailed(error, context: "Saving cloud change")
                    continuation.resume(throwing: error)
                }
            }
            pendingMutationToken = token
            pendingMutationTask = task
        }
    }

    private func flushPendingCloudDeletions(for userScopeId: String) async throws {
        guard SharedDataSafetyGate.isEnabled else { return }
        let deletions = pendingCloudDeletions.filter { $0.userScopeId == userScopeId }
        for deletion in deletions {
            switch deletion.entity {
            case .member:
                try await service.deleteMember(
                    id: deletion.recordId,
                    userScopeId: deletion.userScopeId,
                    budgetScopeId: deletion.budgetScopeId
                )
            case .membership:
                try await service.revokeMembership(
                    memberUserId: deletion.recordId,
                    userScopeId: deletion.userScopeId,
                    budgetScopeId: deletion.budgetScopeId
                )
            case .transaction:
                guard let expectedRowVersion = deletion.expectedRowVersion,
                      let mutationId = deletion.mutationId else {
                    throw SupabaseBudgetSyncError.unsafePendingDeletion
                }
                do {
                    _ = try await service.deleteTransactionSafely(
                        id: deletion.recordId,
                        expectedRowVersion: expectedRowVersion,
                        userScopeId: deletion.userScopeId,
                        budgetScopeId: deletion.budgetScopeId,
                        mutationId: mutationId
                    )
                } catch SupabaseBudgetSyncError.remoteDeleted {
                    clearPendingCloudDeletion(deletion)
                    throw SupabaseBudgetSyncError.remoteDeleted
                }
            case .settlement:
                guard let expectedRowVersion = deletion.expectedRowVersion,
                      let mutationId = deletion.mutationId else {
                    throw SupabaseBudgetSyncError.unsafePendingDeletion
                }
                do {
                    _ = try await service.deleteSettlementSafely(
                        id: deletion.recordId,
                        expectedRowVersion: expectedRowVersion,
                        userScopeId: deletion.userScopeId,
                        budgetScopeId: deletion.budgetScopeId,
                        mutationId: mutationId
                    )
                } catch SupabaseBudgetSyncError.remoteDeleted {
                    clearPendingCloudDeletion(deletion)
                    throw SupabaseBudgetSyncError.remoteDeleted
                }
            }
            clearPendingCloudDeletion(deletion)
        }
    }

    private func recordPendingCloudDeletion(_ deletion: PendingCloudDeletion) {
        guard !pendingCloudDeletions.contains(deletion) else { return }
        pendingCloudDeletions.append(deletion)
        persistPendingCloudDeletions()
    }

    private func clearPendingCloudDeletion(_ deletion: PendingCloudDeletion) {
        pendingCloudDeletions.removeAll { $0 == deletion }
        persistPendingCloudDeletions()
    }

    private func persistPendingCloudDeletions() {
        guard let data = try? JSONEncoder().encode(pendingCloudDeletions) else { return }
        userDefaults.set(data, forKey: Self.pendingCloudDeletionsKey)
    }

    static func loadPendingCloudDeletions(
        from userDefaults: UserDefaults,
        key: String
    ) -> [PendingCloudDeletion] {
        let safetyVersionKey = key == Self.pendingCloudDeletionsKey
            ? Self.pendingCloudDeletionSafetyVersionKey
            : "\(key).safetyVersion"
        let storedSafetyVersion = userDefaults.integer(forKey: safetyVersionKey)

        // The pre-00B queue did not record why a transaction was deleted. The
        // old member-removal flow could therefore persist a transaction-only
        // prefix before it reached its member marker. Clear every pre-00B job
        // once on upgrade; a recoverable remote row may reappear, but unknown
        // legacy work can no longer permanently erase history.
        guard storedSafetyVersion >= Self.currentPendingCloudDeletionSafetyVersion else {
            userDefaults.removeObject(forKey: key)
            userDefaults.set(
                Self.currentPendingCloudDeletionSafetyVersion,
                forKey: safetyVersionKey
            )
            return []
        }

        guard let data = userDefaults.data(forKey: key),
              let deletions = try? JSONDecoder().decode([PendingCloudDeletion].self, from: data) else {
            return []
        }

        // PR 00B removes the legacy UI that queued member, membership, and
        // member-linked transaction deletions as one non-atomic batch. Those
        // legacy records have no origin metadata, so preserve data on upgrade:
        // if a scope contains either lifecycle deletion, discard the entire
        // pending batch for that scope instead of replaying a partial history
        // deletion. Standalone record deletions in other scopes stay queued.
        let unsafeScopeKeys = Set(
            deletions.compactMap { deletion -> String? in
                switch deletion.entity {
                case .member, .membership:
                    return deletion.scopeKey
                case .transaction, .settlement:
                    return nil
                }
            }
        )
        guard !unsafeScopeKeys.isEmpty else {
            return deletions
        }

        let sanitized = deletions.filter { !unsafeScopeKeys.contains($0.scopeKey) }
        if let sanitizedData = try? JSONEncoder().encode(sanitized) {
            userDefaults.set(sanitizedData, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
        return sanitized
    }

    @discardableResult
    private func runSave(_ operation: @escaping () async throws -> Void) async -> Bool {
        do {
            try await runWithRetry(operation)
            markSynced()
            return true
        } catch {
            markFailed(error, context: "Saving cloud change")
            return false
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
                if error is CancellationError || !Self.isRetryable(error) || attempt >= maxRetryAttempts {
                    throw error
                }

                let delayNanoseconds = UInt64(pow(2.0, Double(attempt - 1)) * 500_000_000)
                try await Task.sleep(nanoseconds: delayNanoseconds)
                attempt += 1
            }
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let error = error as? SupabaseBudgetSyncError else { return true }
        switch error {
        case .idempotencyMismatch,
             .remoteDeleted,
             .mutationRecordNotFound,
             .invalidMemberReference,
             .memberReferenceForbidden,
             .sharedDataMutationConflict,
             .sharedDataSafetyDisabled,
             .unsafePendingDeletion,
             .sharedBudgetInvitesUnavailable,
             .sharedBudgetLeaveUnavailable:
            return false
        case .missingUser,
             .notBudgetOwner,
             .invalidCloudDate,
             .invalidCloudMoneyContract:
            return true
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

        if message.localizedCaseInsensitiveContains("changed on another device") {
            return "This shared record changed on another device. Refresh before trying again."
        }

        if message.localizedCaseInsensitiveContains("remote_deleted") ||
            message.localizedCaseInsensitiveContains("already deleted on another device") {
            return "This record was already deleted on another device. It was not recreated."
        }

        if message.localizedCaseInsensitiveContains("idempotency_mismatch") {
            return "This cloud retry did not match the original change and was not applied. Refresh before trying again."
        }

        if message.localizedCaseInsensitiveContains("shared-data safety writes") {
            return SharedDataSafetyGate.readOnlyMessage
        }

        if message.localizedCaseInsensitiveContains("pending deletion") {
            return "A pending deletion was held until its conflict metadata can be verified."
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

private struct FullSyncRequest {
    let settings: BudgetSettings
    let shouldPushSettings: Bool
    let members: [BudgetMember]
    let shouldPushMembers: Bool
    let transactions: [Transaction]
    let settlements: [Settlement]
    let context: ModelContext
    let userScopeId: String
    let userEmail: String?
    let budgetScopeId: String?

    var scopeKey: String {
        "\(userScopeId)|\(budgetScopeId ?? userScopeId)"
    }
}

private struct ActiveFullSync {
    let token: UUID
    let scopeKey: String
    let task: Task<CloudBudgetSyncSummary, Error>
}

struct PendingCloudDeletion: Codable, Hashable {
    enum Entity: String, Codable {
        case member
        case membership
        case transaction
        case settlement
    }

    let entity: Entity
    let recordId: UUID
    let userScopeId: String
    let budgetScopeId: String
    let expectedRowVersion: Int64?
    let mutationId: UUID?

    init(
        entity: Entity,
        recordId: UUID,
        userScopeId: String,
        budgetScopeId: String,
        expectedRowVersion: Int64? = nil,
        mutationId: UUID? = nil
    ) {
        self.entity = entity
        self.recordId = recordId
        self.userScopeId = userScopeId
        self.budgetScopeId = budgetScopeId
        self.expectedRowVersion = expectedRowVersion
        self.mutationId = mutationId
    }

    fileprivate var scopeKey: String {
        "\(userScopeId)|\(budgetScopeId)"
    }
}

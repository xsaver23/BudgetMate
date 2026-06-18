import Foundation
import Supabase
import SwiftData

struct CloudBudgetSyncSummary {
    let syncedSettings: Bool
    let pushedMembers: Int
    let pulledMembers: Int
    let pushedTransactions: Int
    let pulledTransactions: Int
    let pushedSettlements: Int
    let pulledSettlements: Int

    var message: String {
        let settingsText = syncedSettings ? "settings, " : ""
        let memberCount = max(pushedMembers, pulledMembers)
        let transactionCount = max(pushedTransactions, pulledTransactions)
        let settlementCount = max(pushedSettlements, pulledSettlements)

        if settlementCount > 0 {
            return "Cloud sync is up to date. Checked \(settingsText)\(memberCount) member\(memberCount == 1 ? "" : "s"), \(transactionCount) transaction\(transactionCount == 1 ? "" : "s"), and \(settlementCount) settle-up record\(settlementCount == 1 ? "" : "s")."
        }

        return "Cloud sync is up to date. Checked \(settingsText)\(memberCount) member\(memberCount == 1 ? "" : "s") and \(transactionCount) transaction\(transactionCount == 1 ? "" : "s")."
    }
}

enum SupabaseBudgetSyncError: LocalizedError {
    case missingUser

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return "Sign in again before syncing."
        }
    }
}

struct CloudBudgetSettingsRow: Codable {
    let userId: UUID
    let budgetId: UUID
    let monthlyBudget: Double
    let currencyCode: String
    let appearance: String
    let categoryBudgets: [String: Double]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case budgetId = "budget_id"
        case monthlyBudget = "monthly_budget"
        case currencyCode = "currency_code"
        case appearance
        case categoryBudgets = "category_budgets"
    }

    init(settings: BudgetSettings, userId: UUID, budgetId: UUID? = nil) {
        self.userId = userId
        self.budgetId = budgetId ?? userId
        monthlyBudget = settings.monthlyBudget
        currencyCode = settings.currencyCode
        appearance = settings.appearance.rawValue
        categoryBudgets = settings.categoryBudgets
    }

    func makeSettings() -> BudgetSettings {
        BudgetSettings(
            monthlyBudget: monthlyBudget,
            currencyCode: currencyCode,
            appearance: AppearanceOption(rawValue: appearance) ?? .system,
            categoryBudgets: categoryBudgets
        )
    }
}

struct CloudBudgetMemberRow: Codable {
    let id: UUID
    let userId: UUID
    let budgetId: UUID
    let displayName: String
    let email: String?
    let initials: String
    let color: String
    let authUserId: UUID?
    let role: String
    let inviteStatus: String
    let joinedDate: String?
    let createdDate: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case budgetId = "budget_id"
        case displayName = "display_name"
        case email
        case initials
        case color
        case authUserId = "auth_user_id"
        case role
        case inviteStatus = "invite_status"
        case joinedDate = "joined_date"
        case createdDate = "created_date"
    }

    init(member: BudgetMember, userId: UUID, budgetId: UUID? = nil) {
        id = member.id
        self.userId = userId
        self.budgetId = budgetId ?? userId
        displayName = member.displayName
        email = member.email
        initials = member.initials
        color = member.color
        authUserId = member.authUserId
        role = member.role.rawValue
        inviteStatus = member.inviteStatus.rawValue
        joinedDate = member.joinedDate.map(Self.string(from:))
        createdDate = Self.string(from: member.createdDate)
    }

    func makeMember() -> BudgetMember {
        BudgetMember(
            id: id,
            displayName: displayName,
            email: email,
            initials: initials,
            color: color,
            authUserId: authUserId,
            role: BudgetMemberRole(rawValue: role) ?? .member,
            inviteStatus: InviteStatus(rawValue: inviteStatus) ?? .active,
            joinedDate: joinedDate.map(Self.date(from:)),
            createdDate: Self.date(from: createdDate)
        )
    }

    private static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(from string: String) -> Date {
        ISO8601DateFormatter().date(from: string) ?? .now
    }
}

private struct CloudBudgetRow: Codable {
    let id: UUID
    let ownerUserId: UUID
    let name: String

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserId = "owner_user_id"
        case name
    }
}

private struct CloudBudgetMembershipRow: Codable {
    let budgetId: UUID
    let userId: UUID
    let role: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case budgetId = "budget_id"
        case userId = "user_id"
        case role
        case status
    }

    func makeMembership() -> BudgetMembership {
        BudgetMembership(
            budgetId: budgetId,
            userId: userId,
            role: role,
            status: status
        )
    }
}

private struct CloudBudgetInviteRow: Codable {
    let id: UUID
    let budgetId: UUID
    let invitedByUserId: UUID
    let displayName: String
    let email: String
    let status: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case budgetId = "budget_id"
        case invitedByUserId = "invited_by_user_id"
        case displayName = "display_name"
        case email
        case status
        case createdAt = "created_at"
    }

    init(displayName: String, email: String, invitedByUserId: UUID) {
        id = UUID()
        budgetId = invitedByUserId
        self.invitedByUserId = invitedByUserId
        self.displayName = displayName
        self.email = email.lowercased()
        status = "pending"
        createdAt = ISO8601DateFormatter().string(from: .now)
    }

    func makeInvite() -> BudgetInvite {
        BudgetInvite(
            id: id,
            budgetId: budgetId,
            invitedByUserId: invitedByUserId,
            displayName: displayName,
            email: email,
            status: status,
            createdAt: ISO8601DateFormatter().date(from: createdAt) ?? .now
        )
    }
}

private struct CloudBudgetInviteUpdateRow: Codable {
    let status: String
    let acceptedAt: String
    let acceptedByUserId: UUID?

    enum CodingKeys: String, CodingKey {
        case status
        case acceptedAt = "accepted_at"
        case acceptedByUserId = "accepted_by_user_id"
    }

    init(status: String, acceptedByUserId: UUID? = nil) {
        self.status = status
        self.acceptedByUserId = acceptedByUserId
        acceptedAt = ISO8601DateFormatter().string(from: .now)
    }
}

private struct CloudBudgetMemberAcceptedUpdateRow: Codable {
    let authUserId: UUID
    let inviteStatus: String
    let joinedDate: String

    enum CodingKeys: String, CodingKey {
        case authUserId = "auth_user_id"
        case inviteStatus = "invite_status"
        case joinedDate = "joined_date"
    }

    init(authUserId: UUID) {
        self.authUserId = authUserId
        inviteStatus = InviteStatus.active.rawValue
        joinedDate = ISO8601DateFormatter().string(from: .now)
    }
}

struct CloudTransactionSplitRow: Codable {
    let id: UUID
    let memberId: UUID
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case id
        case memberId = "member_id"
        case amount
    }
}

struct CloudTransactionRow: Codable {
    let id: UUID
    let userId: UUID
    let budgetId: UUID
    let title: String
    let amount: Double
    let type: String
    let category: String
    let paymentMethod: String?
    let createdByMemberId: UUID
    let date: String
    let createdAt: String
    let recurrenceRule: String?
    let splits: [CloudTransactionSplitRow]

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case budgetId = "budget_id"
        case title
        case amount
        case type
        case category
        case paymentMethod = "payment_method"
        case createdByMemberId = "created_by_member_id"
        case date
        case createdAt = "created_at"
        case recurrenceRule = "recurrence_rule"
        case splits
    }

    init(transaction: Transaction, userId: UUID, budgetId: UUID? = nil) {
        id = transaction.id
        self.userId = userId
        self.budgetId = budgetId ?? userId
        title = transaction.title
        amount = transaction.amount
        type = transaction.type.rawValue
        category = transaction.category.rawValue
        paymentMethod = transaction.paymentMethod?.rawValue
        createdByMemberId = transaction.createdByMemberId
        date = Self.string(from: transaction.date)
        createdAt = Self.string(from: transaction.createdAt)
        recurrenceRule = transaction.recurrenceRule
        splits = transaction.splits.map {
            CloudTransactionSplitRow(id: $0.id, memberId: $0.memberId, amount: $0.amount)
        }
    }

    func apply(to transaction: Transaction, ownerUserId: String) {
        transaction.title = title
        transaction.amount = amount
        transaction.type = TransactionType(rawValue: type) ?? .expense
        transaction.category = TransactionCategory(rawValue: category)
        transaction.paymentMethod = paymentMethod.flatMap(PaymentMethod.init(rawValue:))
        transaction.createdByMemberId = createdByMemberId
        transaction.date = Self.date(from: date)
        transaction.createdAt = Self.date(from: createdAt)
        transaction.recurrenceRule = recurrenceRule
        transaction.ownerUserId = ownerUserId
    }

    func makeTransaction(ownerUserId: String) -> Transaction {
        Transaction(
            id: id,
            title: title,
            amount: amount,
            type: TransactionType(rawValue: type) ?? .expense,
            category: TransactionCategory(rawValue: category),
            paymentMethod: paymentMethod.flatMap(PaymentMethod.init(rawValue:)),
            createdByMemberId: createdByMemberId,
            date: Self.date(from: date),
            createdAt: Self.date(from: createdAt),
            recurrenceRule: recurrenceRule,
            ownerUserId: ownerUserId
        )
    }

    private static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(from string: String) -> Date {
        ISO8601DateFormatter().date(from: string) ?? .now
    }
}

struct CloudSettlementRow: Codable {
    let id: UUID
    let userId: UUID
    let budgetId: UUID
    let fromMemberId: UUID
    let toMemberId: UUID
    let amount: Double
    let date: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case budgetId = "budget_id"
        case fromMemberId = "from_member_id"
        case toMemberId = "to_member_id"
        case amount
        case date
    }

    init(settlement: Settlement, userId: UUID, budgetId: UUID? = nil) {
        id = settlement.id
        self.userId = userId
        self.budgetId = budgetId ?? userId
        fromMemberId = settlement.fromMemberId
        toMemberId = settlement.toMemberId
        amount = settlement.amount
        date = ISO8601DateFormatter().string(from: settlement.date)
    }

    func apply(to settlement: Settlement, ownerUserId: String) {
        settlement.fromMemberId = fromMemberId
        settlement.toMemberId = toMemberId
        settlement.amount = amount
        settlement.date = ISO8601DateFormatter().date(from: date) ?? .now
        settlement.ownerUserId = ownerUserId
    }

    func makeSettlement(ownerUserId: String) -> Settlement {
        Settlement(
            id: id,
            fromMemberId: fromMemberId,
            toMemberId: toMemberId,
            amount: amount,
            date: ISO8601DateFormatter().date(from: date) ?? .now,
            ownerUserId: ownerUserId
        )
    }
}

final class SupabaseBudgetSyncService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
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
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId

        try await ensurePersonalBudget(userId: userId)

        let existingSettings = try await fetchSettings(userScopeId: userScopeId, budgetScopeId: budgetId.uuidString)
        let settingsRow = CloudBudgetSettingsRow(settings: settings, userId: userId, budgetId: budgetId)
        let memberRows = members.map { CloudBudgetMemberRow(member: $0, userId: userId, budgetId: budgetId) }
        let signedInMemberIds = signedInMemberIds(for: userId, in: members)
        let transactionRows = transactions
            .filter { shouldBulkPush(transaction: $0, signedInMemberIds: signedInMemberIds) }
            .map { CloudTransactionRow(transaction: $0, userId: userId, budgetId: budgetId) }
        let settlementRows = settlements
            .filter { shouldBulkPush(settlement: $0, signedInMemberIds: signedInMemberIds) }
            .map { CloudSettlementRow(settlement: $0, userId: userId, budgetId: budgetId) }

        if budgetId == userId && (existingSettings == nil || settings != .default) {
            try await client
                .from("budget_settings")
                .upsert(settingsRow, onConflict: "user_id")
                .execute()
        }

        if budgetId == userId && !memberRows.isEmpty && !Self.isDefaultSampleMembers(members) {
            try await client
                .from("budget_members")
                .upsert(memberRows, onConflict: "id")
                .execute()
        }

        if budgetId == userId && !transactionRows.isEmpty {
            try await client
                .from("budget_transactions")
                .upsert(transactionRows, onConflict: "id")
                .execute()
        }

        if budgetId == userId && !settlementRows.isEmpty {
            try await client
                .from("budget_settlements")
                .upsert(settlementRows, onConflict: "id")
                .execute()
        }

        let pulledTransactions: [CloudTransactionRow] = try await client
            .from("budget_transactions")
            .select()
            .eq("budget_id", value: budgetId)
            .execute()
            .value

        let pulledSettlements: [CloudSettlementRow] = try await client
            .from("budget_settlements")
            .select()
            .eq("budget_id", value: budgetId)
            .execute()
            .value

        merge(pulledTransactions, into: context, existing: transactions, ownerUserId: budgetId.uuidString)
        merge(pulledSettlements, into: context, existing: settlements, ownerUserId: budgetId.uuidString)
        let pulledMembers = try await fetchMembers(userScopeId: userScopeId, budgetScopeId: budgetId.uuidString)

        return CloudBudgetSyncSummary(
            syncedSettings: true,
            pushedMembers: memberRows.count,
            pulledMembers: pulledMembers.count,
            pushedTransactions: transactionRows.count,
            pulledTransactions: pulledTransactions.count,
            pushedSettlements: settlementRows.count,
            pulledSettlements: pulledSettlements.count
        )
    }

    func fetchSettings(userScopeId: String, budgetScopeId: String? = nil) async throws -> BudgetSettings? {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId

        let rows: [CloudBudgetSettingsRow] = try await client
            .from("budget_settings")
            .select()
            .eq("budget_id", value: budgetId)
            .execute()
            .value

        return rows.first?.makeSettings()
    }

    func upsertSettings(_ settings: BudgetSettings, userScopeId: String, budgetScopeId: String? = nil) async throws {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId

        try await ensurePersonalBudget(userId: userId)
        guard budgetId == userId else { return }

        let row = CloudBudgetSettingsRow(settings: settings, userId: userId, budgetId: budgetId)
        try await client
            .from("budget_settings")
            .upsert(row, onConflict: "user_id")
            .execute()
    }

    func fetchMembers(userScopeId: String, budgetScopeId: String? = nil) async throws -> [BudgetMember] {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId

        let rows: [CloudBudgetMemberRow] = try await client
            .from("budget_members")
            .select()
            .eq("budget_id", value: budgetId)
            .execute()
            .value

        return rows.map { $0.makeMember() }
    }

    func upsertMembers(_ members: [BudgetMember], userScopeId: String, budgetScopeId: String? = nil) async throws {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId

        try await ensurePersonalBudget(userId: userId)
        guard budgetId == userId else { return }

        guard !members.isEmpty else { return }
        let rows = members.map { CloudBudgetMemberRow(member: $0, userId: userId, budgetId: budgetId) }
        try await client
            .from("budget_members")
            .upsert(rows, onConflict: "id")
            .execute()
    }

    func createInvite(displayName: String, email: String, userScopeId: String) async throws {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }

        try await ensurePersonalBudget(userId: userId)

        let row = CloudBudgetInviteRow(
            displayName: displayName,
            email: email,
            invitedByUserId: userId
        )

        try await client
            .from("budget_invites")
            .upsert(row, onConflict: "budget_id,email")
            .execute()
    }

    func fetchPendingInvites(email: String) async throws -> [BudgetInvite] {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else { return [] }

        let rows: [CloudBudgetInviteRow] = try await client
            .from("budget_invites")
            .select()
            .eq("email", value: normalizedEmail)
            .eq("status", value: "pending")
            .execute()
            .value

        return rows.map { $0.makeInvite() }
    }

    func fetchMemberships(userScopeId: String) async throws -> [BudgetMembership] {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }

        let rows: [CloudBudgetMembershipRow] = try await client
            .from("budget_memberships")
            .select()
            .eq("user_id", value: userId)
            .eq("status", value: "active")
            .execute()
            .value

        return rows.map { $0.makeMembership() }
    }

    func acceptInvite(_ invite: BudgetInvite, userScopeId: String) async throws {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }

        let membership = CloudBudgetMembershipRow(
            budgetId: invite.budgetId,
            userId: userId,
            role: "member",
            status: "active"
        )

        try await client
            .from("budget_memberships")
            .upsert(membership, onConflict: "budget_id,user_id")
            .execute()

        try await client
            .from("budget_members")
            .update(CloudBudgetMemberAcceptedUpdateRow(authUserId: userId))
            .eq("budget_id", value: invite.budgetId)
            .eq("email", value: invite.email.lowercased())
            .execute()

        try await client
            .from("budget_invites")
            .update(CloudBudgetInviteUpdateRow(status: "accepted", acceptedByUserId: userId))
            .eq("id", value: invite.id)
            .execute()
    }

    func leaveBudget(userScopeId: String, budgetScopeId: String) async throws {
        guard let userId = UUID(uuidString: userScopeId),
              let budgetId = UUID(uuidString: budgetScopeId),
              budgetId != userId else {
            return
        }

        try await client
            .from("budget_memberships")
            .delete()
            .eq("budget_id", value: budgetId)
            .eq("user_id", value: userId)
            .execute()
    }

    func deleteMember(_ member: BudgetMember, userScopeId: String, budgetScopeId: String? = nil) async throws {
        guard let userId = UUID(uuidString: userScopeId) else { return }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId

        try await client
            .from("budget_members")
            .delete()
            .eq("id", value: member.id)
            .eq("budget_id", value: budgetId)
            .execute()
    }

    func revokeMembership(memberUserId: UUID, userScopeId: String, budgetScopeId: String? = nil) async throws {
        guard let ownerId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? ownerId
        guard memberUserId != ownerId else { return }

        try await client
            .from("budget_memberships")
            .delete()
            .eq("budget_id", value: budgetId)
            .eq("user_id", value: memberUserId)
            .execute()
    }

    func deleteTransaction(_ transaction: Transaction, userScopeId: String, budgetScopeId: String? = nil) async throws {
        guard let userId = UUID(uuidString: userScopeId) else { return }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId
        try await client
            .from("budget_transactions")
            .delete()
            .eq("id", value: transaction.id)
            .eq("budget_id", value: budgetId)
            .execute()
    }

    func upsertTransaction(_ transaction: Transaction, userScopeId: String, budgetScopeId: String? = nil) async throws {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId

        try await ensurePersonalBudget(userId: userId)

        let row = CloudTransactionRow(transaction: transaction, userId: userId, budgetId: budgetId)
        try await client
            .from("budget_transactions")
            .upsert(row, onConflict: "id")
            .execute()
    }

    func upsertSettlement(_ settlement: Settlement, userScopeId: String, budgetScopeId: String? = nil) async throws {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId

        try await ensurePersonalBudget(userId: userId)

        let row = CloudSettlementRow(settlement: settlement, userId: userId, budgetId: budgetId)
        try await client
            .from("budget_settlements")
            .upsert(row, onConflict: "id")
            .execute()
    }

    func deleteSettlement(_ settlement: Settlement, userScopeId: String, budgetScopeId: String? = nil) async throws {
        guard let userId = UUID(uuidString: userScopeId) else { return }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId
        try await client
            .from("budget_settlements")
            .delete()
            .eq("id", value: settlement.id)
            .eq("budget_id", value: budgetId)
            .execute()
    }

    func deleteAllBudgetData(userScopeId: String, budgetScopeId: String? = nil) async throws {
        guard let userId = UUID(uuidString: userScopeId) else { return }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId

        try await client
            .from("budget_transactions")
            .delete()
            .eq("budget_id", value: budgetId)
            .execute()

        try await client
            .from("budget_settlements")
            .delete()
            .eq("budget_id", value: budgetId)
            .execute()
    }

    private func ensurePersonalBudget(userId: UUID) async throws {
        let budget = CloudBudgetRow(
            id: userId,
            ownerUserId: userId,
            name: "My Budget"
        )
        let membership = CloudBudgetMembershipRow(
            budgetId: userId,
            userId: userId,
            role: "owner",
            status: "active"
        )

        try await client
            .from("budgets")
            .upsert(budget, onConflict: "id")
            .execute()

        try await client
            .from("budget_memberships")
            .upsert(membership, onConflict: "budget_id,user_id")
            .execute()
    }

    private static func isDefaultSampleMembers(_ members: [BudgetMember]) -> Bool {
        let memberIds = Set(members.map(\.id))
        let sampleIds = Set(BudgetSampleData.members.map(\.id))
        return memberIds == sampleIds
    }

    private func signedInMemberIds(for userId: UUID, in members: [BudgetMember]) -> Set<UUID> {
        let matchingIds = members.compactMap { member -> UUID? in
            if member.id == userId || member.authUserId == userId {
                return member.id
            }
            return nil
        }

        return Set(matchingIds.isEmpty ? [userId] : matchingIds)
    }

    private func shouldBulkPush(transaction: Transaction, signedInMemberIds: Set<UUID>) -> Bool {
        signedInMemberIds.contains(transaction.createdByMemberId)
    }

    private func shouldBulkPush(settlement: Settlement, signedInMemberIds: Set<UUID>) -> Bool {
        signedInMemberIds.contains(settlement.fromMemberId) || signedInMemberIds.contains(settlement.toMemberId)
    }

    private func merge(
        _ rows: [CloudTransactionRow],
        into context: ModelContext,
        existing transactions: [Transaction],
        ownerUserId: String
    ) {
        let existingById = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })

        for row in rows {
            let transaction = existingById[row.id] ?? row.makeTransaction(ownerUserId: ownerUserId)
            if existingById[row.id] == nil {
                context.insert(transaction)
            } else {
                row.apply(to: transaction, ownerUserId: ownerUserId)
            }

            for split in Array(transaction.splits) {
                context.delete(split)
            }

            for splitRow in row.splits where splitRow.amount > 0 {
                context.insert(
                    TransactionSplit(
                        id: splitRow.id,
                        memberId: splitRow.memberId,
                        amount: splitRow.amount,
                        transaction: transaction
                    )
                )
            }
        }
    }

    private func merge(
        _ rows: [CloudSettlementRow],
        into context: ModelContext,
        existing settlements: [Settlement],
        ownerUserId: String
    ) {
        let existingById = Dictionary(uniqueKeysWithValues: settlements.map { ($0.id, $0) })

        for row in rows {
            if let settlement = existingById[row.id] {
                row.apply(to: settlement, ownerUserId: ownerUserId)
            } else {
                context.insert(row.makeSettlement(ownerUserId: ownerUserId))
            }
        }
    }
}

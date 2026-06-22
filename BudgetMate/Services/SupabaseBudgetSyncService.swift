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
    case notBudgetOwner
    case invalidCloudDate(String)

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return "Sign in again before syncing."
        case .notBudgetOwner:
            return "Only the household owner can invite members."
        case .invalidCloudDate(let value):
            return "Cloud data has an invalid date: \(value)."
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
    let categoryEmojis: [String: String]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case budgetId = "budget_id"
        case monthlyBudget = "monthly_budget"
        case currencyCode = "currency_code"
        case appearance
        case categoryBudgets = "category_budgets"
        case categoryEmojis = "category_emojis"
    }

    init(
        userId: UUID,
        budgetId: UUID,
        monthlyBudget: Double,
        currencyCode: String,
        appearance: String,
        categoryBudgets: [String: Double],
        categoryEmojis: [String: String] = [:]
    ) {
        self.userId = userId
        self.budgetId = budgetId
        self.monthlyBudget = monthlyBudget
        self.currencyCode = currencyCode
        self.appearance = appearance
        self.categoryBudgets = categoryBudgets
        self.categoryEmojis = categoryEmojis.filter { $0.value.isSingleEmoji }
    }

    init(settings: BudgetSettings, userId: UUID, budgetId: UUID? = nil) {
        self.userId = userId
        self.budgetId = budgetId ?? userId
        monthlyBudget = settings.monthlyBudget
        currencyCode = settings.currencyCode
        appearance = settings.appearance.rawValue
        categoryBudgets = settings.categoryBudgets
        categoryEmojis = settings.categoryEmojis
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        budgetId = try container.decode(UUID.self, forKey: .budgetId)
        monthlyBudget = try container.decodeIfPresent(Double.self, forKey: .monthlyBudget) ?? 0
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? CurrencyOption.usd.code
        appearance = try container.decodeIfPresent(String.self, forKey: .appearance) ?? AppearanceOption.system.rawValue
        categoryBudgets = try container.decodeIfPresent([String: Double].self, forKey: .categoryBudgets) ?? [:]
        let decodedEmojis = try container.decodeIfPresent([String: String].self, forKey: .categoryEmojis) ?? [:]
        categoryEmojis = decodedEmojis.filter { $0.value.isSingleEmoji }
    }

    func makeSettings() -> BudgetSettings {
        BudgetSettings(
            monthlyBudget: monthlyBudget,
            currencyCode: currencyCode,
            appearance: AppearanceOption(rawValue: appearance) ?? .system,
            categoryBudgets: categoryBudgets,
            categoryEmojis: categoryEmojis
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
        initials = member.displayInitials
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

    func validateDates() throws {
        if let joinedDate,
           Self.dateFormatter.date(from: joinedDate) == nil {
            throw SupabaseBudgetSyncError.invalidCloudDate(joinedDate)
        }

        guard Self.dateFormatter.date(from: createdDate) != nil else {
            throw SupabaseBudgetSyncError.invalidCloudDate(createdDate)
        }
    }

    private static func string(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static func date(from string: String) -> Date {
        dateFormatter.date(from: string) ?? .now
    }

    private static let dateFormatter = ISO8601DateFormatter()
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

    func makeSummary() -> BudgetSummary {
        BudgetSummary(id: id, name: name)
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

    func makeMembership(name: String? = nil) -> BudgetMembership {
        BudgetMembership(
            budgetId: budgetId,
            userId: userId,
            role: role,
            status: status,
            name: name
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

    init(displayName: String, email: String, budgetId: UUID, invitedByUserId: UUID) {
        id = UUID()
        self.budgetId = budgetId
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
            createdAt: Self.dateFormatter.date(from: createdAt) ?? .now
        )
    }

    func validateCreatedAt() throws {
        guard Self.dateFormatter.date(from: createdAt) != nil else {
            throw SupabaseBudgetSyncError.invalidCloudDate(createdAt)
        }
    }

    private static let dateFormatter = ISO8601DateFormatter()
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

private struct CloudBudgetMemberRepairUpdateRow: Codable {
    let authUserId: UUID
    let inviteStatus: String

    enum CodingKeys: String, CodingKey {
        case authUserId = "auth_user_id"
        case inviteStatus = "invite_status"
    }

    init(authUserId: UUID) {
        self.authUserId = authUserId
        inviteStatus = InviteStatus.active.rawValue
    }
}

private struct CloudRecordIDRow: Codable {
    let id: UUID
    let userId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
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

    func validateDates() throws {
        guard Self.dateFormatter.date(from: date) != nil else {
            throw SupabaseBudgetSyncError.invalidCloudDate(date)
        }

        guard Self.dateFormatter.date(from: createdAt) != nil else {
            throw SupabaseBudgetSyncError.invalidCloudDate(createdAt)
        }
    }

    private static func string(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static func date(from string: String) -> Date {
        dateFormatter.date(from: string) ?? .now
    }

    private static let dateFormatter = ISO8601DateFormatter()
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
        date = Self.dateFormatter.string(from: settlement.date)
    }

    func apply(to settlement: Settlement, ownerUserId: String) {
        settlement.fromMemberId = fromMemberId
        settlement.toMemberId = toMemberId
        settlement.amount = amount
        settlement.date = Self.dateFormatter.date(from: date) ?? .now
        settlement.ownerUserId = ownerUserId
    }

    func makeSettlement(ownerUserId: String) -> Settlement {
        Settlement(
            id: id,
            fromMemberId: fromMemberId,
            toMemberId: toMemberId,
            amount: amount,
            date: Self.dateFormatter.date(from: date) ?? .now,
            ownerUserId: ownerUserId
        )
    }

    func validateDate() throws {
        guard Self.dateFormatter.date(from: date) != nil else {
            throw SupabaseBudgetSyncError.invalidCloudDate(date)
        }
    }

    private static let dateFormatter = ISO8601DateFormatter()
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
        userEmail: String? = nil,
        budgetScopeId: String? = nil
    ) async throws -> CloudBudgetSyncSummary {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId
        try members.forEach { try $0.validateForSync() }
        try transactions.forEach { try $0.validateForSync() }
        try settlements.forEach { try $0.validateForSync() }

        try await ensurePersonalBudget(userId: userId)
        if let userEmail {
            try await repairMemberProfileIfNeeded(
                userScopeId: userScopeId,
                userEmail: userEmail,
                budgetScopeId: budgetId.uuidString
            )
        }

        let existingSettings = try await fetchSettings(userScopeId: userScopeId, budgetScopeId: budgetId.uuidString)
        let settingsRow = CloudBudgetSettingsRow(settings: settings, userId: userId, budgetId: budgetId)
        let memberRows = Self.uniqueRows(
            members.map { CloudBudgetMemberRow(member: $0, userId: userId, budgetId: budgetId) },
            by: \.id
        )
        let signedInMemberIds = signedInMemberIds(for: userId, userEmail: userEmail, in: members)
        let cloudTransactionIDRows: [CloudRecordIDRow] = try await client
            .from("budget_transactions")
            .select("id,user_id")
            .eq("budget_id", value: budgetId)
            .execute()
            .value
        let cloudTransactionOwnersByID = Dictionary(cloudTransactionIDRows.map { ($0.id, $0.userId) }, uniquingKeysWith: { first, _ in first })
        let cloudSettlementIDRows: [CloudRecordIDRow] = try await client
            .from("budget_settlements")
            .select("id,user_id")
            .eq("budget_id", value: budgetId)
            .execute()
            .value
        let cloudSettlementOwnersByID = Dictionary(cloudSettlementIDRows.map { ($0.id, $0.userId) }, uniquingKeysWith: { first, _ in first })
        let transactionRows = Self.uniqueRows(transactions
            .filter {
                shouldBulkPush(
                    transaction: $0,
                    userId: userId,
                    signedInMemberIds: signedInMemberIds,
                    cloudOwnersByID: cloudTransactionOwnersByID
                )
            }
            .map { CloudTransactionRow(transaction: $0, userId: userId, budgetId: budgetId) },
            by: \.id
        )
        let pushedTransactionIDs = Set(transactionRows.map(\.id))
        let settlementRows = Self.uniqueRows(settlements
            .filter {
                shouldBulkPush(
                    settlement: $0,
                    userId: userId,
                    signedInMemberIds: signedInMemberIds,
                    cloudOwnersByID: cloudSettlementOwnersByID
                )
            }
            .map { CloudSettlementRow(settlement: $0, userId: userId, budgetId: budgetId) },
            by: \.id
        )
        let pushedSettlementIDs = Set(settlementRows.map(\.id))

        if existingSettings == nil || settings != .default {
            try await client
                .from("budget_settings")
                .upsert(settingsRow, onConflict: "budget_id")
                .execute()
        }

        if !memberRows.isEmpty && !Self.isDefaultSampleMembers(members) {
            try await client
                .from("budget_members")
                .upsert(memberRows, onConflict: "id")
                .execute()
        }

        if !transactionRows.isEmpty {
            try await client
                .from("budget_transactions")
                .upsert(transactionRows, onConflict: "id")
                .execute()
        }

        if !settlementRows.isEmpty {
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
        try pulledTransactions.forEach { try $0.validateDates() }
        try pulledSettlements.forEach { try $0.validateDate() }

        pruneLocalRowsMissingFromCloud(
            localTransactions: transactions,
            localSettlements: settlements,
            pulledTransactions: pulledTransactions,
            pulledSettlements: pulledSettlements,
            pushedTransactionIDs: pushedTransactionIDs,
            pushedSettlementIDs: pushedSettlementIDs,
            in: context
        )
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

        let row = CloudBudgetSettingsRow(settings: settings, userId: userId, budgetId: budgetId)
        try await client
            .from("budget_settings")
            .upsert(row, onConflict: "budget_id")
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

        try rows.forEach { try $0.validateDates() }
        return rows.map { $0.makeMember() }
    }

    func upsertMembers(_ members: [BudgetMember], userScopeId: String, budgetScopeId: String? = nil) async throws {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId

        try await ensurePersonalBudget(userId: userId)

        guard !members.isEmpty else { return }
        try members.forEach { try $0.validateForSync() }
        let rows = Self.uniqueRows(
            members.map { CloudBudgetMemberRow(member: $0, userId: userId, budgetId: budgetId) },
            by: \.id
        )
        try await client
            .from("budget_members")
            .upsert(rows, onConflict: "id")
            .execute()
    }

    func ensureSharedBudget(name: String, userScopeId: String) async throws -> BudgetSummary {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }

        try await ensurePersonalBudget(userId: userId)
        return try await ensureSharedBudget(ownerUserId: userId, name: name)
    }

    func fetchOwnedBudgets(userScopeId: String) async throws -> [BudgetSummary] {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }

        try await ensurePersonalBudget(userId: userId)
        let rows: [CloudBudgetRow] = try await client
            .from("budgets")
            .select()
            .eq("owner_user_id", value: userId)
            .execute()
            .value

        return rows
            .filter { $0.id != userId }
            .map { $0.makeSummary() }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func createInvite(displayName: String, email: String, userScopeId: String, budgetId: UUID) async throws {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }

        try await ensurePersonalBudget(userId: userId)
        try await validateBudgetOwner(userId: userId, budgetId: budgetId)
        let normalizedDisplayName = BudgetMember.normalizedDisplayName(displayName)
        guard !normalizedDisplayName.isEmpty,
              Self.normalizedEmail(email) != nil else {
            throw BudgetDataValidationError.emptyMemberName
        }

        let row = CloudBudgetInviteRow(
            displayName: normalizedDisplayName,
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            budgetId: budgetId,
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

        try rows.forEach { try $0.validateCreatedAt() }
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

        let budgetNames = try await accessibleBudgetNamesByID()
        return rows.map { row in
            row.makeMembership(name: budgetNames[row.budgetId])
        }
    }

    func repairMemberProfileIfNeeded(userScopeId: String, userEmail: String, budgetScopeId: String? = nil) async throws {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        guard let normalizedEmail = Self.normalizedEmail(userEmail) else {
            return
        }

        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId

        try await client
            .from("budget_members")
            .update(CloudBudgetMemberRepairUpdateRow(authUserId: userId))
            .eq("budget_id", value: budgetId)
            .eq("email", value: normalizedEmail)
            .execute()
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
        try transaction.validateForSync()

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
        try settlement.validateForSync()

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

    private func ensureSharedBudget(ownerUserId: UUID, name: String) async throws -> BudgetSummary {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = normalizedName.isEmpty ? "Shared Budget" : normalizedName
        let ownedBudgets: [CloudBudgetRow] = try await client
            .from("budgets")
            .select()
            .eq("owner_user_id", value: ownerUserId)
            .execute()
            .value

        if let existing = ownedBudgets.first(where: {
            $0.id != ownerUserId && $0.name.localizedCaseInsensitiveCompare(safeName) == .orderedSame
        }) {
            return existing.makeSummary()
        }

        let budget = CloudBudgetRow(
            id: UUID(),
            ownerUserId: ownerUserId,
            name: safeName
        )
        let membership = CloudBudgetMembershipRow(
            budgetId: budget.id,
            userId: ownerUserId,
            role: "owner",
            status: "active"
        )

        try await client
            .from("budgets")
            .insert(budget)
            .execute()

        try await client
            .from("budget_memberships")
            .upsert(membership, onConflict: "budget_id,user_id")
            .execute()

        return budget.makeSummary()
    }

    private func validateBudgetOwner(userId: UUID, budgetId: UUID) async throws {
        let rows: [CloudBudgetMembershipRow] = try await client
            .from("budget_memberships")
            .select()
            .eq("budget_id", value: budgetId)
            .eq("user_id", value: userId)
            .eq("role", value: "owner")
            .eq("status", value: "active")
            .execute()
            .value

        guard !rows.isEmpty else {
            throw SupabaseBudgetSyncError.notBudgetOwner
        }
    }

    private func accessibleBudgetNamesByID() async throws -> [UUID: String] {
        let rows: [CloudBudgetRow] = try await client
            .from("budgets")
            .select()
            .execute()
            .value

        return Dictionary(
            rows.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func isDefaultSampleMembers(_ members: [BudgetMember]) -> Bool {
        let memberIds = Set(members.map(\.id))
        let sampleIds = Set(BudgetSampleData.members.map(\.id))
        return memberIds == sampleIds
    }

    private func signedInMemberIds(for userId: UUID, userEmail: String?, in members: [BudgetMember]) -> Set<UUID> {
        let normalizedSignedInEmail = Self.normalizedEmail(userEmail)
        let matchingIds = members.compactMap { member -> UUID? in
            if member.id == userId || member.authUserId == userId {
                return member.id
            }
            if let normalizedSignedInEmail,
               Self.normalizedEmail(member.email) == normalizedSignedInEmail {
                return member.id
            }
            return nil
        }

        return Set(matchingIds.isEmpty ? [userId] : matchingIds)
    }

    private static func normalizedEmail(_ email: String?) -> String? {
        guard let email else { return nil }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func uniqueRows<Row>(_ rows: [Row], by keyPath: KeyPath<Row, UUID>) -> [Row] {
        var orderedIds: [UUID] = []
        var rowsById: [UUID: Row] = [:]

        for row in rows {
            let id = row[keyPath: keyPath]
            if rowsById[id] == nil {
                orderedIds.append(id)
            }
            rowsById[id] = row
        }

        return orderedIds.compactMap { rowsById[$0] }
    }

    private func shouldBulkPush(
        transaction: Transaction,
        userId: UUID,
        signedInMemberIds: Set<UUID>,
        cloudOwnersByID: [UUID: UUID]
    ) -> Bool {
        if let cloudOwnerId = cloudOwnersByID[transaction.id] {
            return cloudOwnerId == userId && signedInMemberIds.contains(transaction.createdByMemberId)
        }

        return signedInMemberIds.contains(transaction.createdByMemberId)
    }

    private func shouldBulkPush(
        settlement: Settlement,
        userId: UUID,
        signedInMemberIds: Set<UUID>,
        cloudOwnersByID: [UUID: UUID]
    ) -> Bool {
        let includesSignedInMember = signedInMemberIds.contains(settlement.fromMemberId)
            || signedInMemberIds.contains(settlement.toMemberId)

        if let cloudOwnerId = cloudOwnersByID[settlement.id] {
            return cloudOwnerId == userId && includesSignedInMember
        }

        return includesSignedInMember
    }

    private func merge(
        _ rows: [CloudTransactionRow],
        into context: ModelContext,
        existing transactions: [Transaction],
        ownerUserId: String
    ) {
        // Keep the first row per id and delete any duplicates, healing stores
        // that accumulated duplicate rows before ids were deduplicated on sync.
        var existingById: [UUID: Transaction] = [:]
        for transaction in transactions {
            if existingById[transaction.id] == nil {
                existingById[transaction.id] = transaction
            } else {
                context.delete(transaction)
            }
        }

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

    private func pruneLocalRowsMissingFromCloud(
        localTransactions: [Transaction],
        localSettlements: [Settlement],
        pulledTransactions: [CloudTransactionRow],
        pulledSettlements: [CloudSettlementRow],
        pushedTransactionIDs: Set<UUID>,
        pushedSettlementIDs: Set<UUID>,
        in context: ModelContext
    ) {
        let pulledTransactionIDs = Set(pulledTransactions.map(\.id))
        let pulledSettlementIDs = Set(pulledSettlements.map(\.id))

        for transaction in localTransactions
        where !pulledTransactionIDs.contains(transaction.id) && !pushedTransactionIDs.contains(transaction.id) {
            context.delete(transaction)
        }

        for settlement in localSettlements
        where !pulledSettlementIDs.contains(settlement.id) && !pushedSettlementIDs.contains(settlement.id) {
            context.delete(settlement)
        }
    }

    private func merge(
        _ rows: [CloudSettlementRow],
        into context: ModelContext,
        existing settlements: [Settlement],
        ownerUserId: String
    ) {
        // Keep the first row per id and delete any duplicates (see transaction
        // merge above).
        var existingById: [UUID: Settlement] = [:]
        for settlement in settlements {
            if existingById[settlement.id] == nil {
                existingById[settlement.id] = settlement
            } else {
                context.delete(settlement)
            }
        }

        for row in rows {
            if let settlement = existingById[row.id] {
                row.apply(to: settlement, ownerUserId: ownerUserId)
            } else {
                context.insert(row.makeSettlement(ownerUserId: ownerUserId))
            }
        }
    }
}

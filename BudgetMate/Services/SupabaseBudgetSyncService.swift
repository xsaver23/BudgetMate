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
    /// Cloud state observed during this sync, so callers can refresh app
    /// state without issuing extra fetches afterwards.
    var settings: BudgetSettings?
    var members: [BudgetMember] = []

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

private enum CloudISO8601DateCodec {
    private static let standardFormatter = ISO8601DateFormatter()
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String {
        standardFormatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        standardFormatter.date(from: string) ?? fractionalFormatter.date(from: string)
    }

    static func dateOrNow(from string: String) -> Date {
        date(from: string) ?? .now
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
            joinedDate: joinedDate.map(CloudISO8601DateCodec.dateOrNow(from:)),
            createdDate: CloudISO8601DateCodec.dateOrNow(from: createdDate)
        )
    }

    func validateDates() throws {
        if let joinedDate,
           CloudISO8601DateCodec.date(from: joinedDate) == nil {
            throw SupabaseBudgetSyncError.invalidCloudDate(joinedDate)
        }

        guard CloudISO8601DateCodec.date(from: createdDate) != nil else {
            throw SupabaseBudgetSyncError.invalidCloudDate(createdDate)
        }
    }

    private static func string(from date: Date) -> String {
        CloudISO8601DateCodec.string(from: date)
    }

    var usesDedicatedMemberId: Bool {
        guard let authUserId else { return false }
        return id != authUserId
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
        createdAt = CloudISO8601DateCodec.string(from: .now)
    }

    func makeInvite() -> BudgetInvite {
        BudgetInvite(
            id: id,
            budgetId: budgetId,
            invitedByUserId: invitedByUserId,
            displayName: displayName,
            email: email,
            status: status,
            createdAt: CloudISO8601DateCodec.dateOrNow(from: createdAt)
        )
    }

    func validateCreatedAt() throws {
        guard CloudISO8601DateCodec.date(from: createdAt) != nil else {
            throw SupabaseBudgetSyncError.invalidCloudDate(createdAt)
        }
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
        acceptedAt = CloudISO8601DateCodec.string(from: .now)
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
        joinedDate = CloudISO8601DateCodec.string(from: .now)
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

    init(
        transaction: Transaction,
        userId: UUID,
        budgetId: UUID? = nil,
        memberAliases: [UUID: UUID] = [:],
        validMemberIds: Set<UUID> = []
    ) {
        id = transaction.id
        self.userId = userId
        self.budgetId = budgetId ?? userId
        title = transaction.title
        amount = transaction.amount
        type = transaction.type.rawValue
        category = transaction.category.rawValue
        paymentMethod = transaction.paymentMethod?.rawValue
        createdByMemberId = Self.resolvedCreatedByMemberId(
            transaction.createdByMemberId,
            rowUserId: userId,
            aliases: memberAliases,
            validMemberIds: validMemberIds
        )
        date = Self.string(from: transaction.date)
        createdAt = Self.string(from: transaction.createdAt)
        recurrenceRule = transaction.recurrenceRule
        splits = transaction.splits.map {
            CloudTransactionSplitRow(
                id: $0.id,
                memberId: Self.resolvedMemberId($0.memberId, aliases: memberAliases),
                amount: $0.amount
            )
        }
    }

    func apply(
        to transaction: Transaction,
        ownerUserId: String,
        memberAliases: [UUID: UUID] = [:],
        validMemberIds: Set<UUID> = []
    ) {
        transaction.title = title
        transaction.amount = amount
        transaction.type = TransactionType(rawValue: type) ?? .expense
        transaction.category = TransactionCategory(rawValue: category)
        transaction.paymentMethod = paymentMethod.flatMap(PaymentMethod.init(rawValue:))
        transaction.createdByMemberId = Self.resolvedCreatedByMemberId(
            createdByMemberId,
            rowUserId: userId,
            aliases: memberAliases,
            validMemberIds: validMemberIds
        )
        transaction.date = CloudISO8601DateCodec.dateOrNow(from: date)
        transaction.createdAt = CloudISO8601DateCodec.dateOrNow(from: createdAt)
        transaction.recurrenceRule = recurrenceRule
        transaction.ownerUserId = ownerUserId
    }

    /// Whether applying this row to `transaction` would be a no-op. Used to
    /// skip SwiftData writes during merge so unchanged rows never dirty the
    /// store or invalidate the UI. Splits are compared separately.
    func matches(
        _ transaction: Transaction,
        ownerUserId: String,
        memberAliases: [UUID: UUID],
        validMemberIds: Set<UUID>
    ) -> Bool {
        transaction.title == title &&
        transaction.amount == amount &&
        transaction.type == (TransactionType(rawValue: type) ?? .expense) &&
        transaction.category == TransactionCategory(rawValue: category) &&
        transaction.paymentMethod == paymentMethod.flatMap(PaymentMethod.init(rawValue:)) &&
        transaction.createdByMemberId == Self.resolvedCreatedByMemberId(
            createdByMemberId,
            rowUserId: userId,
            aliases: memberAliases,
            validMemberIds: validMemberIds
        ) &&
        transaction.date == CloudISO8601DateCodec.dateOrNow(from: date) &&
        transaction.createdAt == CloudISO8601DateCodec.dateOrNow(from: createdAt) &&
        transaction.recurrenceRule == recurrenceRule &&
        transaction.ownerUserId == ownerUserId
    }

    /// Whether the local splits already equal this row's splits (after alias
    /// resolution), so the merge can leave the relationship untouched.
    func splitsMatch(_ transaction: Transaction, memberAliases: [UUID: UUID]) -> Bool {
        let desired = splits.filter { $0.amount > 0 }
        let existing = transaction.splits
        guard desired.count == existing.count else { return false }

        let existingById = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard existingById.count == existing.count else { return false }

        return desired.allSatisfy { row in
            guard let split = existingById[row.id] else { return false }
            return split.memberId == Self.resolvedMemberId(row.memberId, aliases: memberAliases)
                && split.amount == row.amount
        }
    }

    func makeTransaction(
        ownerUserId: String,
        memberAliases: [UUID: UUID] = [:],
        validMemberIds: Set<UUID> = []
    ) -> Transaction {
        Transaction(
            id: id,
            title: title,
            amount: amount,
            type: TransactionType(rawValue: type) ?? .expense,
            category: TransactionCategory(rawValue: category),
            paymentMethod: paymentMethod.flatMap(PaymentMethod.init(rawValue:)),
            createdByMemberId: Self.resolvedCreatedByMemberId(
                createdByMemberId,
                rowUserId: userId,
                aliases: memberAliases,
                validMemberIds: validMemberIds
            ),
            date: CloudISO8601DateCodec.dateOrNow(from: date),
            createdAt: CloudISO8601DateCodec.dateOrNow(from: createdAt),
            recurrenceRule: recurrenceRule,
            ownerUserId: ownerUserId
        )
    }

    func validateDates() throws {
        guard CloudISO8601DateCodec.date(from: date) != nil else {
            throw SupabaseBudgetSyncError.invalidCloudDate(date)
        }

        guard CloudISO8601DateCodec.date(from: createdAt) != nil else {
            throw SupabaseBudgetSyncError.invalidCloudDate(createdAt)
        }
    }

    private static func string(from date: Date) -> String {
        CloudISO8601DateCodec.string(from: date)
    }

    static func resolvedMemberId(_ memberId: UUID, aliases: [UUID: UUID]) -> UUID {
        aliases[memberId] ?? memberId
    }

    static func resolvedCreatedByMemberId(
        _ memberId: UUID,
        rowUserId: UUID,
        aliases: [UUID: UUID],
        validMemberIds: Set<UUID> = []
    ) -> UUID {
        let mappedMemberId = resolvedMemberId(memberId, aliases: aliases)
        guard !validMemberIds.isEmpty,
              !validMemberIds.contains(mappedMemberId) else {
            return mappedMemberId
        }

        let resolvedRowUserId = resolvedMemberId(rowUserId, aliases: aliases)
        return validMemberIds.contains(resolvedRowUserId) ? resolvedRowUserId : mappedMemberId
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

    init(settlement: Settlement, userId: UUID, budgetId: UUID? = nil, memberAliases: [UUID: UUID] = [:]) {
        id = settlement.id
        self.userId = userId
        self.budgetId = budgetId ?? userId
        fromMemberId = CloudTransactionRow.resolvedMemberId(settlement.fromMemberId, aliases: memberAliases)
        toMemberId = CloudTransactionRow.resolvedMemberId(settlement.toMemberId, aliases: memberAliases)
        amount = settlement.amount
        date = CloudISO8601DateCodec.string(from: settlement.date)
    }

    func apply(to settlement: Settlement, ownerUserId: String, memberAliases: [UUID: UUID] = [:]) {
        settlement.fromMemberId = CloudTransactionRow.resolvedMemberId(fromMemberId, aliases: memberAliases)
        settlement.toMemberId = CloudTransactionRow.resolvedMemberId(toMemberId, aliases: memberAliases)
        settlement.amount = amount
        settlement.date = CloudISO8601DateCodec.dateOrNow(from: date)
        settlement.ownerUserId = ownerUserId
    }

    /// Whether applying this row to `settlement` would be a no-op (see
    /// `CloudTransactionRow.matches`).
    func matches(_ settlement: Settlement, ownerUserId: String, memberAliases: [UUID: UUID]) -> Bool {
        settlement.fromMemberId == CloudTransactionRow.resolvedMemberId(fromMemberId, aliases: memberAliases) &&
        settlement.toMemberId == CloudTransactionRow.resolvedMemberId(toMemberId, aliases: memberAliases) &&
        settlement.amount == amount &&
        settlement.date == CloudISO8601DateCodec.dateOrNow(from: date) &&
        settlement.ownerUserId == ownerUserId
    }

    func makeSettlement(ownerUserId: String, memberAliases: [UUID: UUID] = [:]) -> Settlement {
        Settlement(
            id: id,
            fromMemberId: CloudTransactionRow.resolvedMemberId(fromMemberId, aliases: memberAliases),
            toMemberId: CloudTransactionRow.resolvedMemberId(toMemberId, aliases: memberAliases),
            amount: amount,
            date: CloudISO8601DateCodec.dateOrNow(from: date),
            ownerUserId: ownerUserId
        )
    }

    func validateDate() throws {
        guard CloudISO8601DateCodec.date(from: date) != nil else {
            throw SupabaseBudgetSyncError.invalidCloudDate(date)
        }
    }
}

// Main-actor isolated: the service reads and mutates SwiftData models from
// the app's main ModelContext, which is not thread-safe.
@MainActor
final class SupabaseBudgetSyncService {
    private let client: SupabaseClient
    /// Users whose personal budget row was already ensured this launch.
    private var ensuredPersonalBudgetUserIds: Set<UUID> = []
    /// Scope keys whose member profile repair already ran this launch.
    private var repairedProfileScopeKeys: Set<String> = []

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
        let normalizedMembers = BudgetMember.deduplicatedForBudget(members)
        try normalizedMembers.forEach { try $0.validateForSync() }
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
        let candidateMemberRows = Self.uniqueRows(
            normalizedMembers.map { CloudBudgetMemberRow(member: $0, userId: userId, budgetId: budgetId) },
            by: \.id
        )
        let existingMemberRows = try await budgetMemberRows(budgetId: budgetId)
        let memberAliases = self.memberAliases(
            candidateRows: candidateMemberRows,
            existingRows: existingMemberRows,
            userId: userId,
            userEmail: userEmail
        )
        let validMemberIds = Self.validMemberIds(
            candidateRows: candidateMemberRows,
            existingRows: existingMemberRows,
            aliases: memberAliases
        )
        let signedInMemberIds = Self.memberIdsIncludingAliases(
            signedInMemberIds(for: userId, userEmail: userEmail, in: normalizedMembers),
            aliases: memberAliases
        )
        let memberRows = try await writableMemberRows(
            candidateMemberRows,
            existingRows: existingMemberRows,
            memberAliases: memberAliases,
            userId: userId,
            budgetId: budgetId,
            signedInMemberIds: signedInMemberIds
        )
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
                    cloudOwnersByID: cloudTransactionOwnersByID,
                    memberAliases: memberAliases,
                    validMemberIds: validMemberIds
                )
            }
            .map {
                CloudTransactionRow(
                    transaction: $0,
                    userId: userId,
                    budgetId: budgetId,
                    memberAliases: memberAliases,
                    validMemberIds: validMemberIds
                )
            },
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
            .map { CloudSettlementRow(settlement: $0, userId: userId, budgetId: budgetId, memberAliases: memberAliases) },
            by: \.id
        )
        let pushedSettlementIDs = Set(settlementRows.map(\.id))

        let didPushSettings = existingSettings == nil || settings != .default
        if didPushSettings {
            try await client
                .from("budget_settings")
                .upsert(settingsRow, onConflict: "budget_id")
                .execute()
        }

        if !memberRows.isEmpty && !Self.isDefaultSampleMembers(normalizedMembers) {
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
        merge(
            pulledTransactions,
            into: context,
            existing: transactions,
            ownerUserId: budgetId.uuidString,
            memberAliases: memberAliases,
            validMemberIds: validMemberIds
        )
        merge(pulledSettlements, into: context, existing: settlements, ownerUserId: budgetId.uuidString, memberAliases: memberAliases)
        let pulledMembers = try await fetchMembers(userScopeId: userScopeId, budgetScopeId: budgetId.uuidString)

        return CloudBudgetSyncSummary(
            syncedSettings: true,
            pushedMembers: memberRows.count,
            pulledMembers: pulledMembers.count,
            pushedTransactions: transactionRows.count,
            pulledTransactions: pulledTransactions.count,
            pushedSettlements: settlementRows.count,
            pulledSettlements: pulledSettlements.count,
            settings: didPushSettings ? settings : existingSettings,
            members: pulledMembers
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

        let rows = try await budgetMemberRows(budgetId: budgetId)

        try rows.forEach { try $0.validateDates() }
        let memberships: [CloudBudgetMembershipRow] = try await client
            .from("budget_memberships")
            .select()
            .eq("budget_id", value: budgetId)
            .eq("status", value: "active")
            .execute()
            .value
        let rolesByUserId = Dictionary(
            memberships.map { ($0.userId, BudgetMemberRole(rawValue: $0.role) ?? .member) },
            uniquingKeysWith: { first, _ in first }
        )
        let members = rows.map { row in
            memberWithMembershipRole(row.makeMember(), rolesByUserId: rolesByUserId)
        }
        return BudgetMember.deduplicatedForBudget(members)
    }

    func upsertMembers(_ members: [BudgetMember], userScopeId: String, budgetScopeId: String? = nil) async throws {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId

        try await ensurePersonalBudget(userId: userId)

        guard !members.isEmpty else { return }
        let normalizedMembers = BudgetMember.deduplicatedForBudget(members)
        try normalizedMembers.forEach { try $0.validateForSync() }
        let candidateRows = Self.uniqueRows(
            normalizedMembers.map { CloudBudgetMemberRow(member: $0, userId: userId, budgetId: budgetId) },
            by: \.id
        )
        let existingRows = try await budgetMemberRows(budgetId: budgetId)
        let memberAliases = self.memberAliases(
            candidateRows: candidateRows,
            existingRows: existingRows,
            userId: userId,
            userEmail: nil
        )
        let rows = try await writableMemberRows(
            candidateRows,
            existingRows: existingRows,
            memberAliases: memberAliases,
            userId: userId,
            budgetId: budgetId,
            signedInMemberIds: Self.memberIdsIncludingAliases(
                signedInMemberIds(for: userId, userEmail: nil, in: normalizedMembers),
                aliases: memberAliases
            )
        )
        guard !rows.isEmpty else { return }
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
        let scopeKey = "\(userId.uuidString)|\(budgetId.uuidString)|\(normalizedEmail)"
        guard !repairedProfileScopeKeys.contains(scopeKey) else { return }

        try await client
            .from("budget_members")
            .update(CloudBudgetMemberRepairUpdateRow(authUserId: userId))
            .eq("budget_id", value: budgetId)
            .eq("email", value: normalizedEmail)
            .execute()

        repairedProfileScopeKeys.insert(scopeKey)
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

        let existingRows = try await budgetMemberRows(budgetId: budgetId)
        let memberAliases = self.memberAliases(
            candidateRows: [],
            existingRows: existingRows,
            userId: userId,
            userEmail: nil
        )
        let validMemberIds = Self.validMemberIds(
            candidateRows: [],
            existingRows: existingRows,
            aliases: memberAliases
        )
        let row = CloudTransactionRow(
            transaction: transaction,
            userId: userId,
            budgetId: budgetId,
            memberAliases: memberAliases,
            validMemberIds: validMemberIds
        )
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

        let memberAliases = self.memberAliases(
            candidateRows: [],
            existingRows: try await budgetMemberRows(budgetId: budgetId),
            userId: userId,
            userEmail: nil
        )
        let row = CloudSettlementRow(
            settlement: settlement,
            userId: userId,
            budgetId: budgetId,
            memberAliases: memberAliases
        )
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
        guard !ensuredPersonalBudgetUserIds.contains(userId) else { return }

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

        ensuredPersonalBudgetUserIds.insert(userId)
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

    private func budgetMemberRows(budgetId: UUID) async throws -> [CloudBudgetMemberRow] {
        try await client
            .from("budget_members")
            .select()
            .eq("budget_id", value: budgetId)
            .execute()
            .value
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

        return Set(matchingIds + [userId])
    }

    private func memberAliases(
        candidateRows: [CloudBudgetMemberRow],
        existingRows: [CloudBudgetMemberRow],
        userId: UUID,
        userEmail: String?
    ) -> [UUID: UUID] {
        let rows = existingRows + candidateRows
        guard !rows.isEmpty else { return [:] }

        var aliases: [UUID: UUID] = [:]
        for row in rows {
            let matches = rows.filter { Self.representsSameCloudMember($0, row) }
            guard let canonical = Self.preferredCloudMemberRow(matches),
                  canonical.id != row.id else {
                if let authUserId = row.authUserId,
                   authUserId != row.id {
                    aliases[authUserId] = row.id
                }
                continue
            }
            aliases[row.id] = canonical.id
            if let authUserId = row.authUserId,
               authUserId != canonical.id {
                aliases[authUserId] = canonical.id
            }
        }

        let signedInMatches = rows.filter {
            Self.isSignedInCloudMember($0, userId: userId, userEmail: userEmail)
        }
        if let signedInCanonical = Self.preferredCloudMemberRow(signedInMatches),
           signedInCanonical.id != userId {
            aliases[userId] = signedInCanonical.id
        }

        return aliases.filter { $0.key != $0.value }
    }

    private static func validMemberIds(
        candidateRows: [CloudBudgetMemberRow],
        existingRows: [CloudBudgetMemberRow],
        aliases: [UUID: UUID]
    ) -> Set<UUID> {
        var ids = Set((candidateRows + existingRows).map(\.id))
        ids.formUnion(aliases.values)
        return ids
    }

    private static func memberIdsIncludingAliases(_ ids: Set<UUID>, aliases: [UUID: UUID]) -> Set<UUID> {
        var expanded = ids
        for id in ids {
            if let canonicalId = aliases[id] {
                expanded.insert(canonicalId)
            }
        }

        for (sourceId, canonicalId) in aliases where expanded.contains(canonicalId) {
            expanded.insert(sourceId)
        }

        return expanded
    }

    private func writableMemberRows(
        _ rows: [CloudBudgetMemberRow],
        existingRows: [CloudBudgetMemberRow],
        memberAliases: [UUID: UUID],
        userId: UUID,
        budgetId: UUID,
        signedInMemberIds: Set<UUID>
    ) async throws -> [CloudBudgetMemberRow] {
        guard !rows.isEmpty else { return [] }

        let cloudMemberOwnersByID = Dictionary(existingRows.map { ($0.id, $0.userId) }, uniquingKeysWith: { first, _ in first })
        let canCreateMemberRows = try await isActiveBudgetOwner(userId: userId, budgetId: budgetId)

        return rows.filter { row in
            if let canonicalId = memberAliases[row.id],
               canonicalId != row.id {
                return false
            }

            if let existingOwnerId = cloudMemberOwnersByID[row.id] {
                return existingOwnerId == userId || row.authUserId == userId || signedInMemberIds.contains(row.id)
            }

            return canCreateMemberRows || row.authUserId == userId || signedInMemberIds.contains(row.id)
        }
    }

    private static func representsSameCloudMember(_ lhs: CloudBudgetMemberRow, _ rhs: CloudBudgetMemberRow) -> Bool {
        if lhs.id == rhs.id {
            return true
        }

        if let lhsAuthUserId = lhs.authUserId,
           lhsAuthUserId == rhs.authUserId || lhsAuthUserId == rhs.id {
            return true
        }

        if let rhsAuthUserId = rhs.authUserId,
           rhsAuthUserId == lhs.id {
            return true
        }

        guard let lhsEmail = normalizedEmail(lhs.email),
              let rhsEmail = normalizedEmail(rhs.email) else {
            return false
        }

        return lhsEmail == rhsEmail
    }

    private static func isSignedInCloudMember(_ row: CloudBudgetMemberRow, userId: UUID, userEmail: String?) -> Bool {
        if row.id == userId || row.authUserId == userId {
            return true
        }

        guard let signedInEmail = normalizedEmail(userEmail) else {
            return false
        }

        return normalizedEmail(row.email) == signedInEmail
    }

    private static func preferredCloudMemberRow(_ rows: [CloudBudgetMemberRow]) -> CloudBudgetMemberRow? {
        rows.max { lhs, rhs in
            let lhsScore = cloudMemberCanonicalScore(lhs)
            let rhsScore = cloudMemberCanonicalScore(rhs)

            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }

            let lhsDate = CloudISO8601DateCodec.date(from: lhs.createdDate) ?? .distantFuture
            let rhsDate = CloudISO8601DateCodec.date(from: rhs.createdDate) ?? .distantFuture
            return lhsDate > rhsDate
        }
    }

    private static func cloudMemberCanonicalScore(_ row: CloudBudgetMemberRow) -> Int {
        var score = 0
        if row.inviteStatus == InviteStatus.active.rawValue { score += 100 }
        if row.authUserId != nil { score += 80 }
        if row.usesDedicatedMemberId { score += 60 }
        if row.joinedDate != nil { score += 20 }
        if normalizedEmail(row.email) != nil { score += 10 }
        if row.role == BudgetMemberRole.owner.rawValue { score += 5 }
        return score
    }

    private func isActiveBudgetOwner(userId: UUID, budgetId: UUID) async throws -> Bool {
        let rows: [CloudBudgetMembershipRow] = try await client
            .from("budget_memberships")
            .select()
            .eq("budget_id", value: budgetId)
            .eq("user_id", value: userId)
            .eq("role", value: "owner")
            .eq("status", value: "active")
            .execute()
            .value

        return !rows.isEmpty
    }

    private func memberWithMembershipRole(
        _ member: BudgetMember,
        rolesByUserId: [UUID: BudgetMemberRole]
    ) -> BudgetMember {
        let membershipRole = member.authUserId.flatMap { rolesByUserId[$0] }
            ?? rolesByUserId[member.id]
            ?? member.role

        guard membershipRole != member.role else {
            return member
        }

        return BudgetMember(
            id: member.id,
            displayName: member.displayName,
            email: member.email,
            initials: member.displayInitials,
            color: member.color,
            authUserId: member.authUserId,
            role: membershipRole,
            inviteStatus: member.inviteStatus,
            joinedDate: member.joinedDate,
            createdDate: member.createdDate
        )
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
        cloudOwnersByID: [UUID: UUID],
        memberAliases: [UUID: UUID],
        validMemberIds: Set<UUID>
    ) -> Bool {
        let resolvedCreatedByMemberId = CloudTransactionRow.resolvedCreatedByMemberId(
            transaction.createdByMemberId,
            rowUserId: userId,
            aliases: memberAliases,
            validMemberIds: validMemberIds
        )
        if let cloudOwnerId = cloudOwnersByID[transaction.id] {
            return cloudOwnerId == userId && signedInMemberIds.contains(resolvedCreatedByMemberId)
        }

        // Rows not in the cloud yet: push anything created on this device,
        // even when attributed to another member ("Paid By" a partner while
        // offline), so the prune pass never discards it.
        return signedInMemberIds.contains(resolvedCreatedByMemberId) || transaction.needsSync
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

        // See the transaction variant: locally created rows always push.
        return includesSignedInMember || settlement.needsSync
    }

    private func merge(
        _ rows: [CloudTransactionRow],
        into context: ModelContext,
        existing transactions: [Transaction],
        ownerUserId: String,
        memberAliases: [UUID: UUID] = [:],
        validMemberIds: Set<UUID> = []
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
            // Only touch the store when the cloud row actually differs from
            // the local one. Unconditional writes here used to dirty every
            // transaction (and delete/reinsert every split) on each sync
            // cycle, forcing a full UI re-render every 20 seconds.
            if let transaction = existingById[row.id] {
                let fieldsMatch = row.matches(
                    transaction,
                    ownerUserId: ownerUserId,
                    memberAliases: memberAliases,
                    validMemberIds: validMemberIds
                )
                let splitsMatch = row.splitsMatch(transaction, memberAliases: memberAliases)

                if !fieldsMatch {
                    row.apply(
                        to: transaction,
                        ownerUserId: ownerUserId,
                        memberAliases: memberAliases,
                        validMemberIds: validMemberIds
                    )
                }

                if !splitsMatch {
                    rebuildSplits(for: transaction, from: row, memberAliases: memberAliases, in: context)
                }

                if transaction.needsSync {
                    transaction.needsSync = false
                }
            } else {
                let transaction = row.makeTransaction(
                    ownerUserId: ownerUserId,
                    memberAliases: memberAliases,
                    validMemberIds: validMemberIds
                )
                context.insert(transaction)
                rebuildSplits(for: transaction, from: row, memberAliases: memberAliases, in: context)
            }
        }
    }

    private func rebuildSplits(
        for transaction: Transaction,
        from row: CloudTransactionRow,
        memberAliases: [UUID: UUID],
        in context: ModelContext
    ) {
        for split in Array(transaction.splits) {
            context.delete(split)
        }

        for splitRow in row.splits where splitRow.amount > 0 {
            context.insert(
                TransactionSplit(
                    id: splitRow.id,
                    memberId: CloudTransactionRow.resolvedMemberId(splitRow.memberId, aliases: memberAliases),
                    amount: splitRow.amount,
                    transaction: transaction
                )
            )
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

        // Rows flagged needsSync were created or edited locally and have not
        // been confirmed in the cloud yet (e.g. offline work) - never treat
        // their absence from the cloud as a remote delete.
        for transaction in localTransactions
        where !pulledTransactionIDs.contains(transaction.id)
            && !pushedTransactionIDs.contains(transaction.id)
            && !transaction.needsSync {
            context.delete(transaction)
        }

        for settlement in localSettlements
        where !pulledSettlementIDs.contains(settlement.id)
            && !pushedSettlementIDs.contains(settlement.id)
            && !settlement.needsSync {
            context.delete(settlement)
        }
    }

    private func merge(
        _ rows: [CloudSettlementRow],
        into context: ModelContext,
        existing settlements: [Settlement],
        ownerUserId: String,
        memberAliases: [UUID: UUID] = [:]
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
                if !row.matches(settlement, ownerUserId: ownerUserId, memberAliases: memberAliases) {
                    row.apply(to: settlement, ownerUserId: ownerUserId, memberAliases: memberAliases)
                }
                if settlement.needsSync {
                    settlement.needsSync = false
                }
            } else {
                context.insert(row.makeSettlement(ownerUserId: ownerUserId, memberAliases: memberAliases))
            }
        }
    }
}

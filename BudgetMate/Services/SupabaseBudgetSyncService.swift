import Foundation
import Supabase
import SwiftData

struct CloudBudgetSyncSummary {
    let syncedSettings: Bool
    let pushedSettings: Bool
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

struct CloudCurrencyBaselineSnapshot {
    let settings: BudgetSettings?
    let hasTransactionOrSplit: Bool
    let hasSettlement: Bool

    var hasFinancialHistory: Bool {
        settings?.categoryBudgets.isEmpty == false ||
            hasTransactionOrSplit ||
            hasSettlement
    }
}

private struct CloudRecordIdentityRow: Decodable {
    let id: UUID
}

/// PR02C ships the expanded DTO contract before any client depends on it.
/// PR02D may replace this constant with the approved rollout mechanism only
/// after the server migration has been deployed and verified.
enum MoneyServerBridgeRollout {
    static let isEnabled = false
}

struct SharedDataSafetyMutationResult: Decodable, Equatable {
    let recordId: UUID
    let rowVersion: Int64
    let deleted: Bool
    let replayed: Bool

    enum CodingKeys: String, CodingKey {
        case recordId = "record_id"
        case rowVersion = "row_version"
        case deleted
        case replayed
    }
}

private struct SharedDataSafetyMutationParameters<Payload: Encodable>: Encodable {
    let budgetId: UUID
    let recordId: UUID
    let expectedRowVersion: Int64
    let clientMutationId: UUID
    let operation: String
    let payload: Payload

    enum CodingKeys: String, CodingKey {
        case budgetId = "p_budget_id"
        case recordId = "p_record_id"
        case expectedRowVersion = "p_expected_row_version"
        case clientMutationId = "p_client_mutation_id"
        case operation = "p_operation"
        case payload = "p_payload"
    }
}

private struct EmptySharedDataSafetyPayload: Encodable {}

private struct TransactionMutationPayload: Encodable {
    let title: String
    let amount: Double
    let amountMinorUnits: Int64?
    let currencyCode: String?
    let type: String
    let category: String
    let paymentMethod: String?
    let createdByMemberId: UUID
    let date: String
    let occurredOn: String
    let createdAt: String
    let recurrenceRule: String?
    let splits: [CloudTransactionSplitRow]
    let splitsMinorUnits: [CloudTransactionSplitMoneyRow]?

    enum CodingKeys: String, CodingKey {
        case title, amount, type, category, splits
        case amountMinorUnits = "amount_minor_units"
        case currencyCode = "currency_code"
        case paymentMethod = "payment_method"
        case createdByMemberId = "created_by_member_id"
        case date
        case occurredOn = "occurred_on"
        case createdAt = "created_at"
        case recurrenceRule = "recurrence_rule"
        case splitsMinorUnits = "splits_minor_units"
    }

    init(transaction: Transaction, memberAliases: [UUID: UUID] = [:]) {
        title = transaction.title
        amount = transaction.amount
        amountMinorUnits = transaction.amountMinorUnits
        currencyCode = transaction.currencyCode
        type = transaction.type.rawValue
        category = transaction.category.rawValue
        paymentMethod = transaction.paymentMethod?.rawValue
        createdByMemberId = CloudTransactionRow.resolvedMemberId(transaction.createdByMemberId, aliases: memberAliases)
        date = CloudISO8601DateCodec.string(from: transaction.date)
        occurredOn = CloudISO8601DateCodec.localDateString(from: transaction.date)
        createdAt = CloudISO8601DateCodec.string(from: transaction.createdAt)
        recurrenceRule = transaction.recurrenceRule
        splits = transaction.splits.map {
            CloudTransactionSplitRow(
                id: $0.id,
                memberId: CloudTransactionRow.resolvedMemberId($0.memberId, aliases: memberAliases),
                amount: $0.amount
            )
        }
        let exactSplits = transaction.splits.compactMap { split -> CloudTransactionSplitMoneyRow? in
            guard let amountMinorUnits = split.amountMinorUnits,
                  let currencyCode = split.currencyCode else { return nil }
            return CloudTransactionSplitMoneyRow(
                id: split.id,
                memberId: CloudTransactionRow.resolvedMemberId(split.memberId, aliases: memberAliases),
                amountMinorUnits: amountMinorUnits,
                currencyCode: currencyCode
            )
        }
        splitsMinorUnits = exactSplits.count == transaction.splits.count ? exactSplits : nil
    }
}

private struct SettlementMutationPayload: Encodable {
    let fromMemberId: UUID
    let toMemberId: UUID
    let amount: Double
    let amountMinorUnits: Int64?
    let currencyCode: String?
    let date: String
    let occurredOn: String

    enum CodingKeys: String, CodingKey {
        case amount, date
        case fromMemberId = "from_member_id"
        case toMemberId = "to_member_id"
        case amountMinorUnits = "amount_minor_units"
        case currencyCode = "currency_code"
        case occurredOn = "occurred_on"
    }

    init(settlement: Settlement, memberAliases: [UUID: UUID] = [:]) {
        fromMemberId = CloudTransactionRow.resolvedMemberId(settlement.fromMemberId, aliases: memberAliases)
        toMemberId = CloudTransactionRow.resolvedMemberId(settlement.toMemberId, aliases: memberAliases)
        amount = settlement.amount
        amountMinorUnits = settlement.amountMinorUnits
        currencyCode = settlement.currencyCode
        date = CloudISO8601DateCodec.string(from: settlement.date)
        occurredOn = CloudISO8601DateCodec.localDateString(from: settlement.date)
    }
}

enum SupabaseBudgetSyncError: LocalizedError {
    case missingUser
    case notBudgetOwner
    case invalidCloudDate(String)
    case invalidCloudMoneyContract
    case sharedDataSafetyDisabled
    case sharedDataMutationConflict
    case idempotencyMismatch
    case remoteDeleted
    case mutationRecordNotFound
    case invalidMemberReference
    case memberReferenceForbidden
    case unsafePendingDeletion

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return "Sign in again before syncing."
        case .notBudgetOwner:
            return "Only the household owner can invite members."
        case .invalidCloudDate(let value):
            return "Cloud data has an invalid date: \(value)."
        case .invalidCloudMoneyContract:
            return "Cloud data has inconsistent exact-money fields."
        case .sharedDataSafetyDisabled:
            return "Shared-data writes are temporarily disabled while household safety is being enabled."
        case .sharedDataMutationConflict:
            return "This shared record changed on another device. Refresh before trying again."
        case .idempotencyMismatch:
            return "This cloud retry did not match the original change and was not applied. Refresh before trying again."
        case .remoteDeleted:
            return "This record was already deleted on another device. It was not recreated."
        case .mutationRecordNotFound:
            return "This shared record no longer exists. Refresh before trying again."
        case .invalidMemberReference:
            return "This change refers to an invalid household member. Refresh and try again."
        case .memberReferenceForbidden:
            return "This change refers to a member outside the active household. Refresh and try again."
        case .unsafePendingDeletion:
            return "A pending deletion is missing conflict metadata and was not replayed."
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

    static func representsSameInstant(_ date: Date, as string: String) -> Bool {
        guard let decodedDate = self.date(from: string) else { return false }
        // ISO8601DateFormatter without fractional seconds truncates subsecond
        // precision when iOS creates a cloud payload.
        return abs(date.timeIntervalSince(decodedDate)) < 1
    }

    static func localDateString(from date: Date) -> String {
        localDateFormatter.string(from: date)
    }

    static func localDate(from string: String) -> Date? {
        guard let parsed = localDateFormatter.date(from: string) else { return nil }
        // Noon is stable across daylight-saving transitions and still renders
        // as the selected calendar day in every local DatePicker.
        return Calendar.autoupdatingCurrent.date(bySettingHour: 12, minute: 0, second: 0, of: parsed)
    }

    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private enum CloudMoneyContract {
    static func validatedExactMoney(
        legacyAmount: Double,
        minorUnits: Int64?,
        currencyCode: String?,
        rolloutEnabled: Bool
    ) throws -> Money? {
        guard rolloutEnabled else { return nil }
        guard minorUnits != nil || currencyCode != nil else { return nil }
        guard let minorUnits, let currencyCode,
              let metadata = try? CurrencyMetadata(code: currencyCode) else {
            throw SupabaseBudgetSyncError.invalidCloudMoneyContract
        }
        guard case .success(let expectedMinorUnits) =
                LegacyDoubleMoneyConverter.convert(legacyAmount, metadata: metadata),
              expectedMinorUnits == minorUnits,
              let money = try? Money(
                minorUnits: minorUnits,
                currencyCode: metadata.code
              ) else {
            throw SupabaseBudgetSyncError.invalidCloudMoneyContract
        }
        return money
    }
}

struct CloudBudgetSettingsRow: Codable {
    let userId: UUID
    let budgetId: UUID
    let monthlyBudget: Double
    let currencyCode: String
    let appearance: String
    let categoryBudgets: [String: Double]
    let categoryBudgetsMinorUnits: [String: Int64]?
    let categoryVisibility: [String: BudgetCategoryVisibility]?
    let categoryEmojis: [String: String]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case budgetId = "budget_id"
        case monthlyBudget = "monthly_budget"
        case currencyCode = "currency_code"
        case appearance
        case categoryBudgets = "category_budgets"
        case categoryBudgetsMinorUnits = "category_budgets_minor_units"
        case categoryVisibility = "category_visibility"
        case categoryEmojis = "category_emojis"
    }

    init(
        userId: UUID,
        budgetId: UUID,
        monthlyBudget: Double,
        currencyCode: String,
        appearance: String,
        categoryBudgets: [String: Double],
        categoryBudgetsMinorUnits: [String: Int64]? = nil,
        categoryVisibility: [String: BudgetCategoryVisibility]? = nil,
        categoryEmojis: [String: String] = [:]
    ) {
        self.userId = userId
        self.budgetId = budgetId
        self.monthlyBudget = monthlyBudget
        self.currencyCode = currencyCode
        self.appearance = appearance
        self.categoryBudgets = categoryBudgets
        self.categoryBudgetsMinorUnits = categoryBudgetsMinorUnits
        self.categoryVisibility = categoryVisibility
        self.categoryEmojis = categoryEmojis.filter { $0.value.isSingleEmoji }
    }

    init(
        settings: BudgetSettings,
        userId: UUID,
        budgetId: UUID? = nil,
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) {
        self.userId = userId
        self.budgetId = budgetId ?? userId
        monthlyBudget = settings.monthlyBudget
        currencyCode = settings.currencyCode
        appearance = settings.appearance.rawValue
        categoryBudgets = settings.categoryBudgets
        categoryBudgetsMinorUnits = rolloutEnabled
            ? settings.categoryBudgetsMinorUnits
            : nil
        categoryVisibility = rolloutEnabled
            ? settings.categoryVisibility
            : nil
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
        categoryBudgetsMinorUnits = try container.decodeIfPresent(
            [String: Int64].self,
            forKey: .categoryBudgetsMinorUnits
        )
        categoryVisibility = try container.decodeIfPresent(
            [String: BudgetCategoryVisibility].self,
            forKey: .categoryVisibility
        )
        let decodedEmojis = try container.decodeIfPresent([String: String].self, forKey: .categoryEmojis) ?? [:]
        categoryEmojis = decodedEmojis.filter { $0.value.isSingleEmoji }
    }

    func makeSettings(
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) -> BudgetSettings {
        BudgetSettings(
            monthlyBudget: monthlyBudget,
            currencyCode: currencyCode,
            appearance: AppearanceOption(rawValue: appearance) ?? .system,
            categoryBudgets: categoryBudgets,
            categoryBudgetsMinorUnits: rolloutEnabled
                ? (categoryBudgetsMinorUnits ?? [:])
                : [:],
            categoryVisibility: rolloutEnabled
                ? (categoryVisibility ?? [:])
                : [:],
            categoryEmojis: categoryEmojis
        )
    }

    func validateMoneyContract(
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) throws {
        guard rolloutEnabled else { return }
        guard categoryBudgetsMinorUnits != nil || categoryVisibility != nil else {
            return
        }
        guard let categoryBudgetsMinorUnits, let categoryVisibility else {
            throw SupabaseBudgetSyncError.invalidCloudMoneyContract
        }
        let candidate = BudgetSettings(
            monthlyBudget: monthlyBudget,
            currencyCode: currencyCode,
            appearance: AppearanceOption(rawValue: appearance) ?? .system,
            categoryBudgets: categoryBudgets,
            categoryBudgetsMinorUnits: categoryBudgetsMinorUnits,
            categoryVisibility: categoryVisibility,
            categoryEmojis: categoryEmojis
        )
        let migration = LegacyBudgetSettingsMigrator.migrate(
            candidate,
            currencySource: StaticVerifiedCurrencySource(
                currencyCode: currencyCode
            )
        )
        guard !migration.anomalyReport.isBlocking,
              migration.settings.categoryBudgetsMinorUnits ==
                categoryBudgetsMinorUnits else {
            throw SupabaseBudgetSyncError.invalidCloudMoneyContract
        }
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

private struct AcceptBudgetInviteParameters: Encodable {
    let inviteId: UUID

    enum CodingKeys: String, CodingKey {
        case inviteId = "p_invite_id"
    }
}

private struct CreateBudgetHouseholdParameters: Encodable {
    let name: String
    let budgetId: UUID
    let ownerMemberId: UUID

    enum CodingKeys: String, CodingKey {
        case name = "p_name"
        case budgetId = "p_budget_id"
        case ownerMemberId = "p_owner_member_id"
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

struct CloudTransactionSplitMoneyRow: Codable, Equatable {
    let id: UUID
    let memberId: UUID
    let amountMinorUnits: Int64
    let currencyCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case memberId = "member_id"
        case amountMinorUnits = "amount_minor_units"
        case currencyCode = "currency_code"
    }
}

struct CloudTransactionRow: Codable {
    let id: UUID
    let userId: UUID
    let budgetId: UUID
    let title: String
    let amount: Double
    let amountMinorUnits: Int64?
    let currencyCode: String?
    let type: String
    let category: String
    let paymentMethod: String?
    let createdByMemberId: UUID
    let createdByUserId: UUID?
    let rowVersion: Int64?
    let lastMutationId: UUID?
    let date: String
    var occurredOn: String?
    let createdAt: String
    let recurrenceRule: String?
    let splits: [CloudTransactionSplitRow]
    let splitsMinorUnits: [CloudTransactionSplitMoneyRow]?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case budgetId = "budget_id"
        case title
        case amount
        case amountMinorUnits = "amount_minor_units"
        case currencyCode = "currency_code"
        case type
        case category
        case paymentMethod = "payment_method"
        case createdByMemberId = "created_by_member_id"
        case createdByUserId = "created_by_user_id"
        case rowVersion = "row_version"
        case lastMutationId = "last_mutation_id"
        case date
        case occurredOn = "occurred_on"
        case createdAt = "created_at"
        case recurrenceRule = "recurrence_rule"
        case splits
        case splitsMinorUnits = "splits_minor_units"
    }

    init(
        transaction: Transaction,
        userId: UUID,
        budgetId: UUID? = nil,
        existingUserId: UUID? = nil,
        memberAliases: [UUID: UUID] = [:],
        validMemberIds: Set<UUID> = [],
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) {
        id = transaction.id
        self.userId = existingUserId ?? userId
        self.budgetId = budgetId ?? userId
        title = transaction.title
        amount = transaction.amount
        if rolloutEnabled,
           let exactMinorUnits = transaction.amountMinorUnits,
           let exactCurrencyCode = transaction.currencyCode {
            amountMinorUnits = exactMinorUnits
            currencyCode = exactCurrencyCode
        } else {
            amountMinorUnits = nil
            currencyCode = nil
        }
        type = transaction.type.rawValue
        category = transaction.category.rawValue
        paymentMethod = transaction.paymentMethod?.rawValue
        createdByMemberId = Self.resolvedCreatedByMemberId(
            transaction.createdByMemberId,
            rowUserId: userId,
            aliases: memberAliases,
            validMemberIds: validMemberIds
        )
        createdByUserId = transaction.createdByUserId ?? existingUserId
        rowVersion = transaction.rowVersion
        lastMutationId = transaction.lastMutationId
        date = Self.string(from: transaction.date)
        occurredOn = CloudISO8601DateCodec.localDateString(from: transaction.date)
        createdAt = Self.string(from: transaction.createdAt)
        recurrenceRule = transaction.recurrenceRule
        splits = transaction.splits.map {
            CloudTransactionSplitRow(
                id: $0.id,
                memberId: Self.resolvedMemberId($0.memberId, aliases: memberAliases),
                amount: $0.amount
            )
        }
        if rolloutEnabled {
            let exactSplits = transaction.splits.compactMap {
                split -> CloudTransactionSplitMoneyRow? in
                guard let exactMinorUnits = split.amountMinorUnits,
                      let exactCurrencyCode = split.currencyCode else {
                    return nil
                }
                return CloudTransactionSplitMoneyRow(
                    id: split.id,
                    memberId: Self.resolvedMemberId(
                        split.memberId,
                        aliases: memberAliases
                    ),
                    amountMinorUnits: exactMinorUnits,
                    currencyCode: exactCurrencyCode
                )
            }
            splitsMinorUnits = exactSplits.count == transaction.splits.count
                ? exactSplits
                : nil
        } else {
            splitsMinorUnits = nil
        }
    }

    func apply(
        to transaction: Transaction,
        ownerUserId: String,
        memberAliases: [UUID: UUID] = [:],
        validMemberIds: Set<UUID> = [],
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) {
        transaction.title = title
        transaction.amount = amount
        if rolloutEnabled {
            transaction.amountMinorUnits = amountMinorUnits
            transaction.currencyCode = currencyCode
        }
        transaction.type = TransactionType(rawValue: type) ?? .expense
        transaction.category = TransactionCategory(rawValue: category)
        transaction.paymentMethod = paymentMethod.flatMap(PaymentMethod.init(rawValue:))
        transaction.createdByMemberId = Self.resolvedCreatedByMemberId(
            createdByMemberId,
            rowUserId: userId,
            aliases: memberAliases,
            validMemberIds: validMemberIds
        )
        transaction.createdByUserId = createdByUserId
        transaction.rowVersion = rowVersion
        transaction.lastMutationId = lastMutationId
        transaction.date = resolvedDate
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
        validMemberIds: Set<UUID>,
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) -> Bool {
        transaction.title == title &&
        transaction.amount == amount &&
        (!rolloutEnabled || (
            transaction.amountMinorUnits == amountMinorUnits &&
            transaction.currencyCode == currencyCode
        )) &&
        transaction.type == (TransactionType(rawValue: type) ?? .expense) &&
        transaction.category == TransactionCategory(rawValue: category) &&
        transaction.paymentMethod == paymentMethod.flatMap(PaymentMethod.init(rawValue:)) &&
        transaction.createdByMemberId == Self.resolvedCreatedByMemberId(
            createdByMemberId,
            rowUserId: userId,
            aliases: memberAliases,
            validMemberIds: validMemberIds
        ) &&
        transaction.createdByUserId == createdByUserId &&
        transaction.rowVersion == rowVersion &&
        transaction.lastMutationId == lastMutationId &&
        matchesDate(transaction.date) &&
        CloudISO8601DateCodec.representsSameInstant(transaction.createdAt, as: createdAt) &&
        transaction.recurrenceRule == recurrenceRule &&
        transaction.ownerUserId == ownerUserId
    }

    /// Whether the local splits already equal this row's splits (after alias
    /// resolution), so the merge can leave the relationship untouched.
    func splitsMatch(
        _ transaction: Transaction,
        memberAliases: [UUID: UUID],
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) -> Bool {
        let desired = splits.filter { $0.amount > 0 }
        let existing = transaction.splits
        guard desired.count == existing.count else { return false }

        let existingById = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard existingById.count == existing.count else { return false }

        let legacyMatches = desired.allSatisfy { row in
            guard let split = existingById[row.id] else { return false }
            return split.memberId == Self.resolvedMemberId(row.memberId, aliases: memberAliases)
                && split.amount == row.amount
        }
        guard legacyMatches, rolloutEnabled else { return legacyMatches }
        guard let splitsMinorUnits,
              splitsMinorUnits.count == existing.count else {
            return false
        }
        let exactByID = Dictionary(
            splitsMinorUnits.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard exactByID.count == splitsMinorUnits.count else { return false }
        return existing.allSatisfy { split in
            guard let exact = exactByID[split.id] else { return false }
            return split.memberId == Self.resolvedMemberId(
                exact.memberId,
                aliases: memberAliases
            )
                && split.amountMinorUnits == exact.amountMinorUnits
                && split.currencyCode == exact.currencyCode
        }
    }

    func makeTransaction(
        ownerUserId: String,
        memberAliases: [UUID: UUID] = [:],
        validMemberIds: Set<UUID> = [],
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) -> Transaction {
        Transaction(
            id: id,
            title: title,
            amount: amount,
            amountMinorUnits: rolloutEnabled ? amountMinorUnits : nil,
            currencyCode: rolloutEnabled ? currencyCode : nil,
            type: TransactionType(rawValue: type) ?? .expense,
            category: TransactionCategory(rawValue: category),
            paymentMethod: paymentMethod.flatMap(PaymentMethod.init(rawValue:)),
            createdByMemberId: Self.resolvedCreatedByMemberId(
                createdByMemberId,
                rowUserId: userId,
                aliases: memberAliases,
                validMemberIds: validMemberIds
            ),
            createdByUserId: createdByUserId,
            rowVersion: rowVersion,
            lastMutationId: lastMutationId,
            date: resolvedDate,
            createdAt: CloudISO8601DateCodec.dateOrNow(from: createdAt),
            recurrenceRule: recurrenceRule,
            ownerUserId: ownerUserId
        )
    }

    func validateDates(
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) throws {
        if let occurredOn,
           CloudISO8601DateCodec.localDate(from: occurredOn) == nil {
            throw SupabaseBudgetSyncError.invalidCloudDate(occurredOn)
        }
        guard CloudISO8601DateCodec.date(from: date) != nil else {
            throw SupabaseBudgetSyncError.invalidCloudDate(date)
        }

        guard CloudISO8601DateCodec.date(from: createdAt) != nil else {
            throw SupabaseBudgetSyncError.invalidCloudDate(createdAt)
        }
        try validateMoneyContract(rolloutEnabled: rolloutEnabled)
    }

    private func validateMoneyContract(rolloutEnabled: Bool) throws {
        guard rolloutEnabled else { return }
        let exactAmount = try CloudMoneyContract.validatedExactMoney(
            legacyAmount: amount,
            minorUnits: amountMinorUnits,
            currencyCode: currencyCode,
            rolloutEnabled: true
        )
        guard exactAmount != nil || splitsMinorUnits == nil else {
            throw SupabaseBudgetSyncError.invalidCloudMoneyContract
        }
        guard let exactSplits = splitsMinorUnits else { return }
        guard exactSplits.count == splits.count else {
            throw SupabaseBudgetSyncError.invalidCloudMoneyContract
        }
        let exactByID = Dictionary(
            exactSplits.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard exactByID.count == exactSplits.count else {
            throw SupabaseBudgetSyncError.invalidCloudMoneyContract
        }

        var exactTotal: Int64 = 0
        for legacySplit in splits {
            guard let exactSplit = exactByID[legacySplit.id],
                  exactSplit.memberId == legacySplit.memberId else {
                throw SupabaseBudgetSyncError.invalidCloudMoneyContract
            }
            let splitMoney = try CloudMoneyContract.validatedExactMoney(
                legacyAmount: legacySplit.amount,
                minorUnits: exactSplit.amountMinorUnits,
                currencyCode: exactSplit.currencyCode,
                rolloutEnabled: true
            )
            guard splitMoney?.currencyCode == exactAmount?.currencyCode else {
                throw SupabaseBudgetSyncError.invalidCloudMoneyContract
            }
            let sum = exactTotal.addingReportingOverflow(
                exactSplit.amountMinorUnits
            )
            guard !sum.overflow else {
                throw SupabaseBudgetSyncError.invalidCloudMoneyContract
            }
            exactTotal = sum.partialValue
        }
        if !exactSplits.isEmpty, exactTotal != exactAmount?.minorUnits {
            throw SupabaseBudgetSyncError.invalidCloudMoneyContract
        }
    }

    private static func string(from date: Date) -> String {
        CloudISO8601DateCodec.string(from: date)
    }

    private var resolvedDate: Date {
        occurredOn.flatMap(CloudISO8601DateCodec.localDate(from:))
            ?? CloudISO8601DateCodec.dateOrNow(from: date)
    }

    private func matchesDate(_ localDate: Date) -> Bool {
        if let occurredOn {
            return CloudISO8601DateCodec.localDateString(from: localDate) == occurredOn
        }
        return CloudISO8601DateCodec.representsSameInstant(localDate, as: date)
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
    let createdByUserId: UUID?
    let rowVersion: Int64?
    let lastMutationId: UUID?
    let amount: Double
    let amountMinorUnits: Int64?
    let currencyCode: String?
    let date: String
    var occurredOn: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case budgetId = "budget_id"
        case fromMemberId = "from_member_id"
        case toMemberId = "to_member_id"
        case createdByUserId = "created_by_user_id"
        case rowVersion = "row_version"
        case lastMutationId = "last_mutation_id"
        case amount
        case amountMinorUnits = "amount_minor_units"
        case currencyCode = "currency_code"
        case date
        case occurredOn = "occurred_on"
    }

    init(
        settlement: Settlement,
        userId: UUID,
        budgetId: UUID? = nil,
        existingUserId: UUID? = nil,
        memberAliases: [UUID: UUID] = [:],
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) {
        id = settlement.id
        self.userId = existingUserId ?? userId
        self.budgetId = budgetId ?? userId
        fromMemberId = CloudTransactionRow.resolvedMemberId(settlement.fromMemberId, aliases: memberAliases)
        toMemberId = CloudTransactionRow.resolvedMemberId(settlement.toMemberId, aliases: memberAliases)
        createdByUserId = settlement.createdByUserId ?? existingUserId
        rowVersion = settlement.rowVersion
        lastMutationId = settlement.lastMutationId
        amount = settlement.amount
        if rolloutEnabled,
           let exactMinorUnits = settlement.amountMinorUnits,
           let exactCurrencyCode = settlement.currencyCode {
            amountMinorUnits = exactMinorUnits
            currencyCode = exactCurrencyCode
        } else {
            amountMinorUnits = nil
            currencyCode = nil
        }
        date = CloudISO8601DateCodec.string(from: settlement.date)
        occurredOn = CloudISO8601DateCodec.localDateString(from: settlement.date)
    }

    func apply(
        to settlement: Settlement,
        ownerUserId: String,
        memberAliases: [UUID: UUID] = [:],
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) {
        settlement.fromMemberId = CloudTransactionRow.resolvedMemberId(fromMemberId, aliases: memberAliases)
        settlement.toMemberId = CloudTransactionRow.resolvedMemberId(toMemberId, aliases: memberAliases)
        settlement.createdByUserId = createdByUserId
        settlement.rowVersion = rowVersion
        settlement.lastMutationId = lastMutationId
        settlement.amount = amount
        if rolloutEnabled {
            settlement.amountMinorUnits = amountMinorUnits
            settlement.currencyCode = currencyCode
        }
        settlement.date = resolvedDate
        settlement.ownerUserId = ownerUserId
    }

    /// Whether applying this row to `settlement` would be a no-op (see
    /// `CloudTransactionRow.matches`).
    func matches(
        _ settlement: Settlement,
        ownerUserId: String,
        memberAliases: [UUID: UUID],
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) -> Bool {
        settlement.fromMemberId == CloudTransactionRow.resolvedMemberId(fromMemberId, aliases: memberAliases) &&
        settlement.toMemberId == CloudTransactionRow.resolvedMemberId(toMemberId, aliases: memberAliases) &&
        settlement.createdByUserId == createdByUserId &&
        settlement.rowVersion == rowVersion &&
        settlement.lastMutationId == lastMutationId &&
        settlement.amount == amount &&
        (!rolloutEnabled || (
            settlement.amountMinorUnits == amountMinorUnits &&
            settlement.currencyCode == currencyCode
        )) &&
        matchesDate(settlement.date) &&
        settlement.ownerUserId == ownerUserId
    }

    func makeSettlement(
        ownerUserId: String,
        memberAliases: [UUID: UUID] = [:],
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) -> Settlement {
        Settlement(
            id: id,
            fromMemberId: CloudTransactionRow.resolvedMemberId(fromMemberId, aliases: memberAliases),
            toMemberId: CloudTransactionRow.resolvedMemberId(toMemberId, aliases: memberAliases),
            amount: amount,
            amountMinorUnits: rolloutEnabled ? amountMinorUnits : nil,
            currencyCode: rolloutEnabled ? currencyCode : nil,
            createdByUserId: createdByUserId,
            rowVersion: rowVersion,
            lastMutationId: lastMutationId,
            date: resolvedDate,
            ownerUserId: ownerUserId
        )
    }

    func validateDate(
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) throws {
        if let occurredOn,
           CloudISO8601DateCodec.localDate(from: occurredOn) == nil {
            throw SupabaseBudgetSyncError.invalidCloudDate(occurredOn)
        }
        guard CloudISO8601DateCodec.date(from: date) != nil else {
            throw SupabaseBudgetSyncError.invalidCloudDate(date)
        }
        _ = try CloudMoneyContract.validatedExactMoney(
            legacyAmount: amount,
            minorUnits: amountMinorUnits,
            currencyCode: currencyCode,
            rolloutEnabled: rolloutEnabled
        )
    }

    private var resolvedDate: Date {
        occurredOn.flatMap(CloudISO8601DateCodec.localDate(from:))
            ?? CloudISO8601DateCodec.dateOrNow(from: date)
    }

    private func matchesDate(_ localDate: Date) -> Bool {
        if let occurredOn {
            return CloudISO8601DateCodec.localDateString(from: localDate) == occurredOn
        }
        return CloudISO8601DateCodec.representsSameInstant(localDate, as: date)
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
    /// Older deployments do not have the date-only compatibility columns.
    /// Once PostgREST reports them missing, use legacy payloads for this run.

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    @discardableResult
    static func prepareMutationIDs(
        transactions: [Transaction],
        settlements: [Settlement]
    ) -> Bool {
        var changed = false
        for transaction in transactions where transaction.needsSync && transaction.lastMutationId == nil {
            transaction.lastMutationId = UUID()
            changed = true
        }
        for settlement in settlements where settlement.needsSync && settlement.lastMutationId == nil {
            settlement.lastMutationId = UUID()
            changed = true
        }
        return changed
    }

    static func shouldDeferFinancialWrites(
        transactions: [Transaction],
        settlements: [Settlement]
    ) -> Bool {
        !SharedDataSafetyGate.isEnabled &&
            (transactions.contains(where: \.needsSync) || settlements.contains(where: \.needsSync))
    }

    func sync(
        settings: BudgetSettings,
        shouldPushSettings: Bool,
        members: [BudgetMember],
        shouldPushMembers: Bool,
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
        let dirtyTransactions = transactions.filter(\.needsSync)
        let dirtySettlements = settlements.filter(\.needsSync)

        // A passive pull used to revalidate every historical row and every
        // split on the main actor. On a larger budget that work could land
        // while the keyboard was active and visibly stall transaction entry.
        // Only rows that can be uploaded in this pass need local validation;
        // pulled cloud rows are validated separately below.
        if shouldPushMembers {
            try normalizedMembers.forEach { try $0.validateForSync() }
        }
        try dirtyTransactions.forEach { try $0.validateForSync() }
        try dirtySettlements.forEach { try $0.validateForSync() }

        // Persist IDs before the first network attempt. A legacy dirty row
        // must not receive a new id after a crash between pull and RPC.
        if Self.prepareMutationIDs(transactions: dirtyTransactions, settlements: dirtySettlements) {
            try context.save()
        }
        let financialWritesEnabled = SharedDataSafetyGate.isEnabled

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
        let memberRows = shouldPushMembers ? try await writableMemberRows(
            candidateMemberRows,
            existingRows: existingMemberRows,
            memberAliases: memberAliases,
            userId: userId,
            budgetId: budgetId,
            signedInMemberIds: signedInMemberIds
        ) : []
        let cloudTransactions: [CloudTransactionRow] = try await client
            .from("budget_transactions")
            .select()
            .eq("budget_id", value: budgetId)
            .execute()
            .value
        let cloudSettlements: [CloudSettlementRow] = try await client
            .from("budget_settlements")
            .select()
            .eq("budget_id", value: budgetId)
            .execute()
            .value
        try cloudTransactions.forEach { try $0.validateDates() }
        try cloudSettlements.forEach { try $0.validateDate() }
        let cloudTransactionsByID = Dictionary(cloudTransactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let cloudSettlementsByID = Dictionary(cloudSettlements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let transactionRows = Self.uniqueRows(dirtyTransactions
            .map {
                CloudTransactionRow(
                    transaction: $0,
                    userId: userId,
                    budgetId: budgetId,
                    existingUserId: cloudTransactionsByID[$0.id]?.userId,
                    memberAliases: memberAliases,
                    validMemberIds: validMemberIds
                )
            },
            by: \.id
        )
        let pushedTransactionIDs = financialWritesEnabled ? Set(transactionRows.map(\.id)) : []
        let settlementRows = Self.uniqueRows(dirtySettlements
            .map {
                CloudSettlementRow(
                    settlement: $0,
                    userId: userId,
                    budgetId: budgetId,
                    existingUserId: cloudSettlementsByID[$0.id]?.userId,
                    memberAliases: memberAliases
                )
            },
            by: \.id
        )
        let pushedSettlementIDs = financialWritesEnabled ? Set(settlementRows.map(\.id)) : []

        let didPushSettings = existingSettings == nil || shouldPushSettings
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

        if financialWritesEnabled {
          for transaction in dirtyTransactions {
            if transaction.rowVersion == nil {
                transaction.rowVersion = cloudTransactionsByID[transaction.id]?.rowVersion
            }
            let mutationId = transaction.lastMutationId ?? UUID()
            let operation = cloudTransactionsByID[transaction.id] == nil ? "insert" : "update"
            let result = try await mutateTransaction(
                transaction,
                operation: operation,
                userScopeId: userScopeId,
                budgetScopeId: budgetId.uuidString,
                mutationId: mutationId,
                memberAliases: memberAliases
            )
            transaction.rowVersion = result.rowVersion
            transaction.lastMutationId = mutationId
            transaction.needsSync = false
          }

          for settlement in dirtySettlements {
            if settlement.rowVersion == nil {
                settlement.rowVersion = cloudSettlementsByID[settlement.id]?.rowVersion
            }
            let mutationId = settlement.lastMutationId ?? UUID()
            let operation = cloudSettlementsByID[settlement.id] == nil ? "insert" : "update"
            let result = try await mutateSettlement(
                settlement,
                operation: operation,
                userScopeId: userScopeId,
                budgetScopeId: budgetId.uuidString,
                mutationId: mutationId,
                memberAliases: memberAliases
            )
            settlement.rowVersion = result.rowVersion
            settlement.lastMutationId = mutationId
            settlement.needsSync = false
          }
        }

        // The rows just written are the authoritative values for this pass.
        // Reconcile them into the initial pull instead of issuing two more
        // full-table reads after every sync.
        let pulledTransactions: [CloudTransactionRow] = !financialWritesEnabled || transactionRows.isEmpty
            ? cloudTransactions
            : try await client
                .from("budget_transactions")
                .select()
                .eq("budget_id", value: budgetId)
                .execute()
                .value
        let pulledSettlements: [CloudSettlementRow] = !financialWritesEnabled || settlementRows.isEmpty
            ? cloudSettlements
            : try await client
                .from("budget_settlements")
                .select()
                .eq("budget_id", value: budgetId)
                .execute()
                .value

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
            pushedSettings: didPushSettings,
            pushedMembers: memberRows.count,
            pulledMembers: pulledMembers.count,
            pushedTransactions: financialWritesEnabled ? transactionRows.count : 0,
            pulledTransactions: pulledTransactions.count,
            pushedSettlements: financialWritesEnabled ? settlementRows.count : 0,
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

        guard let row = rows.first else { return nil }
        try row.validateMoneyContract()
        return row.makeSettings()
    }

    func fetchCurrencyBaseline(
        userScopeId: String,
        budgetScopeId: String? = nil
    ) async throws -> CloudCurrencyBaselineSnapshot {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId
        let settings = try await fetchSettings(
            userScopeId: userScopeId,
            budgetScopeId: budgetId.uuidString
        )
        let transactionRows: [CloudRecordIdentityRow] = try await client
            .from("budget_transactions")
            .select("id")
            .eq("budget_id", value: budgetId)
            .limit(1)
            .execute()
            .value
        let settlementRows: [CloudRecordIdentityRow] = try await client
            .from("budget_settlements")
            .select("id")
            .eq("budget_id", value: budgetId)
            .limit(1)
            .execute()
            .value

        return CloudCurrencyBaselineSnapshot(
            settings: settings,
            hasTransactionOrSplit: !transactionRows.isEmpty,
            hasSettlement: !settlementRows.isEmpty
        )
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

    func ensureSharedBudget(
        name: String,
        userScopeId: String,
        budgetId: UUID,
        ownerMemberId: UUID
    ) async throws -> BudgetSummary {
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }

        try await ensurePersonalBudget(userId: userId)
        return try await ensureSharedBudget(
            ownerUserId: userId,
            name: name,
            budgetId: budgetId,
            ownerMemberId: ownerMemberId
        )
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

        do {
            try await client
                .rpc("accept_budget_invite", params: AcceptBudgetInviteParameters(inviteId: invite.id))
                .execute()
            return
        } catch {
            // Keep compatibility while the migration rolls out, but never
            // fall back after an authorization or validation error from the
            // atomic function.
            guard Self.isMissingFunction(error, named: "accept_budget_invite") else {
                throw error
            }
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

    func deleteMember(id: UUID, userScopeId: String, budgetScopeId: String? = nil) async throws {
        guard let userId = UUID(uuidString: userScopeId) else { return }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId

        try await client
            .from("budget_members")
            .delete()
            .eq("id", value: id)
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

    func deleteTransaction(
        id: UUID,
        expectedRowVersion: Int64? = nil,
        userScopeId: String,
        budgetScopeId: String? = nil,
        mutationId: UUID = UUID()
    ) async throws {
        guard let expectedRowVersion else {
            throw SupabaseBudgetSyncError.unsafePendingDeletion
        }
        _ = try await deleteTransactionSafely(
            id: id,
            expectedRowVersion: expectedRowVersion,
            userScopeId: userScopeId,
            budgetScopeId: budgetScopeId,
            mutationId: mutationId
        )
    }

    func mutateTransaction(
        _ transaction: Transaction,
        operation: String,
        userScopeId: String,
        budgetScopeId: String? = nil,
        mutationId: UUID = UUID(),
        memberAliases: [UUID: UUID] = [:]
    ) async throws -> SharedDataSafetyMutationResult {
        guard SharedDataSafetyGate.isEnabled else {
            throw SupabaseBudgetSyncError.sharedDataSafetyDisabled
        }
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId
        try transaction.validateForSync()
        let params = SharedDataSafetyMutationParameters(
            budgetId: budgetId,
            recordId: transaction.id,
            expectedRowVersion: transaction.rowVersion ?? 0,
            clientMutationId: mutationId,
            operation: operation,
            payload: TransactionMutationPayload(transaction: transaction, memberAliases: memberAliases)
        )
        do {
            return try await client
                .rpc("mutate_budget_transaction", params: params)
                .execute()
                .value
        } catch {
            throw Self.mapMutationError(error)
        }
    }

    func deleteTransactionSafely(
        id: UUID,
        expectedRowVersion: Int64?,
        userScopeId: String,
        budgetScopeId: String? = nil,
        mutationId: UUID
    ) async throws -> SharedDataSafetyMutationResult {
        guard SharedDataSafetyGate.isEnabled else {
            throw SupabaseBudgetSyncError.sharedDataSafetyDisabled
        }
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId
        guard let expectedRowVersion else {
            throw SupabaseBudgetSyncError.unsafePendingDeletion
        }
        let params = SharedDataSafetyMutationParameters(
            budgetId: budgetId,
            recordId: id,
            expectedRowVersion: expectedRowVersion,
            clientMutationId: mutationId,
            operation: "delete",
            payload: EmptySharedDataSafetyPayload()
        )
        do {
            return try await client
                .rpc("mutate_budget_transaction", params: params)
                .execute()
                .value
        } catch {
            throw Self.mapMutationError(error)
        }
    }

    func upsertTransaction(_ transaction: Transaction, userScopeId: String, budgetScopeId: String? = nil) async throws {
        try await upsertTransactions(
            [transaction],
            userScopeId: userScopeId,
            budgetScopeId: budgetScopeId
        )
    }

    func upsertTransactions(
        _ transactions: [Transaction],
        userScopeId: String,
        budgetScopeId: String? = nil
    ) async throws {
        guard !transactions.isEmpty else { return }
        guard SharedDataSafetyGate.isEnabled else {
            throw SupabaseBudgetSyncError.sharedDataSafetyDisabled
        }
        for transaction in transactions {
            let mutationId = transaction.lastMutationId ?? UUID()
            let result = try await mutateTransaction(
                transaction,
                operation: transaction.rowVersion == nil ? "insert" : "update",
                userScopeId: userScopeId,
                budgetScopeId: budgetScopeId,
                mutationId: mutationId
            )
            transaction.rowVersion = result.rowVersion
            transaction.lastMutationId = mutationId
        }
    }

    func upsertSettlement(_ settlement: Settlement, userScopeId: String, budgetScopeId: String? = nil) async throws {
        guard SharedDataSafetyGate.isEnabled else {
            throw SupabaseBudgetSyncError.sharedDataSafetyDisabled
        }
        let mutationId = settlement.lastMutationId ?? UUID()
        let result = try await mutateSettlement(
            settlement,
            operation: settlement.rowVersion == nil ? "insert" : "update",
            userScopeId: userScopeId,
            budgetScopeId: budgetScopeId,
            mutationId: mutationId
        )
        settlement.rowVersion = result.rowVersion
        settlement.lastMutationId = mutationId
    }

    func deleteSettlement(
        id: UUID,
        expectedRowVersion: Int64? = nil,
        userScopeId: String,
        budgetScopeId: String? = nil,
        mutationId: UUID = UUID()
    ) async throws {
        guard let expectedRowVersion else {
            throw SupabaseBudgetSyncError.unsafePendingDeletion
        }
        _ = try await deleteSettlementSafely(
            id: id,
            expectedRowVersion: expectedRowVersion,
            userScopeId: userScopeId,
            budgetScopeId: budgetScopeId,
            mutationId: mutationId
        )
    }

    func mutateSettlement(
        _ settlement: Settlement,
        operation: String,
        userScopeId: String,
        budgetScopeId: String? = nil,
        mutationId: UUID = UUID(),
        memberAliases: [UUID: UUID] = [:]
    ) async throws -> SharedDataSafetyMutationResult {
        guard SharedDataSafetyGate.isEnabled else {
            throw SupabaseBudgetSyncError.sharedDataSafetyDisabled
        }
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId
        try settlement.validateForSync()
        let params = SharedDataSafetyMutationParameters(
            budgetId: budgetId,
            recordId: settlement.id,
            expectedRowVersion: settlement.rowVersion ?? 0,
            clientMutationId: mutationId,
            operation: operation,
            payload: SettlementMutationPayload(settlement: settlement, memberAliases: memberAliases)
        )
        do {
            return try await client
                .rpc("mutate_budget_settlement", params: params)
                .execute()
                .value
        } catch {
            throw Self.mapMutationError(error)
        }
    }

    func deleteSettlementSafely(
        id: UUID,
        expectedRowVersion: Int64?,
        userScopeId: String,
        budgetScopeId: String? = nil,
        mutationId: UUID
    ) async throws -> SharedDataSafetyMutationResult {
        guard SharedDataSafetyGate.isEnabled else {
            throw SupabaseBudgetSyncError.sharedDataSafetyDisabled
        }
        guard let userId = UUID(uuidString: userScopeId) else {
            throw SupabaseBudgetSyncError.missingUser
        }
        let budgetId = UUID(uuidString: budgetScopeId ?? userScopeId) ?? userId
        guard let expectedRowVersion else {
            throw SupabaseBudgetSyncError.unsafePendingDeletion
        }
        let params = SharedDataSafetyMutationParameters(
            budgetId: budgetId,
            recordId: id,
            expectedRowVersion: expectedRowVersion,
            clientMutationId: mutationId,
            operation: "delete",
            payload: EmptySharedDataSafetyPayload()
        )
        do {
            return try await client
                .rpc("mutate_budget_settlement", params: params)
                .execute()
                .value
        } catch {
            throw Self.mapMutationError(error)
        }
    }

    private static func mapMutationError(_ error: Error) -> Error {
        let message = error.localizedDescription.lowercased()
        if message.contains("idempotency_mismatch") {
            return SupabaseBudgetSyncError.idempotencyMismatch
        }
        if message.contains("remote_deleted") {
            return SupabaseBudgetSyncError.remoteDeleted
        }
        if message.contains("record_not_found") {
            return SupabaseBudgetSyncError.mutationRecordNotFound
        }
        if message.contains("invalid_member_reference") {
            return SupabaseBudgetSyncError.invalidMemberReference
        }
        if message.contains("member_reference_forbidden") {
            return SupabaseBudgetSyncError.memberReferenceForbidden
        }
        if message.contains("changed on another device") {
            return SupabaseBudgetSyncError.sharedDataMutationConflict
        }
        return error
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

    private func ensureSharedBudget(
        ownerUserId: UUID,
        name: String,
        budgetId: UUID,
        ownerMemberId: UUID
    ) async throws -> BudgetSummary {
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
            // Heal a legacy non-atomic attempt that committed the budget row
            // but failed before creating its owner membership.
            try await client
                .from("budget_memberships")
                .upsert(
                    CloudBudgetMembershipRow(
                        budgetId: existing.id,
                        userId: ownerUserId,
                        role: "owner",
                        status: "active"
                    ),
                    onConflict: "budget_id,user_id"
                )
                .execute()
            return existing.makeSummary()
        }

        do {
            let createdBudgetId: UUID = try await client
                .rpc(
                    "create_budget_household",
                    params: CreateBudgetHouseholdParameters(
                        name: safeName,
                        budgetId: budgetId,
                        ownerMemberId: ownerMemberId
                    )
                )
                .execute()
                .value
            return BudgetSummary(id: createdBudgetId, name: safeName)
        } catch {
            // Older database deployments used the direct table bootstrap.
            // Only use it when the atomic function itself is unavailable.
            guard Self.isMissingFunction(error, named: "create_budget_household") else {
                throw error
            }
        }

        let budget = CloudBudgetRow(
            id: budgetId,
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

    private static func isMissingFunction(_ error: Error, named functionName: String) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains(functionName.lowercased()) &&
            (message.contains("schema cache") ||
                message.contains("could not find") ||
                message.contains("does not exist"))
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

                // A queued save can dirty this model while the full sync is
                // suspended on the network. In that case `row` is the older
                // payload captured by this sync. Preserve the newer local
                // values so the serialized save that follows can upload them.
                if transaction.needsSync && (!fieldsMatch || !splitsMatch) {
                    continue
                }

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
        in context: ModelContext,
        rolloutEnabled: Bool = MoneyServerBridgeRollout.isEnabled
    ) {
        for split in Array(transaction.splits) {
            context.delete(split)
        }

        let exactByID = Dictionary(
            (row.splitsMinorUnits ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for splitRow in row.splits where splitRow.amount > 0 {
            let exact = rolloutEnabled ? exactByID[splitRow.id] : nil
            context.insert(
                TransactionSplit(
                    id: splitRow.id,
                    memberId: CloudTransactionRow.resolvedMemberId(splitRow.memberId, aliases: memberAliases),
                    amount: splitRow.amount,
                    amountMinorUnits: exact?.amountMinorUnits,
                    currencyCode: exact?.currencyCode,
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
                let fieldsMatch = row.matches(
                    settlement,
                    ownerUserId: ownerUserId,
                    memberAliases: memberAliases
                )

                // See the transaction merge above: never overwrite a newer
                // dirty edit with the older payload from an in-flight sync.
                if settlement.needsSync && !fieldsMatch {
                    continue
                }

                if !fieldsMatch {
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

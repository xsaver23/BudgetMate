import Foundation
import SwiftData

@Model
final class Transaction {
    var id: UUID
    var title: String
    var amount: Double
    var type: TransactionType
    var category: TransactionCategory
    var paymentMethod: PaymentMethod?
    var createdByMemberId: UUID
    var date: Date
    var createdAt: Date
    var recurrenceRule: String?
    var ownerUserId: String
    /// True while a locally created or edited row has not been confirmed in
    /// the cloud. Protects offline work from the sync prune pass.
    var needsSync: Bool = false
    @Transient var recurringSourceId: UUID?

    /// Per-member shares for a split expense. Empty for non-split transactions.
    @Relationship(deleteRule: .cascade, inverse: \TransactionSplit.transaction)
    var splits: [TransactionSplit] = []

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        type: TransactionType,
        category: TransactionCategory,
        paymentMethod: PaymentMethod? = nil,
        createdByMemberId: UUID,
        date: Date = .now,
        createdAt: Date = .now,
        recurrenceRule: String? = nil,
        ownerUserId: String = "local"
    ) {
        self.id = id
        self.title = Self.normalizedTitle(title)
        self.amount = max(0, amount)
        self.type = type
        self.category = category
        self.paymentMethod = paymentMethod
        self.createdByMemberId = createdByMemberId
        self.date = date
        self.createdAt = createdAt
        self.recurrenceRule = recurrenceRule
        self.ownerUserId = ownerUserId
    }
}

extension Transaction {
    static func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    func validateForSync() throws {
        guard amount > 0, amount.isFinite else {
            throw BudgetDataValidationError.invalidTransactionAmount(title: title)
        }

        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BudgetDataValidationError.emptyTransactionTitle
        }

        try splits.forEach { try $0.validateForSync() }
    }

    var isMonthlyRecurring: Bool {
        recurrenceRule?.hasPrefix("monthly") == true
    }

    var recurrenceEndDate: Date? {
        guard let recurrenceRule,
              let range = recurrenceRule.range(of: "until=") else {
            return nil
        }
        let rawDate = String(recurrenceRule[range.upperBound...])
        return Self.recurrenceDateFormatter.date(from: rawDate)
    }

    var isGeneratedRecurringOccurrence: Bool {
        recurringSourceId != nil
    }

    static func monthlyRecurrenceRule(until endDate: Date?) -> String {
        guard let endDate else { return "monthly" }
        return "monthly|until=\(recurrenceDateFormatter.string(from: endDate))"
    }

    /// True when the transaction's cost is divided among members.
    var isSplit: Bool { !splits.isEmpty }

    /// Members the cost applies to: split participants, or just the payer.
    var participantIds: [UUID] {
        guard isSplit else { return [createdByMemberId] }

        var ids: [UUID] = []
        for split in splits where !ids.contains(split.memberId) {
            ids.append(split.memberId)
        }
        return ids
    }

    /// Amount a given member is responsible for (expenses only).
    /// For split expenses this is their share; otherwise the full amount
    /// is attributed to the payer.
    func consumedExpense(for memberId: UUID) -> Double {
        guard type == .expense else { return 0 }
        if isSplit {
            for split in splits where split.memberId == memberId {
                return split.amount
            }
            return 0
        }
        return createdByMemberId == memberId ? amount : 0
    }

    /// Whether this transaction should appear when filtering by member.
    func involves(memberId: UUID) -> Bool {
        if type == .expense {
            if isSplit {
                return splits.contains { $0.memberId == memberId }
            }
            return createdByMemberId == memberId
        }
        return createdByMemberId == memberId
    }

    private static let recurrenceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum BudgetDataValidationError: LocalizedError {
    case emptyMemberName
    case invalidMemberNameEmoji
    case emptyTransactionTitle
    case invalidTransactionAmount(title: String)
    case invalidSplitAmount
    case invalidSettlementAmount
    case invalidSettlementDirection

    var errorDescription: String? {
        switch self {
        case .emptyMemberName:
            return "Member names cannot be empty."
        case .invalidMemberNameEmoji:
            return "Member names cannot include emoji."
        case .emptyTransactionTitle:
            return "Transaction titles cannot be empty."
        case .invalidTransactionAmount(let title):
            return "Transaction \"\(title)\" needs an amount greater than zero."
        case .invalidSplitAmount:
            return "Split amounts must be greater than zero."
        case .invalidSettlementAmount:
            return "Settle-up amounts must be greater than zero."
        case .invalidSettlementDirection:
            return "A member cannot settle up with themselves."
        }
    }
}

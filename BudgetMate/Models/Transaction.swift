import Foundation

extension BudgetMateSchemaV2.Transaction {
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

    var isSplit: Bool { !splits.isEmpty }

    var participantIds: [UUID] {
        guard isSplit else { return [createdByMemberId] }

        var ids: [UUID] = []
        for split in splits where !ids.contains(split.memberId) {
            ids.append(split.memberId)
        }
        return ids
    }

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

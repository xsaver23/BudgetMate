import Foundation
import SwiftData

/// One member's share of a split expense. A transaction with no splits is a
/// regular (non-split) transaction fully attributed to its payer.
@Model
final class TransactionSplit {
    var id: UUID
    var memberId: UUID
    var amount: Double
    var transaction: Transaction?

    init(id: UUID = UUID(), memberId: UUID, amount: Double, transaction: Transaction? = nil) {
        self.id = id
        self.memberId = memberId
        self.amount = max(0, amount)
        self.transaction = transaction
    }
}

extension TransactionSplit {
    func validateForSync() throws {
        guard amount > 0, amount.isFinite else {
            throw BudgetDataValidationError.invalidSplitAmount
        }
    }
}

enum SplitMethod: String, CaseIterable, Identifiable {
    case equally
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .equally: return "Equally"
        case .custom: return "Custom"
        }
    }
}

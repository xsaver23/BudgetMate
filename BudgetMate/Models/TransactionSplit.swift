import Foundation

extension BudgetMateSchemaV2.TransactionSplit {
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

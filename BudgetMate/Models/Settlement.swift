import Foundation

extension BudgetMateSchemaV2.Settlement {
    func validateForSync() throws {
        guard amount > 0, amount.isFinite else {
            throw BudgetDataValidationError.invalidSettlementAmount
        }

        guard fromMemberId != toMemberId else {
            throw BudgetDataValidationError.invalidSettlementDirection
        }
    }
}

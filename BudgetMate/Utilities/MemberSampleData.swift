import Foundation

enum MemberSampleData {
    // Legacy aliases kept temporarily while migration is in progress.
    static let userAId = BudgetSampleData.averyId
    static let userBId = BudgetSampleData.jordaniferId

    static let members: [BudgetMember] = BudgetSampleData.currentBudget.members
}

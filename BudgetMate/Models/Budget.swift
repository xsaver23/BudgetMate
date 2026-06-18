import Foundation

struct Budget: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let createdByUserId: UUID
    var members: [BudgetMember]
    let createdDate: Date

    init(
        id: UUID = UUID(),
        name: String,
        createdByUserId: UUID,
        members: [BudgetMember],
        createdDate: Date = .now
    ) {
        self.id = id
        self.name = name
        self.createdByUserId = createdByUserId
        self.members = members
        self.createdDate = createdDate
    }
}

struct BudgetInvite: Identifiable, Hashable {
    let id: UUID
    let budgetId: UUID
    let invitedByUserId: UUID
    let displayName: String
    let email: String
    let status: String
    let createdAt: Date

    var isPending: Bool {
        status == "pending"
    }
}

struct BudgetMembership: Identifiable, Hashable {
    let budgetId: UUID
    let userId: UUID
    let role: String
    let status: String

    var id: String {
        "\(budgetId.uuidString)-\(userId.uuidString)"
    }

    var isActive: Bool {
        status == "active"
    }

    func displayName(currentUserId: String) -> String {
        budgetId.uuidString == currentUserId ? "My Budget" : "Shared Budget"
    }
}

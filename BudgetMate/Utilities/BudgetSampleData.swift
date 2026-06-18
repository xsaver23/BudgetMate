import Foundation

enum BudgetSampleData {
    static let budgetId = UUID(uuidString: "C3C3C3C3-3333-3333-3333-C3C3C3C3C3C3")!
    static let averyId = UUID(uuidString: "A1A1A1A1-1111-1111-1111-A1A1A1A1A1A1")!
    static let jordaniferId = UUID(uuidString: "B2B2B2B2-2222-2222-2222-B2B2B2B2B2B2")!
    static let marcusId = UUID(uuidString: "D4D4D4D4-4444-4444-4444-D4D4D4D4D4D4")!
    static let priyaId = UUID(uuidString: "E5E5E5E5-5555-5555-5555-E5E5E5E5E5E5")!

    static let members: [BudgetMember] = [
        BudgetMember(
            id: averyId,
            displayName: "Avery",
            email: "avery@example.com",
            initials: "EF",
            color: "#3B82F6",
            role: .owner,
            inviteStatus: .active,
            joinedDate: .now
        ),
        BudgetMember(
            id: jordaniferId,
            displayName: "Jordanifer",
            email: "jordanifer@example.com",
            initials: "J",
            color: "#F97316",
            role: .member,
            inviteStatus: .active,
            joinedDate: .now
        ),
        BudgetMember(
            id: marcusId,
            displayName: "Marcus",
            email: "marcus@example.com",
            initials: "M",
            color: "#10B981",
            role: .member,
            inviteStatus: .active,
            joinedDate: .now
        ),
        BudgetMember(
            id: priyaId,
            displayName: "Priya",
            email: "priya@example.com",
            initials: "P",
            color: "#8B5CF6",
            role: .member,
            inviteStatus: .active,
            joinedDate: .now
        )
    ]

    static func householdMembers(owner: BudgetMember) -> [BudgetMember] {
        let demoMembers = members
            .filter { $0.id != averyId }
            .map {
                BudgetMember(
                    id: $0.id,
                    displayName: $0.displayName,
                    email: nil,
                    initials: $0.initials,
                    color: $0.color,
                    role: .member,
                    inviteStatus: .active,
                    joinedDate: $0.joinedDate,
                    createdDate: $0.createdDate
                )
            }

        let ownerMember = BudgetMember(
            id: owner.id,
            displayName: owner.displayName,
            email: owner.email,
            initials: owner.initials,
            color: owner.color,
            authUserId: owner.authUserId,
            role: .owner,
            inviteStatus: .active,
            joinedDate: owner.joinedDate,
            createdDate: owner.createdDate
        )

        return [ownerMember] + demoMembers
    }

    static let currentBudget = Budget(
        id: budgetId,
        name: "Household Budget",
        createdByUserId: averyId,
        members: members
    )

    static let monthlyBudget: Double = 4_800

    static let categoryBudgets: [TransactionCategory: Double] = [
        .rent: 2_400,
        .bills: 375,
        .subscription: 35,
        .food: 175,
        .groceries: 650,
        .health: 125,
        .household: 150,
        .gas: 150,
        .transportation: 120,
        .shopping: 350,
        .restaurant: 275,
        .entertainment: 150,
        .studentLoans: 0,
        .parking: 0,
        .date: 150,
        .vacation: 0,
        .gift: 75,
        .other: 200
    ]
}

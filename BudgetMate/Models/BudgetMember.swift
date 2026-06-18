import Foundation

struct BudgetMember: Identifiable, Codable, Hashable {
    let id: UUID
    let displayName: String
    let email: String?
    let initials: String
    let color: String
    let role: BudgetMemberRole
    let inviteStatus: InviteStatus
    let joinedDate: Date?
    let createdDate: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        email: String? = nil,
        initials: String,
        color: String,
        role: BudgetMemberRole = .member,
        inviteStatus: InviteStatus = .active,
        joinedDate: Date? = .now,
        createdDate: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.initials = initials
        self.color = color
        self.role = role
        self.inviteStatus = inviteStatus
        self.joinedDate = joinedDate
        self.createdDate = createdDate
    }

    init(
        id: UUID = UUID(),
        name: String,
        initials: String,
        colorHex: String,
        createdDate: Date = .now
    ) {
        self.init(
            id: id,
            displayName: name,
            email: nil,
            initials: initials,
            color: colorHex,
            role: .member,
            inviteStatus: .active,
            joinedDate: .now,
            createdDate: createdDate
        )
    }

    // Backward-compatible aliases while we migrate UI naming.
    var name: String { displayName }
    var colorHex: String { color }
}

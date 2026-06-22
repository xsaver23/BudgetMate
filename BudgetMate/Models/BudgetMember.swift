import Foundation

struct BudgetMember: Identifiable, Codable, Hashable {
    let id: UUID
    let displayName: String
    let email: String?
    let initials: String
    let color: String
    let authUserId: UUID?
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
        authUserId: UUID? = nil,
        role: BudgetMemberRole = .member,
        inviteStatus: InviteStatus = .active,
        joinedDate: Date? = .now,
        createdDate: Date = .now
    ) {
        let normalizedName = Self.normalizedDisplayName(displayName)
        self.id = id
        self.displayName = normalizedName
        self.email = Self.normalizedEmail(email)
        self.initials = Self.normalizedInitials(initials, displayName: normalizedName)
        self.color = color
        self.authUserId = authUserId
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
    var displayInitials: String { Self.initials(from: displayName) }

    static func normalizedDisplayName(_ displayName: String) -> String {
        let trimmed = displayName.withoutEmoji().trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Member" : trimmed
    }

    static func normalizedEmail(_ email: String?) -> String? {
        guard let email else { return nil }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedInitials(_ initials: String, displayName: String) -> String {
        let trimmed = initials.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != "?" {
            let safeInitials = trimmed.withoutEmoji()
            if !safeInitials.isEmpty {
                return String(safeInitials.prefix(2)).uppercased()
            }
        }

        return Self.initials(from: displayName)
    }

    static func initials(from displayName: String) -> String {
        let parts = displayName
            .withoutEmoji()
            .split(separator: " ")
            .filter { !$0.isEmpty }

        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
        }

        if let first = parts.first?.first {
            return String(first).uppercased()
        }

        return "?"
    }

    func validateForSync() throws {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BudgetDataValidationError.emptyMemberName
        }
        guard !displayName.containsEmoji else {
            throw BudgetDataValidationError.emptyMemberName
        }
    }
}

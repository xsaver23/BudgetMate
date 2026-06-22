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

    static func deduplicatedForBudget(_ members: [BudgetMember]) -> [BudgetMember] {
        var mergedMembers: [BudgetMember] = []

        for member in members {
            if let existingIndex = mergedMembers.firstIndex(where: { $0.representsSamePerson(as: member) }) {
                mergedMembers[existingIndex] = mergedMembers[existingIndex].mergedIdentity(with: member)
            } else {
                mergedMembers.append(member)
            }
        }

        return mergedMembers
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
            throw BudgetDataValidationError.invalidMemberNameEmoji
        }
    }

    private func representsSamePerson(as other: BudgetMember) -> Bool {
        if id == other.id {
            return true
        }

        if let authUserId,
           authUserId == other.authUserId || authUserId == other.id {
            return true
        }

        if let otherAuthUserId = other.authUserId,
           otherAuthUserId == id {
            return true
        }

        guard let email = Self.normalizedEmail(email),
              let otherEmail = Self.normalizedEmail(other.email) else {
            return false
        }

        return email == otherEmail
    }

    private func mergedIdentity(with other: BudgetMember) -> BudgetMember {
        let preferred = Self.preferredCanonicalMember(self, other)
        let secondary = preferred.id == id ? other : self
        let mergedRole: BudgetMemberRole = (role == .owner || other.role == .owner) ? .owner : preferred.role
        let mergedInviteStatus: InviteStatus = (inviteStatus == .active || other.inviteStatus == .active) ? .active : preferred.inviteStatus

        return BudgetMember(
            id: preferred.id,
            displayName: preferred.displayName,
            email: preferred.email ?? secondary.email,
            initials: BudgetMember.initials(from: preferred.displayName),
            color: preferred.color,
            authUserId: preferred.authUserId ?? secondary.authUserId,
            role: mergedRole,
            inviteStatus: mergedInviteStatus,
            joinedDate: preferred.joinedDate ?? secondary.joinedDate,
            createdDate: min(preferred.createdDate, secondary.createdDate)
        )
    }

    private static func preferredCanonicalMember(_ lhs: BudgetMember, _ rhs: BudgetMember) -> BudgetMember {
        let lhsScore = canonicalScore(lhs)
        let rhsScore = canonicalScore(rhs)

        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }

        return lhs.createdDate <= rhs.createdDate ? lhs : rhs
    }

    private static func canonicalScore(_ member: BudgetMember) -> Int {
        var score = 0
        if member.role == .owner { score += 100 }
        if member.inviteStatus == .active { score += 40 }
        if member.authUserId != nil { score += 20 }
        if member.joinedDate != nil { score += 10 }
        if member.email != nil { score += 5 }
        return score
    }
}

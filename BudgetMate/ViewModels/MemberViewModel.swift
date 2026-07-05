import Foundation

enum MemberMutationError: LocalizedError {
    case cannotDeleteLastMember
    case cannotDeleteLastOwner

    var errorDescription: String? {
        switch self {
        case .cannotDeleteLastMember:
            return "You cannot remove the last budget member."
        case .cannotDeleteLastOwner:
            return "You cannot remove the last owner. Assign another owner first."
        }
    }
}

struct MemberRemovalResult {
    let removedMemberIds: Set<UUID>
    let didReassignActiveMember: Bool
}

@MainActor
final class MemberViewModel: ObservableObject {
    @Published private(set) var currentBudget: Budget
    @Published private(set) var isProfileComplete: Bool
    @Published var members: [BudgetMember] {
        didSet {
            persistMembers()
            ensureActiveMemberIsValid()
        }
    }

    @Published var activeMemberId: UUID {
        didSet { persistActiveMemberId() }
    }

    private let activeMemberKey = "budgetmate.activeMemberId"
    private let profileCompletedKey = "budgetmate.profileCompleted"
    private var repository: BudgetRepository
    private let userDefaults: UserDefaults
    private var currentUserScopeId: String
    private var currentUserEmail: String?
    private let memberPalette = ["#3B82F6", "#F97316", "#10B981", "#8B5CF6", "#EF4444", "#06B6D4"]

    init(
        repository: BudgetRepository = LocalBudgetRepository(),
        userDefaults: UserDefaults = .standard,
        userScopeId: String = "local"
    ) {
        let loadedBudget = repository.loadCurrentBudget()
        let resolvedMembers = loadedBudget.members

        self.repository = repository
        self.currentBudget = loadedBudget
        self.members = resolvedMembers
        self.userDefaults = userDefaults
        self.currentUserScopeId = userScopeId
        self.currentUserEmail = nil
        self.isProfileComplete = userDefaults.bool(
            forKey: Self.profileCompletedKey(baseKey: profileCompletedKey, userScopeId: userScopeId)
        )

        if let storedId = userDefaults.string(forKey: Self.activeMemberKey(baseKey: activeMemberKey, userScopeId: userScopeId)),
           let uuid = UUID(uuidString: storedId),
           resolvedMembers.contains(where: { $0.id == uuid }) {
            activeMemberId = uuid
        } else {
            activeMemberId = resolvedMembers.first?.id ?? UUID()
        }
    }

    var budgetName: String { currentBudget.name }
    var syncMode: BudgetSyncMode { repository.syncMode }

    var activeMember: BudgetMember {
        members.first(where: { $0.id == activeMemberId }) ?? members.first ?? BudgetMember(
            name: "Unknown User",
            initials: "?",
            colorHex: "#9CA3AF"
        )
    }

    /// Adds any demo members that are not already in the budget (matched by id).
    func mergeDemoMembers(_ demoMembers: [BudgetMember]) {
        var updated = members
        for demo in demoMembers where !updated.contains(where: { $0.id == demo.id }) {
            updated.append(demo)
        }
        guard updated.count != members.count else { return }
        members = updated
    }

    func replaceMembers(with cloudMembers: [BudgetMember]) {
        guard !cloudMembers.isEmpty else { return }
        let normalizedMembers = BudgetMember.deduplicatedForBudget(cloudMembers)
        let sortedMembers = normalizedMembers.sorted { lhs, rhs in
            if lhs.role != rhs.role {
                return lhs.role == .owner
            }
            return lhs.createdDate < rhs.createdDate
        }
        if sortedMembers != members {
            members = sortedMembers
        }
        if let signedInMember = signedInMember(in: sortedMembers) {
            activeMemberId = signedInMember.id
        }
    }

    func switchUser(to userScopeId: String, email: String?) {
        currentUserEmail = email
        guard currentUserScopeId != userScopeId else {
            if let signedInMember = signedInMember(in: members) {
                activeMemberId = signedInMember.id
            }
            return
        }
        currentUserScopeId = userScopeId
        repository = LocalBudgetRepository(
            userDefaults: userDefaults,
            userScopeId: userScopeId,
            fallbackBudget: Self.defaultBudget(userScopeId: userScopeId, email: email)
        )

        var loadedBudget = repository.loadCurrentBudget()
        let fallbackBudget = Self.defaultBudget(userScopeId: userScopeId, email: email)
        if Self.shouldReplaceSampleBudget(loadedBudget, forUserScopeId: userScopeId) {
            loadedBudget = fallbackBudget
            repository.saveCurrentBudget(loadedBudget)
        }
        currentBudget = loadedBudget
        members = loadedBudget.members
        isProfileComplete = userDefaults.bool(forKey: profileCompletedKey(for: userScopeId))

        if let storedId = userDefaults.string(forKey: activeMemberKey(for: userScopeId)),
           let uuid = UUID(uuidString: storedId),
           members.contains(where: { $0.id == uuid }) {
            activeMemberId = uuid
        } else {
            activeMemberId = members.first?.id ?? UUID()
        }

        if let signedInMember = signedInMember(in: members) {
            activeMemberId = signedInMember.id
        }
    }

    func profileMember(userScopeId: String, email: String?) -> BudgetMember? {
        signedInMember(in: members, userScopeId: userScopeId, email: email)
    }

    @discardableResult
    func restoreProfileIfPresent(from cloudMembers: [BudgetMember], userScopeId: String, email: String?) -> Bool {
        let normalizedMembers = BudgetMember.deduplicatedForBudget(cloudMembers)
        guard let cloudProfile = signedInMember(in: normalizedMembers, userScopeId: userScopeId, email: email) else {
            return false
        }

        replaceMembers(with: normalizedMembers)
        activeMemberId = cloudProfile.id
        isProfileComplete = true
        persistProfileCompleted()
        return true
    }

    @discardableResult
    func inviteMember(displayName: String, email: String?) -> BudgetMember? {
        guard let newMember = makeInvitedMember(displayName: displayName, email: email) else {
            return nil
        }

        members.append(newMember)
        return newMember
    }

    func makeInvitedMember(displayName: String, email: String?) -> BudgetMember? {
        let trimmedName = BudgetMember.normalizedDisplayName(displayName)
        guard !trimmedName.isEmpty else { return nil }
        guard !displayName.containsEmoji else { return nil }

        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = (trimmedEmail?.isEmpty == true) ? nil : trimmedEmail?.lowercased()

        return BudgetMember(
            displayName: trimmedName,
            email: normalizedEmail,
            initials: BudgetMember.initials(from: trimmedName),
            color: nextColor(),
            role: .member,
            inviteStatus: .invited,
            joinedDate: nil
        )
    }

    func makeSharedOwnerMember(userScopeId: String, email: String?) -> BudgetMember {
        let source = profileMember(userScopeId: userScopeId, email: email) ?? activeMember
        return BudgetMember(
            displayName: source.displayName,
            email: source.email ?? email,
            initials: source.displayInitials,
            color: source.color,
            authUserId: UUID(uuidString: userScopeId) ?? source.authUserId,
            role: .owner,
            inviteStatus: .active,
            joinedDate: source.joinedDate ?? .now,
            createdDate: .now
        )
    }

    func completeProfile(displayName: String) {
        let trimmedName = BudgetMember.normalizedDisplayName(displayName)
        guard !trimmedName.isEmpty else { return }
        guard !displayName.containsEmoji else { return }

        let current = activeMember
        let profileMember = BudgetMember(
            id: current.id,
            displayName: trimmedName,
            email: current.email,
            initials: BudgetMember.initials(from: trimmedName),
            color: current.color,
            authUserId: UUID(uuidString: currentUserScopeId) ?? current.authUserId,
            role: .owner,
            inviteStatus: .active,
            joinedDate: current.joinedDate ?? .now,
            createdDate: current.createdDate
        )

        var updatedMembers = members
        if let index = updatedMembers.firstIndex(where: { $0.id == current.id }) {
            updatedMembers[index] = profileMember
        } else {
            updatedMembers.insert(profileMember, at: 0)
        }

        activeMemberId = profileMember.id
        members = updatedMembers
        isProfileComplete = true
        persistProfileCompleted()
    }

    @discardableResult
    func updateProfileName(_ displayName: String, userScopeId: String) -> Bool {
        let trimmedName = BudgetMember.normalizedDisplayName(displayName)
        guard !trimmedName.isEmpty else { return false }
        guard !displayName.containsEmoji else { return false }

        let profileId = UUID(uuidString: userScopeId)
        let normalizedEmail = Self.normalizedEmail(currentUserEmail)
        guard let index = members.firstIndex(where: { member in
            if let profileId, member.id == profileId {
                return true
            }

            guard let normalizedEmail else { return false }
            return Self.normalizedEmail(member.email) == normalizedEmail
        }) else {
            return false
        }

        let current = members[index]
        let updatedProfile = BudgetMember(
            id: current.id,
            displayName: trimmedName,
            email: current.email,
            initials: BudgetMember.initials(from: trimmedName),
            color: current.color,
            authUserId: current.authUserId,
            role: current.role,
            inviteStatus: current.inviteStatus,
            joinedDate: current.joinedDate,
            createdDate: current.createdDate
        )

        var updatedMembers = members
        updatedMembers[index] = updatedProfile
        members = updatedMembers
        return true
    }

    @discardableResult
    func removeMembers(at offsets: IndexSet) throws -> MemberRemovalResult {
        let idsToRemove = Set(offsets.compactMap { members[safe: $0]?.id })
        let remainingMembers = members.filter { !idsToRemove.contains($0.id) }

        if remainingMembers.isEmpty {
            throw MemberMutationError.cannotDeleteLastMember
        }

        if !remainingMembers.contains(where: { $0.role == .owner }) {
            throw MemberMutationError.cannotDeleteLastOwner
        }

        let activeMemberRemoved = idsToRemove.contains(activeMemberId)
        if activeMemberRemoved {
            activeMemberId = remainingMembers[0].id
        }

        members = remainingMembers
        return MemberRemovalResult(
            removedMemberIds: idsToRemove,
            didReassignActiveMember: activeMemberRemoved
        )
    }

    private func persistActiveMemberId() {
        userDefaults.set(activeMemberId.uuidString, forKey: activeMemberKey(for: currentUserScopeId))
    }

    private func persistProfileCompleted() {
        userDefaults.set(isProfileComplete, forKey: profileCompletedKey(for: currentUserScopeId))
    }

    private func persistMembers() {
        currentBudget.members = members
        repository.saveCurrentBudget(currentBudget)
    }

    private func nextColor() -> String {
        let index = members.count % memberPalette.count
        return memberPalette[index]
    }

    private func ensureActiveMemberIsValid() {
        if let signedInMember = signedInMember(in: members),
           activeMemberId != signedInMember.id {
            activeMemberId = signedInMember.id
        } else if !members.contains(where: { $0.id == activeMemberId }),
                  let firstMemberId = members.first?.id {
            activeMemberId = firstMemberId
        }
    }

    private func signedInMember(in members: [BudgetMember]) -> BudgetMember? {
        signedInMember(in: members, userScopeId: currentUserScopeId, email: currentUserEmail)
    }

    private func signedInMember(in members: [BudgetMember], userScopeId: String, email: String?) -> BudgetMember? {
        if let userId = UUID(uuidString: userScopeId),
           let member = members.first(where: { $0.id == userId || $0.authUserId == userId }) {
            return member
        }

        guard let normalizedEmail = Self.normalizedEmail(email) else { return nil }
        return members.first { Self.normalizedEmail($0.email) == normalizedEmail }
    }

    private static func normalizedEmail(_ email: String?) -> String? {
        let normalized = email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }

    private func activeMemberKey(for userScopeId: String) -> String {
        Self.activeMemberKey(baseKey: activeMemberKey, userScopeId: userScopeId)
    }

    private func profileCompletedKey(for userScopeId: String) -> String {
        Self.profileCompletedKey(baseKey: profileCompletedKey, userScopeId: userScopeId)
    }

    private static func activeMemberKey(baseKey: String, userScopeId: String) -> String {
        "\(baseKey).\(userScopeId)"
    }

    private static func profileCompletedKey(baseKey: String, userScopeId: String) -> String {
        "\(baseKey).\(userScopeId)"
    }

    private static func defaultBudget(userScopeId: String, email: String?) -> Budget {
        let memberId = UUID(uuidString: userScopeId) ?? UUID()
        let displayName = defaultDisplayName(from: email)
        let member = BudgetMember(
            id: memberId,
            displayName: displayName,
            email: email,
            initials: BudgetMember.initials(from: displayName),
            color: "#3B82F6",
            authUserId: memberId,
            role: .owner,
            inviteStatus: .active,
            joinedDate: .now
        )

        return Budget(
            id: memberId,
            name: "My Budget",
            createdByUserId: memberId,
            members: [member]
        )
    }

    private static func shouldReplaceSampleBudget(_ budget: Budget, forUserScopeId userScopeId: String) -> Bool {
        guard let userId = UUID(uuidString: userScopeId) else { return false }
        let memberIds = Set(budget.members.map(\.id))
        let sampleIds = Set(BudgetSampleData.members.map(\.id))
        return memberIds == sampleIds && !memberIds.contains(userId)
    }

    private static func defaultDisplayName(from email: String?) -> String {
        let localPart = email?
            .split(separator: "@")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let localPart, !localPart.isEmpty else {
            return "Me"
        }

        return localPart
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { part in part.prefix(1).uppercased() + part.dropFirst() }
            .joined(separator: " ")
    }

}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

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

struct MemberCloudSyncToken: Equatable {
    let budgetScopeId: String
    let revision: Int
}

@MainActor
final class MemberViewModel: ObservableObject {
    @Published private(set) var currentBudget: Budget
    @Published private(set) var isProfileComplete: Bool
    @Published var members: [BudgetMember] {
        didSet {
            persistMembers()
            ensureActiveMemberIsValid()
            if !isApplyingScopedMembers {
                markMembersDirty()
            }
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
    private var currentBudgetScopeId: String
    private var currentUserEmail: String?
    private var isApplyingScopedMembers = false
    private let membersCloudDirtyKey = "budgetmate.membersCloudDirty"
    private let membersCloudRevisionKey = "budgetmate.membersCloudRevision"
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
        self.currentBudgetScopeId = userScopeId
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

    var pendingCloudSyncToken: MemberCloudSyncToken? {
        guard userDefaults.bool(forKey: membersDirtyKey(for: currentBudgetScopeId)) else {
            return nil
        }
        return MemberCloudSyncToken(
            budgetScopeId: currentBudgetScopeId,
            revision: userDefaults.integer(forKey: membersRevisionKey(for: currentBudgetScopeId))
        )
    }

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
        let sortedMembers = Self.sortedMembers(cloudMembers)
        if sortedMembers != members {
            applyScopedMembers(sortedMembers)
        }
        markMembersClean(for: currentBudgetScopeId)
        if let signedInMember = signedInMember(in: sortedMembers) {
            activeMemberId = signedInMember.id
        }
    }

    func replaceMembersWithLocalChanges(_ localMembers: [BudgetMember]) {
        let sortedMembers = Self.sortedMembers(localMembers)
        guard !sortedMembers.isEmpty, sortedMembers != members else { return }
        members = sortedMembers
    }

    func switchUser(to userScopeId: String, budgetScopeId: String? = nil, email: String?) {
        let resolvedBudgetScopeId = budgetScopeId ?? userScopeId
        currentUserEmail = email
        guard currentUserScopeId != userScopeId || currentBudgetScopeId != resolvedBudgetScopeId else {
            if let signedInMember = signedInMember(in: members) {
                activeMemberId = signedInMember.id
            }
            return
        }
        currentUserScopeId = userScopeId
        currentBudgetScopeId = resolvedBudgetScopeId
        repository = LocalBudgetRepository(
            userDefaults: userDefaults,
            userScopeId: resolvedBudgetScopeId,
            fallbackBudget: Self.defaultBudget(
                userScopeId: userScopeId,
                budgetScopeId: resolvedBudgetScopeId,
                email: email
            )
        )

        var loadedBudget = repository.loadCurrentBudget()
        let fallbackBudget = Self.defaultBudget(
            userScopeId: userScopeId,
            budgetScopeId: resolvedBudgetScopeId,
            email: email
        )
        if Self.shouldReplaceSampleBudget(loadedBudget, forUserScopeId: userScopeId) ||
            loadedBudget.id.uuidString != resolvedBudgetScopeId {
            loadedBudget = fallbackBudget
            repository.saveCurrentBudget(loadedBudget)
        }
        currentBudget = loadedBudget
        applyScopedMembers(loadedBudget.members)
        isProfileComplete = userDefaults.bool(forKey: profileCompletedKey(for: userScopeId))

        if let storedId = userDefaults.string(forKey: activeMemberKey(for: resolvedBudgetScopeId)),
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
        userDefaults.set(activeMemberId.uuidString, forKey: activeMemberKey(for: currentBudgetScopeId))
    }

    private func persistProfileCompleted() {
        userDefaults.set(isProfileComplete, forKey: profileCompletedKey(for: currentUserScopeId))
    }

    private func persistMembers() {
        currentBudget.members = members
        repository.saveCurrentBudget(currentBudget)
    }

    func markCloudSyncSucceeded(_ token: MemberCloudSyncToken) {
        let revisionKey = membersRevisionKey(for: token.budgetScopeId)
        guard userDefaults.integer(forKey: revisionKey) == token.revision else {
            return
        }
        markMembersClean(for: token.budgetScopeId)
    }

    private func applyScopedMembers(_ scopedMembers: [BudgetMember]) {
        isApplyingScopedMembers = true
        members = scopedMembers
        isApplyingScopedMembers = false
    }

    private func markMembersDirty() {
        let revisionKey = membersRevisionKey(for: currentBudgetScopeId)
        userDefaults.set(userDefaults.integer(forKey: revisionKey) + 1, forKey: revisionKey)
        userDefaults.set(true, forKey: membersDirtyKey(for: currentBudgetScopeId))
    }

    private func markMembersClean(for budgetScopeId: String) {
        userDefaults.set(false, forKey: membersDirtyKey(for: budgetScopeId))
    }

    private func membersDirtyKey(for budgetScopeId: String) -> String {
        "\(membersCloudDirtyKey).\(budgetScopeId)"
    }

    private func membersRevisionKey(for budgetScopeId: String) -> String {
        "\(membersCloudRevisionKey).\(budgetScopeId)"
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

    private static func sortedMembers(_ members: [BudgetMember]) -> [BudgetMember] {
        BudgetMember.deduplicatedForBudget(members).sorted { lhs, rhs in
            if lhs.role != rhs.role {
                return lhs.role == .owner
            }
            return lhs.createdDate < rhs.createdDate
        }
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

    private static func defaultBudget(userScopeId: String, budgetScopeId: String, email: String?) -> Budget {
        let memberId = UUID(uuidString: userScopeId) ?? UUID()
        let budgetId = UUID(uuidString: budgetScopeId) ?? memberId
        let displayName = defaultDisplayName(from: email)
        let member = BudgetMember(
            id: memberId,
            displayName: displayName,
            email: email,
            initials: BudgetMember.initials(from: displayName),
            color: "#3B82F6",
            authUserId: memberId,
            role: budgetScopeId == userScopeId ? .owner : .member,
            inviteStatus: .active,
            joinedDate: .now
        )

        return Budget(
            id: budgetId,
            name: budgetScopeId == userScopeId ? "My Budget" : "Shared Budget",
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

import Foundation

struct RecordMutationDecision: Equatable {
    enum Reason: Equatable {
        case personalBudget
        case householdOwner
        case restrictedSharedMember
    }

    let reason: Reason

    var isAllowed: Bool {
        reason != .restrictedSharedMember
    }

    var readOnlyMessage: String? {
        guard !isAllowed else { return nil }
        return "Only the household owner can edit or delete shared records right now."
    }
}

enum SharedRecordMutationCapability {
    static func decision(
        currentUserScopeId: String,
        activeBudgetScopeId: String,
        recordBudgetScopeId: String,
        members: [BudgetMember]
    ) -> RecordMutationDecision {
        guard activeBudgetScopeId == recordBudgetScopeId else {
            return RecordMutationDecision(reason: .restrictedSharedMember)
        }

        guard recordBudgetScopeId != currentUserScopeId else {
            return RecordMutationDecision(reason: .personalBudget)
        }

        guard let userId = UUID(uuidString: currentUserScopeId) else {
            return RecordMutationDecision(reason: .restrictedSharedMember)
        }

        let authenticatedMembers = members.filter {
            $0.authUserId == userId || ($0.authUserId == nil && $0.id == userId)
        }
        guard authenticatedMembers.count == 1,
              let authenticatedMember = authenticatedMembers.first,
              authenticatedMember.role == .owner,
              authenticatedMember.inviteStatus == .active else {
            return RecordMutationDecision(reason: .restrictedSharedMember)
        }

        return RecordMutationDecision(reason: .householdOwner)
    }
}

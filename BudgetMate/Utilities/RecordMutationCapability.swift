import Foundation

/// Gate C is intentionally compiled off until the additive server migration
/// has been applied, verified, and all participating clients have been
/// upgraded. Shared-data UI must remain read-only while it is false.
enum SharedDataSafetyGate {
    static let isEnabled = false
    static let readOnlyMessage = "Shared-data editing is temporarily unavailable while household safety is being enabled."
}

struct RecordMutationDecision: Equatable {
    enum Reason: Equatable {
        case personalBudget
        case householdOwner
        case householdCreator
        case restrictedSharedMember
        case sharedDataSafetyDisabled
    }

    let reason: Reason

    var isAllowed: Bool {
        switch reason {
        case .personalBudget, .householdOwner, .householdCreator:
            return true
        case .restrictedSharedMember, .sharedDataSafetyDisabled:
            return false
        }
    }

    var readOnlyMessage: String? {
        guard !isAllowed else { return nil }
        if reason == .sharedDataSafetyDisabled {
            return SharedDataSafetyGate.readOnlyMessage
        }
        return "Only the household owner or the authenticated record creator can edit or delete shared records right now."
    }
}

enum SharedRecordMutationCapability {
    static func decision(
        currentUserScopeId: String,
        activeBudgetScopeId: String,
        recordBudgetScopeId: String,
        members: [BudgetMember],
        recordCreatorUserId: UUID? = nil,
        serverGateEnabled: Bool = SharedDataSafetyGate.isEnabled
    ) -> RecordMutationDecision {
        guard activeBudgetScopeId == recordBudgetScopeId else {
            return RecordMutationDecision(reason: .restrictedSharedMember)
        }

        guard recordBudgetScopeId != currentUserScopeId else {
            return RecordMutationDecision(reason: .personalBudget)
        }

        guard serverGateEnabled else {
            return RecordMutationDecision(reason: .sharedDataSafetyDisabled)
        }

        guard let userId = UUID(uuidString: currentUserScopeId) else {
            return RecordMutationDecision(reason: .restrictedSharedMember)
        }

        let authenticatedMembers = members.filter {
            $0.authUserId == userId || ($0.authUserId == nil && $0.id == userId)
        }
        guard authenticatedMembers.count == 1,
              let authenticatedMember = authenticatedMembers.first,
              authenticatedMember.inviteStatus == .active else {
            return RecordMutationDecision(reason: .restrictedSharedMember)
        }

        if authenticatedMember.role == .owner {
            return RecordMutationDecision(reason: .householdOwner)
        }
        if recordCreatorUserId == userId {
            return RecordMutationDecision(reason: .householdCreator)
        }
        return RecordMutationDecision(reason: .restrictedSharedMember)
    }
}

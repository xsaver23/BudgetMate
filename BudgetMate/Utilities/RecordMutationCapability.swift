import Foundation

/// A bounded Gate C configuration. The app only activates shared-data writes
/// when the server readiness marker, Gate C, and the money bridge are all
/// deliberately enabled in the build configuration. This keeps ordinary
/// builds and partial rollout configurations fail-closed.
struct GateCClientRolloutConfiguration: Equatable {
    enum State: Equatable {
        case disabled
        case enabled
        case inconsistent
    }

    static let serverReadyKey = "BUDGETMATE_GATE_C_SERVER_READY"
    static let sharedDataSafetyKey = "BUDGETMATE_GATE_C_ENABLED"
    static let moneyServerBridgeKey = "BUDGETMATE_MONEY_SERVER_BRIDGE_ENABLED"

    let state: State

    init(values: [String: String]) {
        let values = [
            Self.serverReadyKey,
            Self.sharedDataSafetyKey,
            Self.moneyServerBridgeKey
        ].map { Self.activationValue(values[$0]) }

        if values.allSatisfy({ $0 == .enabled }) {
            state = .enabled
        } else if values.allSatisfy({ $0 == .disabled }) {
            state = .disabled
        } else {
            state = .inconsistent
        }
    }

    var isEnabled: Bool {
        state == .enabled
    }

    var disabledMessage: String {
        switch state {
        case .disabled:
            return "Shared-data editing is temporarily unavailable while household safety is being enabled."
        case .inconsistent:
            return "Shared-data editing is unavailable because this build's Gate C rollout configuration is incomplete. Install a correctly configured build."
        case .enabled:
            return "Shared-data editing is temporarily unavailable."
        }
    }

    static var current: Self {
        let info = Bundle.main.infoDictionary ?? [:]
        return Self(values: [
            serverReadyKey: info[serverReadyKey] as? String ?? "",
            sharedDataSafetyKey: info[sharedDataSafetyKey] as? String ?? "",
            moneyServerBridgeKey: info[moneyServerBridgeKey] as? String ?? ""
        ])
    }

    private enum ActivationValue {
        case enabled
        case disabled
        case invalid
    }

    private static func activationValue(_ rawValue: String?) -> ActivationValue {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "YES":
            return .enabled
        case "", "NO", .none:
            return .disabled
        default:
            return .invalid
        }
    }
}

/// Gate C is intentionally off until the additive server migration has been
/// applied, verified, and the three release configuration markers agree.
enum SharedDataSafetyGate {
    static var isEnabled: Bool { isEnabled(configuration: .current) }
    static var readOnlyMessage: String { GateCClientRolloutConfiguration.current.disabledMessage }

    static func isEnabled(configuration: GateCClientRolloutConfiguration) -> Bool {
        configuration.isEnabled
    }
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

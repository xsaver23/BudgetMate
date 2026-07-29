import Foundation

struct RestrictedDestructiveAction: Equatable {
    let title: String
    let message: String
    let accessibilityIdentifier: String
    let isEnabled: Bool

    private init(
        title: String,
        message: String,
        accessibilityIdentifier: String
    ) {
        self.title = title
        self.message = message
        self.accessibilityIdentifier = accessibilityIdentifier
        isEnabled = false
    }

    static func unavailable(
        title: String,
        message: String,
        accessibilityIdentifier: String
    ) -> RestrictedDestructiveAction {
        RestrictedDestructiveAction(
            title: title,
            message: message,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}

enum DestructiveActionGuardrails {
    static let leaveSharedBudget = RestrictedDestructiveAction.unavailable(
        title: "Leave Shared Budget",
        message: "Leaving a shared budget is temporarily unavailable in this beta while household history protections are completed.",
        accessibilityIdentifier: "settings.leaveSharedBudgetUnavailable"
    )

    static let inviteCreation = RestrictedDestructiveAction.unavailable(
        title: "Invite Members",
        message: "Creating or delivering household invites is temporarily unavailable in this beta.",
        accessibilityIdentifier: "budgetMembers.invitesUnavailable"
    )

    static let clearAll = RestrictedDestructiveAction.unavailable(
        title: "Clear All Transactions",
        message: "Clear All is temporarily unavailable while BudgetMate adds an atomic, recoverable version that protects transaction and settle-up history.",
        accessibilityIdentifier: "settings.clearAllUnavailable"
    )

    static let memberRemovalSummary = "Member and invite removal is temporarily unavailable while BudgetMate adds a history-safe member lifecycle."

    static func memberRemoval(for member: BudgetMember) -> RestrictedDestructiveAction {
        if member.role == .owner {
            return .unavailable(
                title: "Remove \(member.displayName)",
                message: "The budget owner cannot be removed.",
                accessibilityIdentifier: "budgetMembers.ownerRemovalUnavailable.\(member.id.uuidString)"
            )
        }

        if member.inviteStatus == .active || member.authUserId != nil {
            return .unavailable(
                title: "Remove \(member.displayName)",
                message: "Accepted member removal is temporarily unavailable to protect shared transaction history.",
                accessibilityIdentifier: "budgetMembers.acceptedRemovalUnavailable.\(member.id.uuidString)"
            )
        }

        return .unavailable(
            title: "Cancel invite for \(member.displayName)",
            message: "Invite cancellation is temporarily unavailable while BudgetMate adds a history-safe member lifecycle.",
            accessibilityIdentifier: "budgetMembers.inviteCancellationUnavailable.\(member.id.uuidString)"
        )
    }
}

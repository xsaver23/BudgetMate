import Foundation

enum BudgetMemberRole: String, Codable, CaseIterable, Identifiable {
    case owner
    case member

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

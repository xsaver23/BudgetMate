import Foundation

enum InviteStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case invited
    case pending

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

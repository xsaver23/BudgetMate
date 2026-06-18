import SwiftUI

enum CategoryColor {
    static func color(for category: TransactionCategory) -> Color {
        switch category {
        case .food:
            return .orange
        case .restaurant:
            return .brown
        case .groceries:
            return .mint
        case .rent:
            return .indigo
        case .subscription:
            return .teal
        case .health:
            return .red
        case .household:
            return .blue
        case .gift:
            return .pink
        case .studentLoans:
            return .purple
        case .date:
            return .pink
        case .vacation:
            return .cyan
        case .parking:
            return .gray
        case .gas:
            return .yellow
        case .transportation:
            return .cyan
        case .shopping:
            return .pink
        case .entertainment:
            return .purple
        case .bills:
            return .red
        case .salary:
            return .green
        case .refund:
            return .mint
        case .work:
            return .blue
        case .eTransfer:
            return .teal
        case .other:
            return .gray
        default:
            return customColor(for: category.rawValue)
        }
    }

    private static func customColor(for rawValue: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .cyan]
        let hash = rawValue.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}

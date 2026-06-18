import Foundation

enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case cash
    case card
    case paypal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cash:
            return "Cash"
        case .card:
            return "Card"
        case .paypal:
            return "Paypal"
        }
    }
}

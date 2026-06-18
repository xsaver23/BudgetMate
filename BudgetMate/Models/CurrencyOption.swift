import Foundation

enum CurrencyOption: String, CaseIterable, Identifiable {
    case usd = "USD"
    case cad = "CAD"
    case eur = "EUR"
    case gbp = "GBP"
    case aud = "AUD"
    case php = "PHP"
    case jpy = "JPY"

    var id: String { code }
    var code: String { rawValue }

    var displayName: String {
        switch self {
        case .usd: return "US Dollar"
        case .cad: return "Canadian Dollar"
        case .eur: return "Euro"
        case .gbp: return "British Pound"
        case .aud: return "Australian Dollar"
        case .php: return "Philippine Peso"
        case .jpy: return "Japanese Yen"
        }
    }

    var symbol: String {
        switch self {
        case .usd: return "$"
        case .cad: return "CA$"
        case .eur: return "€"
        case .gbp: return "£"
        case .aud: return "A$"
        case .php: return "₱"
        case .jpy: return "¥"
        }
    }

    var pickerLabel: String {
        "\(code) - \(displayName) (\(symbol))"
    }

    static func normalizedCode(_ code: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return CurrencyOption(rawValue: normalized)?.code ?? CurrencyOption.usd.code
    }

    static func symbol(for code: String) -> String {
        CurrencyOption(rawValue: normalizedCode(code))?.symbol ?? CurrencyOption.usd.symbol
    }

    static func code(forLegacySymbol symbol: String?) -> String {
        switch symbol?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "CA$":
            return CurrencyOption.cad.code
        case "€":
            return CurrencyOption.eur.code
        case "£":
            return CurrencyOption.gbp.code
        case "A$":
            return CurrencyOption.aud.code
        case "₱":
            return CurrencyOption.php.code
        case "¥":
            return CurrencyOption.jpy.code
        default:
            return CurrencyOption.usd.code
        }
    }
}

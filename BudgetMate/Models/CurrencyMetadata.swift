import Foundation

/// The versioned currency facts used by the exact-money domain.
///
/// This catalog intentionally contains exactly the currencies currently
/// selectable by BudgetMate. Fraction digits are derived from the code and
/// are never accepted as an independent value.
struct CurrencyMetadata: Equatable, Hashable, Identifiable, Sendable {
    static let catalogVersion = 1

    let code: String
    let displayName: String
    let symbol: String
    let fractionDigits: Int

    var id: String { code }

    /// The symbol used by selectors and by the currency's standard metadata.
    /// Ordinary CAD amount formatting deliberately overrides this with `$`.
    var ordinaryDisplaySymbol: String {
        code == "CAD" ? "$" : symbol
    }

    static let supported: [CurrencyMetadata] = [
        CurrencyMetadata(
            code: "USD",
            displayName: "US Dollar",
            symbol: "$",
            fractionDigits: 2
        ),
        CurrencyMetadata(
            code: "CAD",
            displayName: "Canadian Dollar",
            symbol: "CA$",
            fractionDigits: 2
        ),
        CurrencyMetadata(
            code: "EUR",
            displayName: "Euro",
            symbol: "€",
            fractionDigits: 2
        ),
        CurrencyMetadata(
            code: "GBP",
            displayName: "British Pound",
            symbol: "£",
            fractionDigits: 2
        ),
        CurrencyMetadata(
            code: "AUD",
            displayName: "Australian Dollar",
            symbol: "A$",
            fractionDigits: 2
        ),
        CurrencyMetadata(
            code: "PHP",
            displayName: "Philippine Peso",
            symbol: "₱",
            fractionDigits: 2
        ),
        CurrencyMetadata(
            code: "JPY",
            displayName: "Japanese Yen",
            symbol: "¥",
            fractionDigits: 0
        )
    ]

    static var supportedCodes: [String] {
        supported.map(\.code)
    }

    init(code: String) throws {
        let normalized = Self.normalize(code)
        guard let metadata = Self.supported.first(where: { $0.code == normalized }) else {
            throw MoneyDomainError.unsupportedCurrencyCode(code)
        }
        self = metadata
    }

    static func metadata(for code: String) throws -> CurrencyMetadata {
        try CurrencyMetadata(code: code)
    }

    static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func isSupported(_ code: String) -> Bool {
        let normalized = normalize(code)
        return supported.contains { $0.code == normalized }
    }

    private init(
        code: String,
        displayName: String,
        symbol: String,
        fractionDigits: Int
    ) {
        self.code = code
        self.displayName = displayName
        self.symbol = symbol
        self.fractionDigits = fractionDigits
    }
}

enum MoneyDomainError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedCurrencyCode(String)
    case currencyMismatch(expected: String, actual: String)
    case arithmeticOverflow(operation: String)
    case emptyAllocation
    case duplicateParticipant(UUID)
    case payerNotParticipant(UUID)

    var errorDescription: String? {
        switch self {
        case .unsupportedCurrencyCode(let code):
            return "Unsupported currency code: \(code)."
        case .currencyMismatch(let expected, let actual):
            return "Currency mismatch: expected \(expected), received \(actual)."
        case .arithmeticOverflow(let operation):
            return "Money arithmetic overflow during \(operation)."
        case .emptyAllocation:
            return "At least one participant is required for an allocation."
        case .duplicateParticipant(let id):
            return "Allocation participant \(id.uuidString) appears more than once."
        case .payerNotParticipant(let id):
            return "The payer \(id.uuidString) must be one of the participants."
        }
    }
}

enum MoneyParsingError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedCurrencyCode(String)
    case malformedInput
    case excessFractionPrecision(currencyCode: String, maximum: Int)
    case overflow

    var errorDescription: String? {
        switch self {
        case .unsupportedCurrencyCode(let code):
            return "Unsupported currency code: \(code)."
        case .malformedInput:
            return "The amount is not a valid localized currency value."
        case .excessFractionPrecision(_, let maximum):
            return "The amount has more than \(maximum) fractional digits."
        case .overflow:
            return "The amount does not fit in the exact-money range."
        }
    }
}

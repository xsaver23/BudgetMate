import Foundation

struct Money: Codable, Equatable, Hashable, Sendable {
    let minorUnits: Int64
    let currencyCode: String

    init(minorUnits: Int64, currencyCode: String) throws {
        let metadata = try CurrencyMetadata(code: currencyCode)
        self.minorUnits = minorUnits
        self.currencyCode = metadata.code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            minorUnits: container.decode(Int64.self, forKey: .minorUnits),
            currencyCode: container.decode(String.self, forKey: .currencyCode)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(minorUnits, forKey: .minorUnits)
        try container.encode(currencyCode, forKey: .currencyCode)
    }

    func adding(_ other: Money) throws -> Money {
        try requireSameCurrency(as: other)
        let result = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !result.overflow else {
            throw MoneyDomainError.arithmeticOverflow(operation: "addition")
        }
        return try Money(minorUnits: result.partialValue, currencyCode: currencyCode)
    }

    func subtracting(_ other: Money) throws -> Money {
        try requireSameCurrency(as: other)
        let result = minorUnits.subtractingReportingOverflow(other.minorUnits)
        guard !result.overflow else {
            throw MoneyDomainError.arithmeticOverflow(operation: "subtraction")
        }
        return try Money(minorUnits: result.partialValue, currencyCode: currencyCode)
    }

    func negated() throws -> Money {
        let result = Int64.zero.subtractingReportingOverflow(minorUnits)
        guard !result.overflow else {
            throw MoneyDomainError.arithmeticOverflow(operation: "negation")
        }
        return try Money(minorUnits: result.partialValue, currencyCode: currencyCode)
    }

    func multiplied(by multiplier: Int64) throws -> Money {
        let result = minorUnits.multipliedReportingOverflow(by: multiplier)
        guard !result.overflow else {
            throw MoneyDomainError.arithmeticOverflow(operation: "multiplication")
        }
        return try Money(minorUnits: result.partialValue, currencyCode: currencyCode)
    }

    func compare(to other: Money) throws -> ComparisonResult {
        try requireSameCurrency(as: other)
        if minorUnits < other.minorUnits { return .orderedAscending }
        if minorUnits > other.minorUnits { return .orderedDescending }
        return .orderedSame
    }

    func isLess(than other: Money) throws -> Bool {
        try compare(to: other) == .orderedAscending
    }

    func isGreater(than other: Money) throws -> Bool {
        try compare(to: other) == .orderedDescending
    }

    func allocatedEqually(
        among participantIDs: [UUID],
        payerID: UUID
    ) throws -> [UUID: Money] {
        try Self.allocate(self, among: participantIDs, payerID: payerID)
    }

    static func allocate(
        _ amount: Money,
        among participantIDs: [UUID],
        payerID: UUID
    ) throws -> [UUID: Money] {
        guard !participantIDs.isEmpty else {
            throw MoneyDomainError.emptyAllocation
        }

        var seen = Set<UUID>()
        for participantID in participantIDs {
            guard seen.insert(participantID).inserted else {
                throw MoneyDomainError.duplicateParticipant(participantID)
            }
        }
        guard seen.contains(payerID) else {
            throw MoneyDomainError.payerNotParticipant(payerID)
        }

        let orderedIDs = [payerID] + participantIDs
            .filter { $0 != payerID }
            .sorted { $0.uuidString < $1.uuidString }
        let count = Int64(orderedIDs.count)
        let base = amount.minorUnits / count
        let remainder = amount.minorUnits % count
        let adjustments = Int(remainder < 0 ? -remainder : remainder)

        var allocations: [UUID: Money] = [:]
        allocations.reserveCapacity(orderedIDs.count)
        for (index, participantID) in orderedIDs.enumerated() {
            let adjustment: Int64
            if index < adjustments {
                adjustment = remainder < 0 ? -1 : 1
            } else {
                adjustment = 0
            }
            let units = base + adjustment
            allocations[participantID] = try Money(
                minorUnits: units,
                currencyCode: amount.currencyCode
            )
        }
        return allocations
    }

    func formatted(locale: Locale) throws -> String {
        try MoneyFormatter.string(for: self, locale: locale)
    }

    static func parse(
        _ text: String,
        currencyCode: String,
        locale: Locale
    ) throws -> Money {
        try MoneyParser.parse(text, currencyCode: currencyCode, locale: locale)
    }

    private func requireSameCurrency(as other: Money) throws {
        guard currencyCode == other.currencyCode else {
            throw MoneyDomainError.currencyMismatch(
                expected: currencyCode,
                actual: other.currencyCode
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case minorUnits
        case currencyCode
    }
}

enum MoneyFormatter {
    static func string(for money: Money, locale: Locale) throws -> String {
        let metadata = try CurrencyMetadata(code: money.currencyCode)
        let formatter = makeFormatter(
            metadata: metadata,
            locale: locale,
            numberStyle: .currency
        )
        guard let result = formatter.string(from: decimalNumber(for: money, metadata: metadata)) else {
            throw MoneyParsingError.malformedInput
        }
        return result
    }

    static func format(_ money: Money, locale: Locale) throws -> String {
        try string(for: money, locale: locale)
    }

    fileprivate static func makeFormatter(
        metadata: CurrencyMetadata,
        locale: Locale,
        numberStyle: NumberFormatter.Style
    ) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = numberStyle
        formatter.currencyCode = metadata.code
        formatter.currencySymbol = metadata.ordinaryDisplaySymbol
        formatter.internationalCurrencySymbol = metadata.code
        formatter.minimumFractionDigits = metadata.fractionDigits
        formatter.maximumFractionDigits = metadata.fractionDigits
        formatter.usesGroupingSeparator = true
        formatter.generatesDecimalNumbers = true
        formatter.isLenient = false
        formatter.roundingMode = .halfUp
        return formatter
    }

    fileprivate static func decimalNumber(
        for money: Money,
        metadata: CurrencyMetadata
    ) -> NSDecimalNumber {
        var decimal = Decimal(string: String(money.minorUnits), locale: Locale(identifier: "en_US_POSIX")) ?? .zero
        var divisor = Decimal(1)
        for _ in 0..<metadata.fractionDigits {
            divisor *= Decimal(10)
        }
        var result = Decimal()
        _ = NSDecimalDivide(&result, &decimal, &divisor, .plain)
        return NSDecimalNumber(decimal: result)
    }
}

enum MoneyParser {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let maximumPositiveMagnitude = "9223372036854775807"
    private static let maximumNegativeMagnitude = "9223372036854775808"

    private struct ParsedNumber {
        let isNegative: Bool
        let integerDigits: String
        let fractionalDigits: String
    }

    static func parse(
        _ text: String,
        currencyCode: String,
        locale: Locale
    ) throws -> Money {
        let metadata: CurrencyMetadata
        do {
            metadata = try CurrencyMetadata(code: currencyCode)
        } catch MoneyDomainError.unsupportedCurrencyCode {
            throw MoneyParsingError.unsupportedCurrencyCode(currencyCode)
        }

        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { throw MoneyParsingError.malformedInput }

        let currencyFormatter = MoneyFormatter.makeFormatter(
            metadata: metadata,
            locale: locale,
            numberStyle: .currency
        )
        let decimalFormatter = MoneyFormatter.makeFormatter(
            metadata: metadata,
            locale: locale,
            numberStyle: .decimal
        )

        let parsed = try parseCandidate(
            candidate,
            currencyFormatter: currencyFormatter,
            decimalFormatter: decimalFormatter
        )
        guard parsed.fractionalDigits.count <= metadata.fractionDigits else {
            throw MoneyParsingError.excessFractionPrecision(
                currencyCode: metadata.code,
                maximum: metadata.fractionDigits
            )
        }

        let paddedFraction = parsed.fractionalDigits.padding(
            toLength: metadata.fractionDigits,
            withPad: "0",
            startingAt: 0
        )
        let rawMagnitude = parsed.integerDigits + paddedFraction
        let magnitude = rawMagnitude.drop(while: { $0 == "0" })
        let magnitudeDigits = magnitude.isEmpty ? "0" : String(magnitude)
        let maximumMagnitude = parsed.isNegative
            ? Self.maximumNegativeMagnitude
            : Self.maximumPositiveMagnitude
        guard Self.compareMagnitude(magnitudeDigits, maximumMagnitude) != .orderedDescending else {
            throw MoneyParsingError.overflow
        }

        let signedMagnitude = parsed.isNegative ? "-" + magnitudeDigits : magnitudeDigits
        guard let decimal = Decimal(string: signedMagnitude, locale: Self.posixLocale) else {
            throw MoneyParsingError.overflow
        }

        let minorUnits = NSDecimalNumber(decimal: decimal).int64Value
        return try Money(minorUnits: minorUnits, currencyCode: metadata.code)
    }

    private static func parseCandidate(
        _ candidate: String,
        currencyFormatter: NumberFormatter,
        decimalFormatter: NumberFormatter
    ) throws -> ParsedNumber {
        if let extracted = extractBody(
            from: candidate,
            formatter: currencyFormatter
        ), let parsed = parseBody(
            extracted.body,
            isNegative: extracted.isNegative,
            formatter: decimalFormatter
        ) {
            return parsed
        }

        if let extracted = extractBody(
            from: candidate,
            formatter: decimalFormatter
        ), let parsed = parseBody(
            extracted.body,
            isNegative: extracted.isNegative,
            formatter: decimalFormatter
        ) {
            return parsed
        }

        throw MoneyParsingError.malformedInput
    }

    private static func extractBody(
        from candidate: String,
        formatter: NumberFormatter
    ) -> (body: String, isNegative: Bool)? {
        let forms = [
            (
                prefix: formatter.negativePrefix ?? "",
                suffix: formatter.negativeSuffix ?? "",
                isNegative: true
            ),
            (
                prefix: formatter.positivePrefix ?? "",
                suffix: formatter.positiveSuffix ?? "",
                isNegative: false
            )
        ]

        for form in forms {
            guard candidate.hasPrefix(form.prefix), candidate.hasSuffix(form.suffix) else {
                continue
            }

            let bodyStart = candidate.index(
                candidate.startIndex,
                offsetBy: form.prefix.count
            )
            let bodyEnd = candidate.index(
                candidate.endIndex,
                offsetBy: -form.suffix.count
            )
            guard bodyStart <= bodyEnd else { continue }

            return (
                String(candidate[bodyStart..<bodyEnd]),
                form.isNegative
            )
        }

        return nil
    }

    private static func parseBody(
        _ body: String,
        isNegative: Bool,
        formatter: NumberFormatter
    ) -> ParsedNumber? {
        guard let decimalSeparator = formatter.decimalSeparator,
              !decimalSeparator.isEmpty else {
            return nil
        }

        let decimalParts = body.components(separatedBy: decimalSeparator)
        guard decimalParts.count <= 2,
              let integerPart = decimalParts.first,
              !integerPart.isEmpty else {
            return nil
        }

        let fractionalPart: String
        if decimalParts.count == 2 {
            guard !decimalParts[1].isEmpty else { return nil }
            fractionalPart = decimalParts[1]
        } else {
            fractionalPart = ""
        }

        guard let integerDigits = parseIntegerDigits(
            integerPart,
            formatter: formatter
        ) else {
            return nil
        }
        let fractionalDigits = digits(from: fractionalPart) ?? ""
        guard fractionalPart.isEmpty || !fractionalDigits.isEmpty else {
            return nil
        }

        return ParsedNumber(
            isNegative: isNegative,
            integerDigits: integerDigits,
            fractionalDigits: fractionalDigits
        )
    }

    private static func parseIntegerDigits(
        _ integerPart: String,
        formatter: NumberFormatter
    ) -> String? {
        guard let groupingSeparator = formatter.groupingSeparator,
              !groupingSeparator.isEmpty else {
            return digits(from: integerPart)
        }

        let normalized = normalizeGroupingVariants(
            in: integerPart,
            expected: groupingSeparator
        )
        guard normalized.contains(groupingSeparator) else {
            return digits(from: normalized)
        }

        let groups = normalized.components(separatedBy: groupingSeparator)
        guard groups.count > 1,
              let groupingSize = validGroupingSize(formatter.groupingSize) else {
            return nil
        }
        let secondaryGroupingSize = formatter.secondaryGroupingSize > 0
            ? formatter.secondaryGroupingSize
            : groupingSize

        guard let first = groups.first,
              !first.isEmpty,
              first.count <= secondaryGroupingSize,
              groups.dropFirst().allSatisfy({ !$0.isEmpty }),
              groups.dropFirst().dropLast().allSatisfy({
                  $0.count == secondaryGroupingSize
              }),
              groups.last?.count == groupingSize else {
            return nil
        }

        let digitGroups = groups.compactMap { digits(from: $0) }
        guard digitGroups.count == groups.count else { return nil }
        return digitGroups.joined()
    }

    private static func validGroupingSize(_ size: Int) -> Int? {
        size > 0 ? size : nil
    }

    private static func normalizeGroupingVariants(
        in value: String,
        expected: String
    ) -> String {
        guard expected.unicodeScalars.allSatisfy(isGroupingWhitespace) else {
            return value
        }

        var normalized = value
        for variant in [" ", "\u{00A0}", "\u{202F}", "\u{2009}"]
            where variant != expected {
            normalized = normalized.replacingOccurrences(
                of: variant,
                with: expected
            )
        }
        return normalized
    }

    private static func isGroupingWhitespace(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x20, 0x00A0, 0x202F, 0x2009:
            return true
        default:
            return false
        }
    }

    private static func digits(from value: String) -> String? {
        guard !value.isEmpty else { return nil }

        var result = ""
        result.reserveCapacity(value.unicodeScalars.count)
        for scalar in value.unicodeScalars {
            guard let digit = digitValue(for: scalar),
                  let asciiScalar = UnicodeScalar(48 + UInt32(digit)) else {
                return nil
            }
            result.unicodeScalars.append(asciiScalar)
        }
        return result
    }

    private static func digitValue(for scalar: UnicodeScalar) -> UInt8? {
        let value = scalar.value
        for start in decimalDigitBlockStarts
            where value >= start && value < start + 10 {
            return UInt8(value - start)
        }
        return nil
    }

    private static let decimalDigitBlockStarts: [UInt32] = [
        0x0030, // ASCII
        0x0660, // Arabic-Indic
        0x06F0, // Extended Arabic-Indic
        0x0966, // Devanagari
        0x09E6, // Bengali
        0x0A66, // Gurmukhi
        0x0AE6, // Gujarati
        0x0B66, // Oriya
        0x0BE6, // Tamil
        0x0C66, // Telugu
        0x0CE6, // Kannada
        0x0D66, // Malayalam
        0x0E50, // Thai
        0x0ED0, // Lao
        0x0F20, // Tibetan
        0x1040, // Myanmar
        0x17E0, // Khmer
        0x1810, // Mongolian
        0xFF10  // Fullwidth
    ]

    private static func compareMagnitude(_ lhs: String, _ rhs: String) -> ComparisonResult {
        if lhs.count != rhs.count {
            return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
        }
        if lhs == rhs { return .orderedSame }
        return lhs.lexicographicallyPrecedes(rhs) ? .orderedAscending : .orderedDescending
    }
}

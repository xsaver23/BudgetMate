import Foundation
import XCTest
@testable import BudgetMate

final class MoneyDomainTests: XCTestCase {
    func testCatalogCoversExactlyTheSelectableCurrenciesAndUsesCorrectFractionDigits() throws {
        XCTAssertEqual(
            CurrencyMetadata.supportedCodes,
            ["USD", "CAD", "EUR", "GBP", "AUD", "PHP", "JPY"]
        )
        XCTAssertEqual(CurrencyMetadata.catalogVersion, 1)

        let expectedDigits = [
            "USD": 2,
            "CAD": 2,
            "EUR": 2,
            "GBP": 2,
            "AUD": 2,
            "PHP": 2,
            "JPY": 0
        ]
        for metadata in CurrencyMetadata.supported {
            XCTAssertEqual(metadata.fractionDigits, expectedDigits[metadata.code])
            XCTAssertTrue(CurrencyMetadata.isSupported(metadata.code.lowercased()))
        }
        XCTAssertFalse(CurrencyMetadata.isSupported("CHF"))
    }

    func testMoneyNormalizesSupportedCodesAndRejectsUnsupportedCodes() throws {
        let money = try Money(minorUnits: 125, currencyCode: " cad ")
        XCTAssertEqual(money.currencyCode, "CAD")
        XCTAssertEqual(money.minorUnits, 125)

        XCTAssertThrowsError(try Money(minorUnits: 1, currencyCode: "CHF")) { error in
            XCTAssertEqual(error as? MoneyDomainError, .unsupportedCurrencyCode("CHF"))
        }
    }

    func testCheckedArithmeticAndComparisonAreExactAndCurrencyAware() throws {
        let oneDollar = try Money(minorUnits: 100, currencyCode: "USD")
        let fiftyCents = try Money(minorUnits: 50, currencyCode: "USD")
        XCTAssertEqual(try oneDollar.adding(fiftyCents).minorUnits, 150)
        XCTAssertEqual(try oneDollar.subtracting(fiftyCents).minorUnits, 50)
        XCTAssertEqual(try oneDollar.negated().minorUnits, -100)
        XCTAssertEqual(try oneDollar.multiplied(by: 3).minorUnits, 300)
        XCTAssertEqual(try oneDollar.compare(to: fiftyCents), .orderedDescending)
        XCTAssertTrue(try fiftyCents.isLess(than: oneDollar))

        let euro = try Money(minorUnits: 100, currencyCode: "EUR")
        XCTAssertThrowsError(try oneDollar.adding(euro)) { error in
            XCTAssertEqual(
                error as? MoneyDomainError,
                .currencyMismatch(expected: "USD", actual: "EUR")
            )
        }
        XCTAssertThrowsError(try oneDollar.compare(to: euro))

        let maximum = try Money(minorUnits: Int64.max, currencyCode: "USD")
        let minimum = try Money(minorUnits: Int64.min, currencyCode: "USD")
        XCTAssertThrowsError(try maximum.adding(oneDollar))
        XCTAssertThrowsError(try minimum.negated())
        XCTAssertThrowsError(try maximum.multiplied(by: 2))
    }

    func testEqualAllocationIsExactDeterministicAndPayerFirstAcrossMatrix() throws {
        let payer = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
        let recipientIDs = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        ]
        let currencyCode = "USD"

        for participantCount in 1...6 {
            let participants = Array(recipientIDs.prefix(participantCount - 1)) + [payer]
            let inputPermutations = permutations(of: participants)

            for amount in allocationAmounts(for: participantCount) {
                let money = try Money(minorUnits: amount, currencyCode: currencyCode)
                let baseline = try money.allocatedEqually(
                    among: participants,
                    payerID: payer
                )
                let orderedIDs = [payer] + participants
                    .filter { $0 != payer }
                    .sorted { $0.uuidString < $1.uuidString }
                let count = Int64(orderedIDs.count)
                let base = amount / count
                let remainder = amount % count
                let adjustmentCount = Int(remainder < 0 ? -remainder : remainder)
                let adjustment: Int64 = remainder < 0 ? -1 : 1

                XCTAssertEqual(Set(baseline.keys), Set(participants))
                XCTAssertTrue(baseline.values.allSatisfy { $0.currencyCode == currencyCode })
                XCTAssertEqual(
                    try totalMinorUnits(in: baseline, currencyCode: currencyCode),
                    amount,
                    "Conservation failed for count (participantCount), amount (amount)"
                )

                for (index, participantID) in orderedIDs.enumerated() {
                    let expected = base + (index < adjustmentCount ? adjustment : 0)
                    XCTAssertEqual(
                        baseline[participantID]?.minorUnits,
                        expected,
                        "Unexpected remainder recipient for count (participantCount), amount (amount)"
                    )
                }

                for permutation in inputPermutations {
                    let actual = try money.allocatedEqually(
                        among: permutation,
                        payerID: payer
                    )
                    XCTAssertEqual(actual, baseline)
                    XCTAssertEqual(Set(actual.keys), Set(participants))
                    XCTAssertTrue(actual.values.allSatisfy { $0.currencyCode == currencyCode })
                    XCTAssertEqual(
                        try totalMinorUnits(in: actual, currencyCode: currencyCode),
                        amount
                    )
                }
            }
        }

        let example = try Money(minorUnits: 10, currencyCode: currencyCode)
        XCTAssertThrowsError(
            try example.allocatedEqually(among: [], payerID: payer)
        ) { error in
            XCTAssertEqual(error as? MoneyDomainError, .emptyAllocation)
        }
        XCTAssertThrowsError(
            try example.allocatedEqually(among: [payer, payer], payerID: payer)
        ) { error in
            XCTAssertEqual(error as? MoneyDomainError, .duplicateParticipant(payer))
        }
        XCTAssertThrowsError(
            try example.allocatedEqually(among: recipientIDs, payerID: payer)
        ) { error in
            XCTAssertEqual(error as? MoneyDomainError, .payerNotParticipant(payer))
        }
    }

    func testFormattingAndParsingRoundTripAcrossSupportedCurrenciesAndLocales() throws {
        let locales = [
            Locale(identifier: "en_US"),
            Locale(identifier: "en_CA"),
            Locale(identifier: "fr_CA"),
            Locale(identifier: "de_DE"),
            Locale(identifier: "ja_JP")
        ]
        let fixtures: [(String, Int64)] = [
            ("USD", 123456),
            ("CAD", 123456),
            ("EUR", 123456),
            ("GBP", 123456),
            ("AUD", 123456),
            ("PHP", 123456),
            ("JPY", 123456)
        ]

        for locale in locales {
            for (code, minorUnits) in fixtures {
                let money = try Money(minorUnits: minorUnits, currencyCode: code)
                let output = try MoneyFormatter.string(for: money, locale: locale)
                let parsed = try MoneyParser.parse(
                    output,
                    currencyCode: code,
                    locale: locale
                )
                XCTAssertEqual(parsed, money, "Failed round trip for \(code) in \(locale.identifier)")
            }
        }
    }

    func testCADOrdinaryOutputUsesDollarSymbolWithoutCADPrefixes() throws {
        let money = try Money(minorUnits: -123456, currencyCode: "CAD")
        for locale in [Locale(identifier: "en_CA"), Locale(identifier: "fr_CA")] {
            let output = try MoneyFormatter.string(for: money, locale: locale)
            XCTAssertTrue(output.contains("$"), output)
            XCTAssertFalse(output.contains("CAD"), output)
            XCTAssertFalse(output.contains("CA$"), output)
            XCTAssertEqual(
                try MoneyParser.parse(output, currencyCode: "CAD", locale: locale),
                money
            )
        }
    }

    func testParserRejectsMalformedUnsupportedExcessPrecisionAndOverflowValues() throws {
        XCTAssertThrowsError(
            try MoneyParser.parse("$1.2.3", currencyCode: "USD", locale: Locale(identifier: "en_US"))
        ) { error in
            XCTAssertEqual(error as? MoneyParsingError, .malformedInput)
        }
        XCTAssertThrowsError(
            try MoneyParser.parse("$1.001", currencyCode: "USD", locale: Locale(identifier: "en_US"))
        ) { error in
            XCTAssertEqual(
                error as? MoneyParsingError,
                .excessFractionPrecision(currencyCode: "USD", maximum: 2)
            )
        }
        XCTAssertThrowsError(
            try MoneyParser.parse("¥1.2", currencyCode: "JPY", locale: Locale(identifier: "ja_JP"))
        ) { error in
            XCTAssertEqual(
                error as? MoneyParsingError,
                .excessFractionPrecision(currencyCode: "JPY", maximum: 0)
            )
        }
        XCTAssertThrowsError(
            try MoneyParser.parse("$1.00", currencyCode: "CHF", locale: Locale(identifier: "en_US"))
        ) { error in
            XCTAssertEqual(error as? MoneyParsingError, .unsupportedCurrencyCode("CHF"))
        }
        XCTAssertThrowsError(
            try MoneyParser.parse(
                "$92,233,720,368,547,758.08",
                currencyCode: "USD",
                locale: Locale(identifier: "en_US")
            )
        ) { error in
            XCTAssertEqual(error as? MoneyParsingError, .overflow)
        }
        XCTAssertThrowsError(
            try MoneyParser.parse(
                "-$92,233,720,368,547,758.09",
                currencyCode: "USD",
                locale: Locale(identifier: "en_US")
            )
        ) { error in
            XCTAssertEqual(error as? MoneyParsingError, .overflow)
        }
    }

    func testParserUsesLocaleGroupingAndCurrencyAffixesWithoutAcceptingGarbage() throws {
        XCTAssertEqual(
            try MoneyParser.parse(
                "1.2",
                currencyCode: "USD",
                locale: Locale(identifier: "en_US")
            ).minorUnits,
            120
        )
        XCTAssertEqual(
            try MoneyParser.parse(
                "1\u{00A0}234,5",
                currencyCode: "CAD",
                locale: Locale(identifier: "fr_CA")
            ).minorUnits,
            123450
        )
        XCTAssertEqual(
            try MoneyParser.parse(
                "1.234,56\u{00A0}€",
                currencyCode: "EUR",
                locale: Locale(identifier: "de_DE")
            ).minorUnits,
            123456
        )

        let malformedInputs = [
            "$1,23.45", // wrong en_US grouping
            "$1,234.56 trailing", // trailing garbage
            "€1.00" // wrong currency symbol
        ]
        for input in malformedInputs {
            XCTAssertThrowsError(
                try MoneyParser.parse(
                    input,
                    currencyCode: "USD",
                    locale: Locale(identifier: "en_US")
                )
            ) { error in
                XCTAssertEqual(error as? MoneyParsingError, .malformedInput, input)
            }
        }

        XCTAssertThrowsError(
            try MoneyParser.parse(
                "1\u{00A0}23,45 $",
                currencyCode: "CAD",
                locale: Locale(identifier: "fr_CA")
            )
        ) { error in
            XCTAssertEqual(error as? MoneyParsingError, .malformedInput)
        }
    }

    func testFormattingHandlesZeroNegativeMinimumAndLargeMinorUnitsWithoutDouble() throws {
        let values: [Int64] = [0, -1, Int64.min, Int64.max]
        for value in values {
            let money = try Money(minorUnits: value, currencyCode: "USD")
            let output = try MoneyFormatter.string(for: money, locale: Locale(identifier: "en_US"))
            XCTAssertFalse(output.isEmpty)
            XCTAssertEqual(
                try MoneyParser.parse(output, currencyCode: "USD", locale: Locale(identifier: "en_US")),
                money
            )
        }
    }

    private func allocationAmounts(for participantCount: Int) -> [Int64] {
        var amounts: [Int64] = [
            Int64.min,
            Int64.min + 1,
            -1,
            0,
            1,
            Int64.max - 1,
            Int64.max
        ]
        for remainder in 0..<participantCount {
            let amount = Int64(remainder)
            amounts.append(amount)
            if amount != 0 {
                amounts.append(-amount)
            }
        }
        return amounts
    }

    private func totalMinorUnits(
        in allocations: [UUID: Money],
        currencyCode: String
    ) throws -> Int64 {
        var total = try Money(minorUnits: 0, currencyCode: currencyCode)
        for participantID in allocations.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            total = try total.adding(allocations[participantID]!)
        }
        return total.minorUnits
    }

    private func permutations(of values: [UUID]) -> [[UUID]] {
        guard !values.isEmpty else { return [[]] }
        return values.indices.flatMap { index in
            var remaining = values
            let head = remaining.remove(at: index)
            return permutations(of: remaining).map { [head] + $0 }
        }
    }
}

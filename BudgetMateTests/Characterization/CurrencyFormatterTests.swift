import XCTest
@testable import BudgetMate

final class CurrencyFormatterTests: XCTestCase {
    func testCADUsesPlainDollarAcrossLocalesAndValues() {
        let values = [1_234.56, 0, -42.75, 1_234_567.89]
        let locales = ["en_CA", "fr_CA", "en_US"]

        for localeID in locales {
            for value in values {
                let output = CurrencyFormatter.amountString(
                    value,
                    currencyCode: "CAD",
                    locale: Locale(identifier: localeID)
                )

                XCTAssertTrue(output.contains("$"), "Expected $ in \(localeID): \(output)")
                XCTAssertFalse(output.contains("CAD"), "Unexpected CAD in \(localeID): \(output)")
                XCTAssertFalse(output.contains("CA$"), "Unexpected CA$ in \(localeID): \(output)")
            }
        }
    }

    func testCADPreservesLocaleSeparatorsAndSymbolPlacement() {
        let englishCanada = CurrencyFormatter.amountString(
            1_234.5,
            currencyCode: "CAD",
            locale: Locale(identifier: "en_CA")
        )
        let frenchCanada = CurrencyFormatter.amountString(
            1_234.5,
            currencyCode: "CAD",
            locale: Locale(identifier: "fr_CA")
        )
        let englishUnitedStates = CurrencyFormatter.amountString(
            1_234.5,
            currencyCode: "CAD",
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(englishCanada, "$1,234.50")
        XCTAssertTrue(frenchCanada.contains("1\u{00A0}234,50"))
        XCTAssertTrue(frenchCanada.hasSuffix("\u{00A0}$"))
        XCTAssertEqual(englishUnitedStates, "$1,234.50")
    }

    func testCADAffixPlacementMatchesTheLocaleCurrencyContract() {
        let leading = CurrencyFormatter.currencyAffix(
            currencyCode: "CAD",
            locale: Locale(identifier: "en_CA")
        )
        let trailing = CurrencyFormatter.currencyAffix(
            currencyCode: "CAD",
            locale: Locale(identifier: "fr_CA")
        )

        XCTAssertEqual(leading, .init(symbol: "$", placement: .leading))
        XCTAssertEqual(trailing, .init(symbol: "$", placement: .trailing))
    }

    func testNonCADCurrenciesKeepTheirLocalizedPresentation() {
        let euro = CurrencyFormatter.amountString(
            1_234.5,
            currencyCode: "EUR",
            locale: Locale(identifier: "en_US")
        )
        let yen = CurrencyFormatter.amountString(
            1_234.5,
            currencyCode: "JPY",
            locale: Locale(identifier: "ja_JP")
        )

        XCTAssertEqual(euro, "€1,234.50")
        XCTAssertTrue(yen.contains("¥"), "Expected yen symbol: \(yen)")
        XCTAssertFalse(euro.contains("CA$"))
        XCTAssertFalse(yen.contains("CA$"))
    }

    func testCADCodeRemainsStoredAndExplicitWhileDisplaySymbolIsPlainDollar() {
        let settings = BudgetSettings(
            monthlyBudget: 0,
            currencyCode: "CAD",
            categoryBudgets: [:]
        )
        let row = CloudBudgetSettingsRow(
            settings: settings,
            userId: BudgetMateTestFixtures.aliceUserID,
            budgetId: BudgetMateTestFixtures.sharedBudgetID
        )

        XCTAssertEqual(settings.currencyCode, "CAD")
        XCTAssertEqual(row.currencyCode, "CAD")
        XCTAssertEqual(CurrencyOption.symbol(for: "CAD"), "CA$")
        XCTAssertEqual(CurrencyOption.displaySymbol(for: "CAD"), "$")
        XCTAssertTrue(CurrencyOption(rawValue: "CAD")!.pickerLabel.contains("CAD"))
    }
}

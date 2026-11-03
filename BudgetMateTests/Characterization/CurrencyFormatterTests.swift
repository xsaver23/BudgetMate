import XCTest
@testable import BudgetMate

@MainActor
final class CurrencyFormatterTests: XCTestCase {
    func testEditingSplitTransactionPrefillsAndParsesInInjectedLocale() throws {
        let transaction = BudgetMateTestFixtures.customSplitExpense(amount: 1_234.56)

        for localeID in ["en_US", "de_DE", "fr_CA", "de_CH"] {
            let locale = Locale(identifier: localeID)
            let viewModel = AddTransactionViewModel(transaction: transaction, locale: locale)

            let parsedAmount = try XCTUnwrap(
                viewModel.parsedAmount(currencyCode: "USD", locale: locale),
                localeID
            )
            XCTAssertEqual(
                viewModel.amountText,
                ["de_DE", "fr_CA"].contains(localeID) ? "1234,56" : "1234.56",
                localeID
            )
            XCTAssertEqual(parsedAmount, 1_234.56, accuracy: 0.001, localeID)
            XCTAssertEqual(
                viewModel.customSplitMoneyTotal(currencyCode: "USD", locale: locale)?.minorUnits,
                Int64(123_456),
                localeID
            )
            XCTAssertTrue(viewModel.canSave(currencyCode: "USD", locale: locale), localeID)
            XCTAssertTrue(viewModel.isSplitValid(currencyCode: "USD", locale: locale), localeID)
        }
    }

    func testGroupedAmountInputUsesLocaleGroupingAndDecimalRules() {
        let viewModel = AddTransactionViewModel()

        viewModel.updateAmountText("1,234.56", currencyCode: "USD")
        XCTAssertEqual(viewModel.amountText, "1,234.56")
        XCTAssertEqual(
            viewModel.parsedAmount(currencyCode: "USD", locale: Locale(identifier: "en_US")),
            1234.56
        )

        viewModel.updateAmountText("1.234,56", currencyCode: "USD")
        XCTAssertEqual(viewModel.amountText, "1.234,56")
        XCTAssertEqual(
            viewModel.parsedAmount(currencyCode: "USD", locale: Locale(identifier: "de_DE")),
            1234.56
        )

        viewModel.updateAmountText("1\u{00A0}234,56", currencyCode: "CAD")
        XCTAssertEqual(
            viewModel.parsedAmount(currencyCode: "CAD", locale: Locale(identifier: "fr_CA")),
            1234.56
        )
    }

    func testMalformedGroupedAmountRemainsUnparseable() {
        let viewModel = AddTransactionViewModel()
        viewModel.updateAmountText("1,23,4.56", currencyCode: "USD")

        XCTAssertNil(viewModel.parsedAmount(currencyCode: "USD"))

        viewModel.updateAmountText("1 2", currencyCode: "USD")
        XCTAssertNil(viewModel.parsedAmount(currencyCode: "USD", locale: Locale(identifier: "fr_CA")))
    }

    func testSingleGroupingAndExcessPrecisionAreNotSilentlyRewritten() {
        let viewModel = AddTransactionViewModel()

        viewModel.updateAmountText("1,234", currencyCode: "USD")
        XCTAssertEqual(viewModel.amountText, "1,234")
        XCTAssertEqual(
            viewModel.parsedAmount(currencyCode: "USD", locale: Locale(identifier: "en_US")),
            1234
        )

        viewModel.updateAmountText("12.345", currencyCode: "USD")
        XCTAssertEqual(viewModel.amountText, "12.345")
        XCTAssertNil(viewModel.parsedAmount(currencyCode: "USD", locale: Locale(identifier: "en_US")))
    }

    func testJPYExcessFractionRemainsInvalidInsteadOfBecomingWholeYen() {
        let viewModel = AddTransactionViewModel()
        viewModel.updateAmountText("100.5", currencyCode: "JPY")

        XCTAssertEqual(viewModel.amountText, "100.5")
        XCTAssertNil(viewModel.parsedAmount(currencyCode: "JPY", locale: Locale(identifier: "ja_JP")))
    }

    func testSignsAndLettersAreNotStrippedIntoAnotherAmount() {
        let viewModel = AddTransactionViewModel()
        viewModel.updateAmountText("-$1,234.56", currencyCode: "USD")

        XCTAssertEqual(viewModel.amountText, "-$1,234.56")
        XCTAssertNil(viewModel.parsedAmount(currencyCode: "USD", locale: Locale(identifier: "en_US")))
    }

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

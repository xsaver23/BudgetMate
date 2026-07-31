import XCTest
@testable import BudgetMate

final class TransactionRowPresentationTests: XCTestCase {
    func testCADTransactionRowAmountsUseDollarWithIncomeExpenseSigns() {
        let locale = Locale(identifier: "en_CA")

        let expense = TransactionRowPresentation.signedAmount(
            amount: 12.34,
            type: .expense,
            currencySymbol: "CA$",
            locale: locale
        )
        let income = TransactionRowPresentation.signedAmount(
            amount: 12.34,
            type: .income,
            currencySymbol: "CA$",
            locale: locale
        )

        XCTAssertEqual(expense, "-$12.34")
        XCTAssertEqual(income, "+$12.34")
        for output in [expense, income] {
            XCTAssertTrue(output.contains("$"))
            XCTAssertFalse(output.contains("CAD"))
            XCTAssertFalse(output.contains("CA$"))
        }
    }
}

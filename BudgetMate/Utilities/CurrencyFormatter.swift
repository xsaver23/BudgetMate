import Foundation

enum CurrencyFormatter {
    static func amountString(_ amount: Double, symbol: String) -> String {
        "\(symbol)\(numberString(amount))"
    }

    static func numberString(_ amount: Double) -> String {
        amount.formatted(.number.grouping(.automatic).precision(.fractionLength(2)))
    }
}

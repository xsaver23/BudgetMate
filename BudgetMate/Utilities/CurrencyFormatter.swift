import Foundation

enum CurrencyFormatter {
    static func amountString(_ amount: Double, symbol: String) -> String {
        "\(symbol)\(numberString(amount))"
    }

    static func numberString(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
}

import Foundation

enum CurrencyFormatter {
    static func amountString(_ amount: Double, symbol: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        let numberString = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
        return "\(symbol)\(numberString)"
    }
}

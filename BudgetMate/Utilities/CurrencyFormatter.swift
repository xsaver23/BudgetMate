import Foundation

enum CurrencyFormatter {
    enum SymbolPlacement: Equatable {
        case leading
        case trailing
    }

    struct CurrencyAffix: Equatable {
        let symbol: String
        let placement: SymbolPlacement
    }

    static func amountString(
        _ amount: Double,
        currencyCode: String,
        locale: Locale = .current
    ) -> String {
        let normalizedCode = CurrencyOption.normalizedCode(currencyCode)
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = normalizedCode
        formatter.currencySymbol = CurrencyOption.displaySymbol(for: normalizedCode)
        if let metadata = try? CurrencyMetadata(code: normalizedCode) {
            formatter.minimumFractionDigits = metadata.fractionDigits
            formatter.maximumFractionDigits = metadata.fractionDigits
        }
        return formatter.string(from: NSNumber(value: amount)) ?? numberString(amount, locale: locale)
    }

    static func amountString(
        _ amount: Double,
        symbol: String,
        currencyCode: String? = nil,
        locale: Locale = .current
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencySymbol = symbol
        let resolvedCurrencyCode = currencyCode ?? CurrencyOption.code(forLegacySymbol: symbol)
        let fractionDigits = (try? CurrencyMetadata(code: resolvedCurrencyCode))?.fractionDigits ?? 2
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let fallbackNumber = numberString(
            amount,
            currencyCode: resolvedCurrencyCode,
            locale: locale
        )
        return formatter.string(from: NSNumber(value: amount)) ?? "\(symbol)\(fallbackNumber)"
    }

    static func amountString(
        _ money: Money,
        locale: Locale = .current
    ) -> String {
        (try? money.formatted(locale: locale)) ?? ""
    }

    static func amountString(
        _ minorUnits: Int64,
        currencyCode: String,
        locale: Locale = .current
    ) -> String {
        MoneyAccounting.formatted(minorUnits: minorUnits, currencyCode: currencyCode, locale: locale) ?? ""
    }

    static func currencyAffix(
        currencyCode: String,
        locale: Locale = .current
    ) -> CurrencyAffix {
        let normalizedCode = CurrencyOption.normalizedCode(currencyCode)
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = normalizedCode
        formatter.currencySymbol = CurrencyOption.displaySymbol(for: normalizedCode)
        guard let rendered = formatter.string(from: NSNumber(value: 1)),
              let symbol = formatter.currencySymbol,
              let symbolRange = rendered.range(of: symbol),
              let firstNumberIndex = rendered.firstIndex(where: { $0.isNumber }) else {
            return CurrencyAffix(
                symbol: CurrencyOption.displaySymbol(for: normalizedCode),
                placement: .leading
            )
        }
        return CurrencyAffix(
            symbol: symbol,
            placement: symbolRange.lowerBound < firstNumberIndex ? .leading : .trailing
        )
    }

    static func numberString(
        _ amount: Double,
        currencyCode: String? = nil,
        locale: Locale = .current
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let fractionDigits = currencyCode.flatMap { (try? CurrencyMetadata(code: $0))?.fractionDigits } ?? 2
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.*f", fractionDigits, amount)
    }
}

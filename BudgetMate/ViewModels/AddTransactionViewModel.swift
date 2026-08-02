import Foundation

@MainActor
final class AddTransactionViewModel: ObservableObject {
    @Published var type: TransactionType = .expense {
        didSet {
            ensureCategoryMatchesType()
        }
    }
    @Published var title: String = ""
    @Published var amountText: String = ""
    @Published var category: TransactionCategory = .other
    @Published var paymentMethod: PaymentMethod = .card
    @Published var date: Date = .now
    @Published var repeatsMonthly: Bool = false
    @Published var hasRecurrenceEndDate: Bool = false
    @Published var recurrenceEndDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @Published private var customExpenseCategories: [TransactionCategory] = []
    @Published private var hiddenExpenseCategoryRawValues: Set<String> = []

    // Split state (expenses only).
    @Published var isSplit: Bool = false
    @Published var splitMethod: SplitMethod = .equally
    @Published var participants: Set<UUID> = []
    @Published var customAmounts: [UUID: String] = [:]

    var availableCategories: [TransactionCategory] {
        if type == .expense {
            let builtInCategories = TransactionCategory.expenseCategories
                .filter { !hiddenExpenseCategoryRawValues.contains($0.rawValue) }
            return builtInCategories + customExpenseCategories
        }

        return TransactionCategory.incomeCategories
    }

    var isSplittable: Bool { type == .expense }

    init(transaction: Transaction? = nil) {
        guard let transaction else { return }
        type = transaction.type
        title = transaction.title
        let transactionCurrencyCode = transaction.currencyCode ?? CurrencyOption.usd.code
        amountText = CurrencyFormatter.numberString(
            transaction.amount,
            currencyCode: transactionCurrencyCode,
            locale: Locale(identifier: "en_US_POSIX")
        )
        category = transaction.category
        paymentMethod = transaction.paymentMethod ?? .card
        date = transaction.date
        repeatsMonthly = transaction.isMonthlyRecurring
        if let endDate = transaction.recurrenceEndDate {
            hasRecurrenceEndDate = true
            recurrenceEndDate = endDate
        }

        if transaction.isSplit {
            isSplit = true
            splitMethod = .custom
            participants = Set(transaction.splits.map(\.memberId))
            customAmounts = Dictionary(
                transaction.splits.map {
                    ($0.memberId, CurrencyFormatter.numberString(
                        $0.amount,
                        currencyCode: $0.currencyCode ?? transactionCurrencyCode,
                        locale: Locale(identifier: "en_US_POSIX")
                    ))
                },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              parsedAmount != nil else { return false }
        return isSplitValid
    }

    func canSave(currencyCode: String, locale: Locale = .current) -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              parsedAmount(currencyCode: currencyCode, locale: locale) != nil else { return false }
        return isSplitValid(currencyCode: currencyCode, locale: locale)
    }

    var parsedAmount: Double? {
        guard let value = Double(amountText), value > 0 else { return nil }
        return value
    }

    func parsedAmount(currencyCode: String, locale: Locale = .current) -> Double? {
        guard let money = try? Money.parse(
            amountText,
            currencyCode: currencyCode,
            locale: Locale(identifier: "en_US_POSIX")
        ), money.minorUnits > 0 else { return nil }
        return MoneyAccounting.doubleValue(of: money)
    }

    func updateAmountText(_ text: String, currencyCode: String = CurrencyOption.usd.code) {
        let sanitized = Self.sanitizedMoneyText(text, currencyCode: currencyCode)
        amountText = sanitized
    }

    func customAmountText(for memberId: UUID) -> String {
        customAmounts[memberId] ?? ""
    }

    func updateCustomAmount(_ text: String, for memberId: UUID, currencyCode: String = CurrencyOption.usd.code) {
        let sanitized = Self.sanitizedMoneyText(text, currencyCode: currencyCode)
        customAmounts[memberId] = sanitized
    }

    func normalizeInput(currencyCode: String) {
        amountText = Self.sanitizedMoneyText(amountText, currencyCode: currencyCode)
        customAmounts = customAmounts.mapValues {
            Self.sanitizedMoneyText($0, currencyCode: currencyCode)
        }
    }

    // MARK: - Split helpers

    /// Sum of the amounts typed into the custom split fields for participants.
    var customSplitTotal: Double {
        participants.reduce(0) { $0 + (Double(customAmounts[$1] ?? "") ?? 0) }
    }

    func customSplitTotal(currencyCode: String) -> Double {
        guard let money = customSplitMoneyTotal(currencyCode: currencyCode) else { return customSplitTotal }
        return MoneyAccounting.doubleValue(of: money)
    }

    func customSplitMoneyTotal(currencyCode: String) -> Money? {
        guard !participants.isEmpty else { return nil }
        var values: [Money] = []
        for memberId in participants {
            guard let money = try? Money.parse(
                customAmounts[memberId] ?? "",
                currencyCode: currencyCode,
                locale: Locale(identifier: "en_US_POSIX")
            ) else { return nil }
            values.append(money)
        }
        return try? MoneyAccounting.sumChecked(values, currencyCode: currencyCode).get()
    }

    var isSplitValid: Bool {
        isSplitValid(currencyCode: CurrencyOption.usd.code)
    }

    func isSplitValid(currencyCode: String, locale: Locale = .current) -> Bool {
        guard isSplit, isSplittable else { return true }
        guard !participants.isEmpty, parsedAmount(currencyCode: currencyCode, locale: locale) != nil else { return false }
        guard let totalMoney = parsedMoney(currencyCode: currencyCode) else { return false }
        switch splitMethod {
        case .equally:
            return true
        case .custom:
            guard let splitMoney = customSplitMoneyTotal(currencyCode: currencyCode) else { return false }
            return splitMoney.currencyCode == totalMoney.currencyCode && splitMoney.minorUnits == totalMoney.minorUnits
        }
    }

    var splitValidationMessage: String? {
        splitValidationMessage(currencyCode: CurrencyOption.usd.code)
    }

    func splitValidationMessage(currencyCode: String, locale: Locale = .current) -> String? {
        guard isSplit, isSplittable else { return nil }
        if participants.isEmpty { return "Select at least one member to split with." }
        guard parsedAmount(currencyCode: currencyCode, locale: locale) != nil else { return "Enter an amount to split." }
        guard let totalMoney = parsedMoney(currencyCode: currencyCode) else { return "Enter an amount to split." }
        if splitMethod == .custom {
            guard let splitMoney = customSplitMoneyTotal(currencyCode: currencyCode) else {
                return "Enter valid split amounts."
            }
            let difference = totalMoney.minorUnits.subtractingReportingOverflow(splitMoney.minorUnits)
            guard !difference.overflow, difference.partialValue != 0 else { return nil }
            let rendered = CurrencyFormatter.amountString(
                difference.partialValue == Int64.min ? Int64.max : abs(difference.partialValue),
                currencyCode: currencyCode,
                locale: locale
            )
            if difference.partialValue > 0 {
                return "Add \(rendered) more to match the total."
            } else {
                return "That's \(rendered) over the total."
            }
        }
        return nil
    }

    /// Resolves the final per-member shares. `payerId` receives any rounding
    /// remainder for equal splits (or the first participant if not included).
    func resolvedSplits(
        payerId: UUID,
        currencyCode: String = CurrencyOption.usd.code
    ) -> [(memberId: UUID, amount: Double)]? {
        guard let exactSplits = resolvedMoneySplits(payerId: payerId, currencyCode: currencyCode) else { return nil }
        return exactSplits.map { ($0.memberId, MoneyAccounting.doubleValue(of: $0.money)) }
    }

    func resolvedMoneySplits(
        payerId: UUID,
        currencyCode: String = CurrencyOption.usd.code
    ) -> [(memberId: UUID, money: Money)]? {
        guard isSplit, isSplittable, let totalMoney = parsedMoney(currencyCode: currencyCode), !participants.isEmpty else { return nil }

        // Stable ordering with the payer first so remainder cents land there.
        let ids = participants.sorted { lhs, rhs in
            if lhs == payerId { return true }
            if rhs == payerId { return false }
            return lhs.uuidString < rhs.uuidString
        }

        switch splitMethod {
        case .custom:
            let shares: [(UUID, Money)] = ids.compactMap { id in
                guard let money = try? Money.parse(
                    customAmounts[id] ?? "",
                    currencyCode: currencyCode,
                    locale: Locale(identifier: "en_US_POSIX")
                ) else { return nil }
                return (id, money)
            }
            guard shares.count == ids.count,
                  let sum = try? MoneyAccounting.sumChecked(
                      shares.map(\.1),
                      currencyCode: currencyCode
                  ).get(),
                  sum.minorUnits == totalMoney.minorUnits else { return nil }
            return shares.map { (memberId: $0.0, money: $0.1) }

        case .equally:
            guard let allocations = try? totalMoney.allocatedEqually(among: ids, payerID: payerId) else {
                return nil
            }
            return ids.compactMap { id in
                guard let share = allocations[id] else { return nil }
                return (id, share)
            }
        }
    }

    func buildTransaction(
        addedBy member: BudgetMember,
        createdByUserId: UUID? = nil,
        currencyCode: String = CurrencyOption.usd.code,
        date: Date? = nil
    ) -> Transaction? {
        guard let money = parsedMoney(currencyCode: currencyCode) else { return nil }
        let amount = MoneyAccounting.doubleValue(of: money)

        let transaction = Transaction(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            amountMinorUnits: money.minorUnits,
            currencyCode: money.currencyCode,
            type: type,
            category: category,
            paymentMethod: paymentMethod,
            createdByMemberId: member.id,
            createdByUserId: createdByUserId,
            date: date ?? self.date,
            recurrenceRule: recurrenceRule
        )
        transaction.needsSync = true
        return transaction
    }

    func applyChanges(
        to transaction: Transaction,
        paidBy member: BudgetMember,
        currencyCode: String = CurrencyOption.usd.code
    ) {
        guard let money = parsedMoney(currencyCode: currencyCode) else { return }
        let amount = MoneyAccounting.doubleValue(of: money)
        transaction.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.amount = amount
        transaction.amountMinorUnits = money.minorUnits
        transaction.currencyCode = money.currencyCode
        transaction.type = type
        transaction.category = category
        transaction.paymentMethod = paymentMethod
        transaction.createdByMemberId = member.id
        transaction.date = date
        transaction.recurrenceRule = recurrenceRule
        transaction.needsSync = true
    }

    func updateAvailableExpenseCategories(from settings: BudgetSettings) {
        hiddenExpenseCategoryRawValues = Set(
            settings.categoryBudgets.keys.compactMap { key in
                guard TransactionCategory.isHiddenMarkerKey(key) else { return nil }
                return String(key.dropFirst(TransactionCategory.hiddenCategoryPrefix.count))
            }
        )
        customExpenseCategories = settings.legacyCategoryBudgets.keys
            .filter { key in
                !TransactionCategory.builtInRawValues.contains(key) &&
                !BudgetSettings.isInternalBudgetKey(key)
            }
            .map(TransactionCategory.init(rawValue:))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        ensureCategoryMatchesType()
    }

    private var recurrenceRule: String? {
        guard repeatsMonthly else { return nil }
        return Transaction.monthlyRecurrenceRule(until: hasRecurrenceEndDate ? recurrenceEndDate : nil)
    }

    private func parsedMoney(currencyCode: String) -> Money? {
        try? Money.parse(
            amountText,
            currencyCode: currencyCode,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func ensureCategoryMatchesType() {
        if !availableCategories.contains(category) {
            category = availableCategories.first ?? .other
        }
    }

    private static func sanitizedMoneyText(_ text: String, currencyCode: String) -> String {
        let maximumFractionDigits = (try? CurrencyMetadata(code: currencyCode))?.fractionDigits ?? 2
        var result = ""
        var hasDecimalSeparator = false
        var fractionalDigitCount = 0

        for character in text {
            if character.isNumber {
                if hasDecimalSeparator {
                    guard maximumFractionDigits > 0,
                          fractionalDigitCount < maximumFractionDigits else { continue }
                    fractionalDigitCount += 1
                }
                result.append(character)
            } else if character == "." || character == "," {
                if maximumFractionDigits == 0 {
                    hasDecimalSeparator = true
                    continue
                }
                guard !hasDecimalSeparator else { continue }
                hasDecimalSeparator = true
                result.append(".")
            }
        }

        return result
    }
}

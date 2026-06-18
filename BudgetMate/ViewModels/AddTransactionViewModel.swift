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
        amountText = String(format: "%.2f", transaction.amount)
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
                uniqueKeysWithValues: transaction.splits.map {
                    ($0.memberId, String(format: "%.2f", $0.amount))
                }
            )
        }
    }

    var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              parsedAmount != nil else { return false }
        return isSplitValid
    }

    var parsedAmount: Double? {
        guard let value = Double(amountText), value > 0 else { return nil }
        return value
    }

    // MARK: - Split helpers

    /// Sum of the amounts typed into the custom split fields for participants.
    var customSplitTotal: Double {
        participants.reduce(0) { $0 + (Double(customAmounts[$1] ?? "") ?? 0) }
    }

    var isSplitValid: Bool {
        guard isSplit, isSplittable else { return true }
        guard !participants.isEmpty, let total = parsedAmount else { return false }
        switch splitMethod {
        case .equally:
            return true
        case .custom:
            return abs(customSplitTotal - total) < 0.01
        }
    }

    var splitValidationMessage: String? {
        guard isSplit, isSplittable else { return nil }
        if participants.isEmpty { return "Select at least one member to split with." }
        guard let total = parsedAmount else { return "Enter an amount to split." }
        if splitMethod == .custom, abs(customSplitTotal - total) >= 0.01 {
            let diff = total - customSplitTotal
            if diff > 0 {
                return "Add \(String(format: "%.2f", diff)) more to match the total."
            } else {
                return "That's \(String(format: "%.2f", -diff)) over the total."
            }
        }
        return nil
    }

    /// Resolves the final per-member shares. `payerId` receives any rounding
    /// remainder for equal splits (or the first participant if not included).
    func resolvedSplits(payerId: UUID) -> [(memberId: UUID, amount: Double)]? {
        guard isSplit, isSplittable, let total = parsedAmount, !participants.isEmpty else { return nil }

        // Stable ordering with the payer first so remainder cents land there.
        let ids = participants.sorted { lhs, rhs in
            if lhs == payerId { return true }
            if rhs == payerId { return false }
            return lhs.uuidString < rhs.uuidString
        }

        switch splitMethod {
        case .custom:
            return ids.map { ($0, Double(customAmounts[$0] ?? "") ?? 0) }

        case .equally:
            let totalCents = Int((total * 100).rounded())
            let count = ids.count
            let baseCents = totalCents / count
            var remainder = totalCents % count

            return ids.map { id in
                var cents = baseCents
                if remainder > 0 {
                    cents += 1
                    remainder -= 1
                }
                return (id, Double(cents) / 100)
            }
        }
    }

    func buildTransaction(addedBy member: BudgetMember, date: Date? = nil) -> Transaction? {
        guard let amount = parsedAmount else { return nil }

        return Transaction(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            type: type,
            category: category,
            paymentMethod: paymentMethod,
            createdByMemberId: member.id,
            date: date ?? self.date,
            recurrenceRule: recurrenceRule
        )
    }

    func applyChanges(to transaction: Transaction, paidBy member: BudgetMember) {
        guard let amount = parsedAmount else { return }
        transaction.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.amount = amount
        transaction.type = type
        transaction.category = category
        transaction.paymentMethod = paymentMethod
        transaction.createdByMemberId = member.id
        transaction.date = date
        transaction.recurrenceRule = recurrenceRule
    }

    func updateAvailableExpenseCategories(from settings: BudgetSettings) {
        hiddenExpenseCategoryRawValues = Set(
            settings.categoryBudgets.keys.compactMap { key in
                guard TransactionCategory.isHiddenMarkerKey(key) else { return nil }
                return String(key.dropFirst(TransactionCategory.hiddenCategoryPrefix.count))
            }
        )
        customExpenseCategories = settings.categoryBudgets.keys
            .filter { key in
                !TransactionCategory.builtInRawValues.contains(key) &&
                !TransactionCategory.isHiddenMarkerKey(key)
            }
            .map(TransactionCategory.init(rawValue:))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        ensureCategoryMatchesType()
    }

    private var recurrenceRule: String? {
        guard repeatsMonthly else { return nil }
        return Transaction.monthlyRecurrenceRule(until: hasRecurrenceEndDate ? recurrenceEndDate : nil)
    }

    private func ensureCategoryMatchesType() {
        if !availableCategories.contains(category) {
            category = availableCategories.first ?? .other
        }
    }
}

import Foundation

/// Precomputed settlement / split-bill data so dashboard scrolling does not
/// re-walk every transaction and SwiftData relationship on each frame.
struct SettlementComputationCache {
    let suggestions: [SettlementSuggestion]
    let splitExpenses: [Transaction]
    let allSettlements: [Settlement]
    let transactionById: [UUID: Transaction]
    let settlementById: [UUID: Settlement]

    static let empty = SettlementComputationCache(
        suggestions: [],
        splitExpenses: [],
        allSettlements: [],
        transactionById: [:],
        settlementById: [:]
    )

    static func build(
        transactions: [Transaction],
        settlements: [Settlement],
        members: [BudgetMember]
    ) -> SettlementComputationCache {
        // Guard against a local store that ended up with duplicate rows for the
        // same id (e.g. from older multi-device syncs): deduplicate before
        // building keyed dictionaries so we never trap on a duplicate key and
        // never double-count split expenses.
        let transactions = transactions.deduplicatedByID()
        let settlements = settlements.deduplicatedByID()
        let splitExpenses = transactions.filter { $0.type == .expense && !$0.splits.isEmpty }
        let transactionById = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let settlementById = Dictionary(settlements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let suggestions = DashboardViewModel.settlements(
            splitExpenses: splitExpenses,
            settlementRecords: settlements,
            members: members
        )

        return SettlementComputationCache(
            suggestions: suggestions,
            splitExpenses: splitExpenses,
            allSettlements: settlements,
            transactionById: transactionById,
            settlementById: settlementById
        )
    }

    func makeBreakdownPresentation(for suggestion: SettlementSuggestion) -> BreakdownPresentation {
        let lineItems = DashboardViewModel.breakdown(
            from: suggestion.from,
            to: suggestion.to,
            splitExpenses: splitExpenses,
            settlements: allSettlements
        )

        var balanceContextByTransactionId: [UUID: TransactionBalanceContext] = [:]
        balanceContextByTransactionId.reserveCapacity(lineItems.count)
        for item in lineItems {
            guard let transactionId = item.transactionId else { continue }
            balanceContextByTransactionId[transactionId] = TransactionBalanceContext(
                explanation: item.subtitle,
                signedAmount: item.signedAmount
            )
        }

        return BreakdownPresentation(
            suggestion: suggestion,
            lineItems: lineItems,
            transactionById: transactionById,
            settlementById: settlementById,
            balanceContextByTransactionId: balanceContextByTransactionId
        )
    }
}

/// Sheet payload built once when a settlement row is opened.
struct BreakdownPresentation: Identifiable {
    let suggestion: SettlementSuggestion
    let lineItems: [BalanceLineItem]
    let transactionById: [UUID: Transaction]
    let settlementById: [UUID: Settlement]
    let balanceContextByTransactionId: [UUID: TransactionBalanceContext]

    var id: String { suggestion.id }
}

enum FinancialDataFingerprint {
    static func hash(transactions: [Transaction], settlements: [Settlement]) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(transactions.count)
        hasher.combine(settlements.count)
        for transaction in transactions {
            hasher.combine(transaction.id)
            hasher.combine(transaction.amount)
            hasher.combine(transaction.date)
            hasher.combine(transaction.recurrenceRule)
            hasher.combine(transaction.splits.count)
        }
        for settlement in settlements {
            hasher.combine(settlement.id)
            hasher.combine(settlement.amount)
            hasher.combine(settlement.date)
        }
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }
}

/// Month-scoped dashboard values derived off the main thread of SwiftUI body.
struct DashboardDerivedMetrics {
    var settlementCache: SettlementComputationCache = .empty
    var monthTransactions: [Transaction] = []
    var displayedTransactions: [Transaction] = []
    var totals: DashboardTotals = DashboardTotals(
        currentBalance: 0,
        totalIncome: 0,
        totalExpenses: 0,
        remainingBudget: 0
    )
    var expenseBreakdown: [ExpenseCategoryBreakdown] = []

    static func compute(
        transactions: [Transaction],
        settlements: [Settlement],
        members: [BudgetMember],
        monthInterval: DateInterval?,
        selectedMemberId: UUID?,
        monthlyBudget: Double
    ) -> DashboardDerivedMetrics {
        let transactions = transactions.deduplicatedByID()
        let settlements = settlements.deduplicatedByID()
        let settlementCache = SettlementComputationCache.build(
            transactions: transactions,
            settlements: settlements,
            members: members
        )

        let monthTransactions: [Transaction]
        if let monthInterval {
            monthTransactions = RecurringTransactionResolver.transactions(in: monthInterval, from: transactions)
        } else {
            monthTransactions = []
        }

        let displayedTransactions: [Transaction]
        if let selectedMemberId {
            displayedTransactions = monthTransactions.filter { $0.involves(memberId: selectedMemberId) }
        } else {
            displayedTransactions = monthTransactions
        }

        let totals = DashboardViewModel.totals(
            transactions: monthTransactions,
            monthlyBudget: monthlyBudget,
            forMember: selectedMemberId
        )

        let expenseBreakdown = DashboardViewModel.expenseBreakdown(
            transactions: monthTransactions,
            forMember: selectedMemberId
        )

        return DashboardDerivedMetrics(
            settlementCache: settlementCache,
            monthTransactions: monthTransactions,
            displayedTransactions: displayedTransactions,
            totals: totals,
            expenseBreakdown: expenseBreakdown
        )
    }
}

/// Cached values for the Budget tab (member spending + category rows).
struct BudgetTabMetrics {
    var netBalances: [UUID: Int] = [:]
    var monthlyExpenseTransactions: [Transaction] = []
    var expensesByMember: [(member: BudgetMember, total: Double)] = []
    var spentByCategory: [TransactionCategory: Double] = [:]

    var totalExpenses: Double {
        monthlyExpenseTransactions.reduce(0) { $0 + $1.amount }
    }

    static func compute(
        transactions: [Transaction],
        settlements: [Settlement],
        members: [BudgetMember],
        monthInterval: DateInterval?
    ) -> BudgetTabMetrics {
        let transactions = transactions.deduplicatedByID()
        let settlements = settlements.deduplicatedByID()
        let splitExpenses = transactions.filter { $0.type == .expense && !$0.splits.isEmpty }
        let netBalances = DashboardViewModel.netBalances(
            splitExpenses: splitExpenses,
            settlements: settlements
        )

        let monthlyExpenseTransactions: [Transaction]
        if let monthInterval {
            monthlyExpenseTransactions = RecurringTransactionResolver
                .transactions(in: monthInterval, from: transactions)
                .filter { $0.type == .expense }
        } else {
            monthlyExpenseTransactions = []
        }

        var spentByCategory: [TransactionCategory: Double] = [:]
        for transaction in monthlyExpenseTransactions {
            spentByCategory[transaction.category, default: 0] += transaction.amount
        }

        let expensesByMember = members.map { member in
            let total = monthlyExpenseTransactions.reduce(0) { partial, transaction in
                partial + transaction.consumedExpense(for: member.id)
            }
            return (member, total)
        }

        return BudgetTabMetrics(
            netBalances: netBalances,
            monthlyExpenseTransactions: monthlyExpenseTransactions,
            expensesByMember: expensesByMember,
            spentByCategory: spentByCategory
        )
    }
}

extension Array where Element: Identifiable {
    /// Returns the array with elements of duplicate `id` removed, keeping the
    /// first occurrence. Defends against a SwiftData store that contains
    /// duplicate rows for the same identifier.
    func deduplicatedByID() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}

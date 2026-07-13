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

    @MainActor
    static func build(
        transactions: [Transaction],
        settlements: [Settlement],
        members: [BudgetMember]
    ) async throws -> SettlementComputationCache {
        // DashboardDerivedMetrics normalizes these arrays once before calling
        // us. Build the relationship-backed portion cooperatively so presenting
        // the transaction editor can cancel between small batches.
        var splitExpenses: [Transaction] = []
        var transactionById: [UUID: Transaction] = [:]
        splitExpenses.reserveCapacity(transactions.count)
        transactionById.reserveCapacity(transactions.count)

        for (index, transaction) in transactions.enumerated() {
            if index.isMultiple(of: 64) {
                try Task.checkCancellation()
                await Task.yield()
            }

            transactionById[transaction.id] = transaction
            if transaction.type == .expense, !transaction.splits.isEmpty {
                splitExpenses.append(transaction)
            }
        }

        var settlementById: [UUID: Settlement] = [:]
        settlementById.reserveCapacity(settlements.count)
        for (index, settlement) in settlements.enumerated() {
            if index.isMultiple(of: 128) {
                try Task.checkCancellation()
                await Task.yield()
            }
            settlementById[settlement.id] = settlement
        }

        try Task.checkCancellation()
        await Task.yield()
        let suggestions = DashboardViewModel.settlements(
            splitExpenses: splitExpenses,
            settlementRecords: settlements,
            members: members
        )
        try Task.checkCancellation()

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
    static func hash(
        transactions: [Transaction],
        settlements: [Settlement],
        includeSplitCounts: Bool = true
    ) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(transactions.count)
        hasher.combine(settlements.count)
        for transaction in transactions {
            hasher.combine(transaction.id)
            hasher.combine(transaction.amount)
            hasher.combine(transaction.date)
            hasher.combine(transaction.recurrenceRule)
            if includeSplitCounts {
                hasher.combine(transaction.splits.count)
            }
        }
        for settlement in settlements {
            hasher.combine(settlement.id)
            hasher.combine(settlement.amount)
            hasher.combine(settlement.date)
        }
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    /// A dashboard revision that deliberately reads only scalar model fields.
    /// Split relationships can fault from SwiftData one transaction at a time,
    /// so they are inspected later by the cancellable metrics loader instead of
    /// during every SwiftUI body evaluation. `needsSync` catches local split
    /// edits; CloudSyncStore.lastSyncedAt is added by the loader for remote ones.
    static func shallowDashboardRevision(
        transactions: [Transaction],
        settlements: [Settlement],
        members: [BudgetMember]
    ) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(transactions.count)
        hasher.combine(settlements.count)
        hasher.combine(members.count)

        for transaction in transactions {
            hasher.combine(transaction.id)
            hasher.combine(transaction.title)
            hasher.combine(transaction.amount)
            hasher.combine(transaction.type.rawValue)
            hasher.combine(transaction.category.rawValue)
            hasher.combine(transaction.paymentMethod?.rawValue)
            hasher.combine(transaction.createdByMemberId)
            hasher.combine(transaction.date)
            hasher.combine(transaction.createdAt)
            hasher.combine(transaction.recurrenceRule)
            hasher.combine(transaction.ownerUserId)
            hasher.combine(transaction.needsSync)
        }

        for settlement in settlements {
            hasher.combine(settlement.id)
            hasher.combine(settlement.fromMemberId)
            hasher.combine(settlement.toMemberId)
            hasher.combine(settlement.amount)
            hasher.combine(settlement.date)
            hasher.combine(settlement.ownerUserId)
            hasher.combine(settlement.needsSync)
        }

        for member in members {
            hasher.combine(member.id)
            hasher.combine(member.displayName)
            hasher.combine(member.email)
            hasher.combine(member.displayInitials)
            hasher.combine(member.colorHex)
            hasher.combine(member.authUserId)
            hasher.combine(member.role.rawValue)
            hasher.combine(member.inviteStatus.rawValue)
            hasher.combine(member.joinedDate)
            hasher.combine(member.createdDate)
        }

        return UInt64(bitPattern: Int64(hasher.finalize()))
    }
}

/// Month-scoped dashboard values cached outside repeated SwiftUI body reads.
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

    @MainActor
    static func compute(
        transactions: [Transaction],
        settlements: [Settlement],
        members: [BudgetMember],
        monthInterval: DateInterval?,
        selectedMemberId: UUID?,
        monthlyBudget: Double,
        computeSettlements: Bool = true
    ) async throws -> DashboardDerivedMetrics {
        try Task.checkCancellation()
        let transactions = transactions.deduplicatedByID()
        let settlements = computeSettlements ? settlements.deduplicatedByID() : []

        await Task.yield()
        try Task.checkCancellation()

        let settlementCache: SettlementComputationCache
        if computeSettlements {
            settlementCache = try await SettlementComputationCache.build(
                transactions: transactions,
                settlements: settlements,
                members: members
            )
        } else {
            settlementCache = .empty
        }

        await Task.yield()
        try Task.checkCancellation()

        let monthTransactions: [Transaction]
        if let monthInterval {
            monthTransactions = RecurringTransactionResolver.transactions(
                in: monthInterval,
                from: transactions,
                alreadyDeduplicated: true
            )
        } else {
            monthTransactions = []
        }

        await Task.yield()
        try Task.checkCancellation()

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

        try Task.checkCancellation()

        return DashboardDerivedMetrics(
            settlementCache: settlementCache,
            monthTransactions: monthTransactions,
            displayedTransactions: displayedTransactions,
            totals: totals,
            expenseBreakdown: expenseBreakdown
        )
    }
}

/// Cached values for the Transactions tab so recurring resolution, member
/// filtering, day grouping, and summary totals run once per data change
/// instead of several times per SwiftUI body evaluation.
struct TransactionsTabMetrics {
    var filteredTransactions: [Transaction] = []
    var groupedByDay: [(date: Date, items: [Transaction])] = []
    var summaryTotals: DashboardTotals = DashboardTotals(
        currentBalance: 0,
        totalIncome: 0,
        totalExpenses: 0,
        remainingBudget: 0
    )

    static func compute(
        transactions: [Transaction],
        monthInterval: DateInterval?,
        selectedMemberId: UUID?,
        monthlyBudget: Double
    ) -> TransactionsTabMetrics {
        let monthTransactions: [Transaction]
        if let monthInterval {
            monthTransactions = RecurringTransactionResolver.transactions(
                in: monthInterval,
                from: transactions.deduplicatedByID(),
                alreadyDeduplicated: true
            )
        } else {
            monthTransactions = []
        }

        let filteredTransactions: [Transaction]
        if let selectedMemberId {
            filteredTransactions = monthTransactions.filter { $0.involves(memberId: selectedMemberId) }
        } else {
            filteredTransactions = monthTransactions
        }

        let calendar = Calendar.current
        let groupedByDay = Dictionary(grouping: filteredTransactions) { calendar.startOfDay(for: $0.date) }
            .map { (date: $0.key, items: sortedNewestFirst($0.value)) }
            .sorted { $0.date > $1.date }

        let summaryTotals = DashboardViewModel.totals(
            transactions: filteredTransactions,
            monthlyBudget: monthlyBudget,
            forMember: selectedMemberId
        )

        return TransactionsTabMetrics(
            filteredTransactions: filteredTransactions,
            groupedByDay: groupedByDay,
            summaryTotals: summaryTotals
        )
    }

    private static func sortedNewestFirst(_ transactions: [Transaction]) -> [Transaction] {
        transactions.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
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
                .transactions(in: monthInterval, from: transactions, alreadyDeduplicated: true)
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

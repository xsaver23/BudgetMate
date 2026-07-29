import Foundation

/// Precomputed settlement / split-bill data so dashboard scrolling does not
/// re-walk every transaction and SwiftData relationship on each frame.
struct SettlementComputationCache {
    let suggestions: [SettlementSuggestion]
    let splitExpenses: [Transaction]
    let allSettlements: [Settlement]
    let transactionById: [UUID: Transaction]
    let settlementById: [UUID: Settlement]
    let anomalies: [MoneyAccounting.ComputationAnomaly]

    static let empty = SettlementComputationCache(
        suggestions: [],
        splitExpenses: [],
        allSettlements: [],
        transactionById: [:],
        settlementById: [:]
        , anomalies: []
    )

    @MainActor
    static func build(
        transactions: [Transaction],
        settlements: [Settlement],
        members: [BudgetMember],
        currencyCode: String = CurrencyOption.usd.code
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
        let suggestionComputation = DashboardViewModel.settlementsResult(
            splitExpenses: splitExpenses,
            settlementRecords: settlements,
            members: members,
            currencyCode: currencyCode
        )
        try Task.checkCancellation()

        return SettlementComputationCache(
            suggestions: suggestionComputation.suggestions,
            splitExpenses: splitExpenses,
            allSettlements: settlements,
            transactionById: transactionById,
            settlementById: settlementById,
            anomalies: suggestionComputation.anomalies
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
            hasher.combine(transaction.amountMinorUnits)
            hasher.combine(transaction.currencyCode)
            hasher.combine(transaction.date)
            hasher.combine(transaction.recurrenceRule)
            if includeSplitCounts {
                hasher.combine(transaction.splits.count)
                for split in transaction.splits {
                    hasher.combine(split.amountMinorUnits)
                    hasher.combine(split.currencyCode)
                }
            }
        }
        for settlement in settlements {
            hasher.combine(settlement.id)
            hasher.combine(settlement.amount)
            hasher.combine(settlement.amountMinorUnits)
            hasher.combine(settlement.currencyCode)
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
            hasher.combine(transaction.amountMinorUnits)
            hasher.combine(transaction.currencyCode)
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
            hasher.combine(settlement.amountMinorUnits)
            hasher.combine(settlement.currencyCode)
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
    var anomalies: [MoneyAccounting.ComputationAnomaly] = []

    @MainActor
    static func compute(
        transactions: [Transaction],
        settlements: [Settlement],
        members: [BudgetMember],
        monthInterval: DateInterval?,
        selectedMemberId: UUID?,
        monthlyBudget: Double,
        currencyCode: String = CurrencyOption.usd.code,
        calendar: Calendar = .current,
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
                members: members,
                currencyCode: currencyCode
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
                calendar: calendar,
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
            forMember: selectedMemberId,
            currencyCode: currencyCode
        )

        let expenseBreakdownComputation = DashboardViewModel.expenseBreakdownResult(
            transactions: monthTransactions,
            forMember: selectedMemberId,
            currencyCode: currencyCode
        )

        try Task.checkCancellation()

        return DashboardDerivedMetrics(
            settlementCache: settlementCache,
            monthTransactions: monthTransactions,
            displayedTransactions: displayedTransactions,
            totals: totals,
            expenseBreakdown: expenseBreakdownComputation.breakdown,
            anomalies: Array(Set(
                settlementCache.anomalies + totals.anomalies + expenseBreakdownComputation.anomalies
            ))
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
        monthlyBudget: Double,
        currencyCode: String = CurrencyOption.usd.code
        , calendar: Calendar = .current
    ) -> TransactionsTabMetrics {
        let monthTransactions: [Transaction]
        if let monthInterval {
            monthTransactions = RecurringTransactionResolver.transactions(
                in: monthInterval,
                from: transactions.deduplicatedByID(),
                calendar: calendar,
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

        let groupedByDay = Dictionary(grouping: filteredTransactions) { calendar.startOfDay(for: $0.date) }
            .map { (date: $0.key, items: sortedNewestFirst($0.value)) }
            .sorted { $0.date > $1.date }

        let summaryTotals = DashboardViewModel.totals(
            transactions: filteredTransactions,
            monthlyBudget: monthlyBudget,
            forMember: selectedMemberId,
            currencyCode: currencyCode
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

/// The exact transaction subset and total used by a budget category row and
/// its read-only drill-down destination.
struct BudgetCategoryTransactionBreakdown {
    let categoryRawValue: String
    let budgetScopeId: String
    let transactions: [Transaction]
    let total: Double
    let currencyCode: String
    let anomalies: [MoneyAccounting.ComputationAnomaly]

    init(
        categoryRawValue: String,
        budgetScopeId: String,
        sourceTransactions: [Transaction],
        currencyCode: String = CurrencyOption.usd.code
    ) {
        self.categoryRawValue = categoryRawValue
        self.budgetScopeId = budgetScopeId
        self.currencyCode = currencyCode
        let filtered = sourceTransactions
            .filter {
                $0.ownerUserId == budgetScopeId &&
                    $0.type == .expense &&
                    $0.category.rawValue == categoryRawValue
            }
            .sorted(by: Self.newestFirst)
        transactions = filtered
        var values: [Money] = []
        var anomalies: [MoneyAccounting.ComputationAnomaly] = []
        for transaction in filtered {
            switch MoneyAccounting.checkedAmount(for: transaction, fallbackCurrencyCode: currencyCode) {
            case .success(let money): values.append(money)
            case .failure(let anomaly): anomalies.append(anomaly)
            }
        }
        switch MoneyAccounting.aggregateValue(
            values,
            currencyCode: currencyCode,
            sourceID: "category-\(categoryRawValue)"
        ) {
        case .success(let value): total = value
        case .failure(let anomaly):
            total = 0
            anomalies.append(anomaly)
        }
        self.anomalies = Array(Set(anomalies))
    }

    static func newestFirst(_ lhs: Transaction, _ rhs: Transaction) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// Cached values for the Budget tab (member spending + category rows).
struct BudgetTabMetrics {
    var netBalances: [UUID: Int64] = [:]
    var monthlyExpenseTransactions: [Transaction] = []
    var expensesByMember: [(member: BudgetMember, total: Double)] = []
    var spentByCategory: [TransactionCategory: Double] = [:]
    var currencyCode: String = CurrencyOption.usd.code
    var anomalies: [MoneyAccounting.ComputationAnomaly] = []
    var totalExpenses: Double = 0

    func categoryBreakdown(
        for category: TransactionCategory,
        budgetScopeId: String,
        currencyCode: String = CurrencyOption.usd.code
    ) -> BudgetCategoryTransactionBreakdown {
        BudgetCategoryTransactionBreakdown(
            categoryRawValue: category.rawValue,
            budgetScopeId: budgetScopeId,
            sourceTransactions: monthlyExpenseTransactions,
            currencyCode: currencyCode
        )
    }

    static func compute(
        transactions: [Transaction],
        settlements: [Settlement],
        members: [BudgetMember],
        monthInterval: DateInterval?,
        currencyCode: String = CurrencyOption.usd.code,
        budgetScopeId: String? = nil,
        calendar: Calendar = .current
    ) -> BudgetTabMetrics {
        let transactions = transactions
            .filter { budgetScopeId == nil || $0.ownerUserId == budgetScopeId }
            .deduplicatedByID()
        let settlements = settlements
            .filter { budgetScopeId == nil || $0.ownerUserId == budgetScopeId }
            .deduplicatedByID()
        let splitExpenses = transactions.filter { $0.type == .expense && !$0.splits.isEmpty }
        let balanceComputation = DashboardViewModel.netBalancesResult(
            splitExpenses: splitExpenses,
            settlements: settlements,
            currencyCode: currencyCode
        )

        let monthlyExpenseTransactions: [Transaction]
        if let monthInterval {
            monthlyExpenseTransactions = RecurringTransactionResolver
                .transactions(in: monthInterval, from: transactions, calendar: calendar, alreadyDeduplicated: true)
                .filter { $0.type == .expense }
        } else {
            monthlyExpenseTransactions = []
        }

        var anomalies = balanceComputation.anomalies
        for transaction in monthlyExpenseTransactions {
            if case .failure(let anomaly) = MoneyAccounting.checkedAmount(
                for: transaction,
                fallbackCurrencyCode: currencyCode
            ) {
                anomalies.append(anomaly)
            }
            for split in transaction.splits {
                if case .failure(let anomaly) = MoneyAccounting.checkedAmount(
                    for: split,
                    fallbackCurrencyCode: currencyCode
                ) {
                    anomalies.append(anomaly)
                }
            }
        }

        var spentByCategory: [TransactionCategory: [Money]] = [:]
        for transaction in monthlyExpenseTransactions {
            if case .success(let money) = MoneyAccounting.checkedAmount(
                for: transaction,
                fallbackCurrencyCode: currencyCode
            ) {
                spentByCategory[transaction.category, default: []].append(money)
            }
        }

        var expensesByMember: [(member: BudgetMember, total: Double)] = []
        for member in members {
            var values: [Money] = []
            for transaction in monthlyExpenseTransactions {
                if transaction.isSplit {
                    for split in transaction.splits where split.memberId == member.id {
                        if case .success(let money) = MoneyAccounting.checkedAmount(
                            for: split,
                            fallbackCurrencyCode: currencyCode
                        ) {
                            values.append(money)
                        }
                    }
                } else if transaction.createdByMemberId == member.id,
                          case .success(let money) = MoneyAccounting.checkedAmount(
                              for: transaction,
                              fallbackCurrencyCode: currencyCode
                          ) {
                    values.append(money)
                }
            }
            let total: Double
            switch MoneyAccounting.aggregateValue(
                values,
                currencyCode: currencyCode,
                sourceID: "member-\(member.id.uuidString)"
            ) {
            case .success(let value): total = value
            case .failure(let anomaly):
                anomalies.append(anomaly)
                total = 0
            }
            expensesByMember.append((member, total))
        }

        var totalValues: [Money] = []
        for transaction in monthlyExpenseTransactions {
            if case .success(let money) = MoneyAccounting.checkedAmount(
                for: transaction,
                fallbackCurrencyCode: currencyCode
            ) {
                totalValues.append(money)
            }
        }
        let totalExpenses: Double
        switch MoneyAccounting.aggregateValue(totalValues, currencyCode: currencyCode, sourceID: "budget-total") {
        case .success(let value): totalExpenses = value
        case .failure(let anomaly):
            anomalies.append(anomaly)
            totalExpenses = 0
        }

        var categoryTotals: [TransactionCategory: Double] = [:]
        for (category, values) in spentByCategory {
            switch MoneyAccounting.aggregateValue(
                values,
                currencyCode: currencyCode,
                sourceID: "category-\(category.rawValue)"
            ) {
            case .success(let value): categoryTotals[category] = value
            case .failure(let anomaly): anomalies.append(anomaly); categoryTotals[category] = 0
            }
        }

        return BudgetTabMetrics(
            netBalances: balanceComputation.balances,
            monthlyExpenseTransactions: monthlyExpenseTransactions,
            expensesByMember: expensesByMember,
            spentByCategory: categoryTotals,
            currencyCode: currencyCode,
            anomalies: Array(Set(anomalies)),
            totalExpenses: totalExpenses
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

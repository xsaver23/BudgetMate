import Foundation

struct DashboardTotals {
    let currentBalance: Double
    let totalIncome: Double
    let totalExpenses: Double
    let remainingBudget: Double
    let anomalies: [MoneyAccounting.ComputationAnomaly]

    init(
        currentBalance: Double,
        totalIncome: Double,
        totalExpenses: Double,
        remainingBudget: Double,
        anomalies: [MoneyAccounting.ComputationAnomaly] = []
    ) {
        self.currentBalance = currentBalance
        self.totalIncome = totalIncome
        self.totalExpenses = totalExpenses
        self.remainingBudget = remainingBudget
        self.anomalies = anomalies
    }
}

struct ExpenseCategoryBreakdown: Identifiable {
    let category: TransactionCategory
    let amount: Double

    var id: String { category.rawValue }
}

struct ExpenseBreakdownComputation {
    let breakdown: [ExpenseCategoryBreakdown]
    let anomalies: [MoneyAccounting.ComputationAnomaly]
}

/// A simplified "X pays Y" suggestion to clear split-bill debts.
struct SettlementSuggestion: Identifiable {
    let from: BudgetMember
    let to: BudgetMember
    let amountMinorUnits: Int64
    let currencyCode: String

    var amount: Double {
        guard let money = try? Money(minorUnits: amountMinorUnits, currencyCode: currencyCode) else { return 0 }
        return MoneyAccounting.doubleValue(of: money)
    }

    var id: String { "\(from.id)-\(to.id)" }
}

private struct DirectionalBalanceKey: Hashable {
    let from: UUID
    let to: UUID
}

struct NetBalanceComputation {
    let balances: [UUID: Int64]
    let anomalies: [MoneyAccounting.ComputationAnomaly]
}

struct SettlementSuggestionsComputation {
    let suggestions: [SettlementSuggestion]
    let anomalies: [MoneyAccounting.ComputationAnomaly]
}

/// One contributing line in a pairwise balance breakdown between two members.
/// `signedAmount` is positive when it increases what the debtor owes the
/// creditor, and negative when it reduces that debt.
struct BalanceLineItem: Identifiable {
    enum Kind {
        case debtorShare   // creditor paid; debtor consumed a share
        case creditorShare // debtor paid; creditor consumed a share (reduces debt)
        case settlement
    }

    let id: String
    let title: String
    let subtitle: String
    let date: Date
    let category: TransactionCategory?
    let signedAmount: Double
    let kind: Kind
    let transactionId: UUID?
    let settlementId: UUID?

    var isTappable: Bool { transactionId != nil || settlementId != nil }
}

enum DashboardViewModel {
    /// Totals across the given transactions. When `memberId` is provided, income
    /// is attributed to its creator and expenses use that member's split share.
    static func totals(
        transactions: [Transaction],
        monthlyBudget: Double,
        forMember memberId: UUID? = nil,
        currencyCode: String = CurrencyOption.usd.code
    ) -> DashboardTotals {
        var anomalies: [MoneyAccounting.ComputationAnomaly] = []
        let incomeValues = transactions.compactMap { transaction -> Money? in
            guard transaction.type == .income,
                  memberId == nil || transaction.createdByMemberId == memberId else { return nil }
            switch MoneyAccounting.checkedAmount(for: transaction, fallbackCurrencyCode: currencyCode) {
            case .success(let money): return money
            case .failure(let anomaly): anomalies.append(anomaly); return nil
            }
        }
        let totalIncome: Double
        switch MoneyAccounting.sumChecked(incomeValues, currencyCode: currencyCode) {
        case .success(let total): totalIncome = MoneyAccounting.doubleValue(of: total)
        case .failure(let anomaly):
            anomalies.append(anomaly)
            totalIncome = 0
        }

        let expenseValues = transactions.filter { transaction in
            guard transaction.type == .expense else { return false }
            if let memberId {
                return transaction.involves(memberId: memberId)
            }
            return true
        }.flatMap { transaction -> [Money] in
            if let memberId {
                if transaction.isSplit {
                    return transaction.splits
                        .filter { $0.memberId == memberId }
                        .compactMap {
                            switch MoneyAccounting.checkedAmount(for: $0, fallbackCurrencyCode: currencyCode) {
                            case .success(let money): return money
                            case .failure(let anomaly): anomalies.append(anomaly); return nil
                            }
                        }
                }
                guard transaction.createdByMemberId == memberId else { return [] }
                guard case .success(let money) = MoneyAccounting.checkedAmount(
                    for: transaction,
                    fallbackCurrencyCode: currencyCode
                ) else {
                    if case .failure(let anomaly) = MoneyAccounting.checkedAmount(for: transaction, fallbackCurrencyCode: currencyCode) {
                        anomalies.append(anomaly)
                    }
                    return []
                }
                return [money]
            }
            switch MoneyAccounting.checkedAmount(for: transaction, fallbackCurrencyCode: currencyCode) {
            case .success(let money): return [money]
            case .failure(let anomaly): anomalies.append(anomaly); return []
            }
        }
        let totalExpenses: Double
        switch MoneyAccounting.sumChecked(expenseValues, currencyCode: currencyCode) {
        case .success(let total): totalExpenses = MoneyAccounting.doubleValue(of: total)
        case .failure(let anomaly):
            anomalies.append(anomaly)
            totalExpenses = 0
        }

        return DashboardTotals(
            currentBalance: totalIncome - totalExpenses,
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            remainingBudget: monthlyBudget - totalExpenses,
            anomalies: Array(Set(anomalies))
        )
    }

    /// Net position per member from split bills (minus recorded settlements), in currency minor units.
    /// Positive = the member is owed money; negative = the member owes money.
    static func netBalances(
        transactions: [Transaction],
        settlements: [Settlement] = [],
        currencyCode: String = CurrencyOption.usd.code
    ) -> [UUID: Int64] {
        let splitExpenses = transactions.filter { $0.type == .expense && !$0.splits.isEmpty }
        return netBalances(
            splitExpenses: splitExpenses,
            settlements: settlements,
            currencyCode: currencyCode
        )
    }

    static func netBalances(
        splitExpenses: [Transaction],
        settlements: [Settlement] = [],
        currencyCode: String = CurrencyOption.usd.code
    ) -> [UUID: Int64] {
        netBalancesResult(
            splitExpenses: splitExpenses,
            settlements: settlements,
            currencyCode: currencyCode
        ).balances
    }

    static func netBalancesResult(
        splitExpenses: [Transaction],
        settlements: [Settlement] = [],
        currencyCode: String = CurrencyOption.usd.code
    ) -> NetBalanceComputation {
        var balances: [UUID: Int64] = [:]
        var anomalies: [MoneyAccounting.ComputationAnomaly] = []

        for transaction in splitExpenses {
            var shared: Int64 = 0
            for split in transaction.splits {
                guard case .success(let money) = MoneyAccounting.checkedAmount(for: split, fallbackCurrencyCode: currencyCode) else {
                    if case .failure(let anomaly) = MoneyAccounting.checkedAmount(for: split, fallbackCurrencyCode: currencyCode) { anomalies.append(anomaly) }
                    continue
                }
                let memberResult = balances[split.memberId, default: 0].subtractingReportingOverflow(money.minorUnits)
                let sharedResult = shared.addingReportingOverflow(money.minorUnits)
                guard !memberResult.overflow, !sharedResult.overflow else {
                    anomalies.append(.init(sourceID: transaction.id.uuidString, reason: .arithmeticOverflow))
                    continue
                }
                balances[split.memberId] = memberResult.partialValue
                shared = sharedResult.partialValue
            }
            let payerResult = balances[transaction.createdByMemberId, default: 0].addingReportingOverflow(shared)
            if payerResult.overflow {
                anomalies.append(.init(sourceID: transaction.id.uuidString, reason: .arithmeticOverflow))
            } else {
                balances[transaction.createdByMemberId] = payerResult.partialValue
            }
        }

        for settlement in settlements {
            guard case .success(let money) = MoneyAccounting.checkedAmount(for: settlement, fallbackCurrencyCode: currencyCode) else {
                if case .failure(let anomaly) = MoneyAccounting.checkedAmount(for: settlement, fallbackCurrencyCode: currencyCode) { anomalies.append(anomaly) }
                continue
            }
            let fromResult = balances[settlement.fromMemberId, default: 0].addingReportingOverflow(money.minorUnits)
            let toResult = balances[settlement.toMemberId, default: 0].subtractingReportingOverflow(money.minorUnits)
            guard !fromResult.overflow, !toResult.overflow else {
                anomalies.append(.init(sourceID: settlement.id.uuidString, reason: .arithmeticOverflow))
                continue
            }
            balances[settlement.fromMemberId] = fromResult.partialValue
            balances[settlement.toMemberId] = toResult.partialValue
        }

        return NetBalanceComputation(balances: balances, anomalies: Array(Set(anomalies)))
    }

    /// Pairwise "who owes whom" balances. This favors clarity over minimizing
    /// the number of transfers, so users can see direct member-to-member debts.
    static func settlements(
        transactions: [Transaction],
        settlementRecords: [Settlement] = [],
        members: [BudgetMember],
        currencyCode: String = CurrencyOption.usd.code
    ) -> [SettlementSuggestion] {
        let splitExpenses = transactions.filter { $0.type == .expense && !$0.splits.isEmpty }
        return settlements(
            splitExpenses: splitExpenses,
            settlementRecords: settlementRecords,
            members: members,
            currencyCode: currencyCode
        )
    }

    static func settlements(
        splitExpenses: [Transaction],
        settlementRecords: [Settlement] = [],
        members: [BudgetMember],
        currencyCode: String = CurrencyOption.usd.code
    ) -> [SettlementSuggestion] {
        return settlementsResult(
            splitExpenses: splitExpenses,
            settlementRecords: settlementRecords,
            members: members,
            currencyCode: currencyCode
        ).suggestions
    }

    static func settlementsResult(
        splitExpenses: [Transaction],
        settlementRecords: [Settlement] = [],
        members: [BudgetMember],
        currencyCode: String = CurrencyOption.usd.code
    ) -> SettlementSuggestionsComputation {
        guard members.count > 1 else { return .init(suggestions: [], anomalies: []) }

        let membersById = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var directionalMinorUnits: [DirectionalBalanceKey: Int64] = [:]
        var anomalies: [MoneyAccounting.ComputationAnomaly] = []

        for transaction in splitExpenses {
            let payerId = transaction.createdByMemberId
            for split in transaction.splits where split.memberId != payerId {
                guard case .success(let money) = MoneyAccounting.checkedAmount(for: split, fallbackCurrencyCode: currencyCode) else {
                    if case .failure(let anomaly) = MoneyAccounting.checkedAmount(for: split, fallbackCurrencyCode: currencyCode) { anomalies.append(anomaly) }
                    continue
                }
                guard money.minorUnits > 0 else { continue }
                let key = DirectionalBalanceKey(from: split.memberId, to: payerId)
                let result = directionalMinorUnits[key, default: 0].addingReportingOverflow(money.minorUnits)
                guard !result.overflow else {
                    anomalies.append(.init(sourceID: transaction.id.uuidString, reason: .arithmeticOverflow))
                    continue
                }
                directionalMinorUnits[key] = result.partialValue
            }
        }

        for settlement in settlementRecords {
            guard case .success(let money) = MoneyAccounting.checkedAmount(for: settlement, fallbackCurrencyCode: currencyCode) else {
                if case .failure(let anomaly) = MoneyAccounting.checkedAmount(for: settlement, fallbackCurrencyCode: currencyCode) { anomalies.append(anomaly) }
                continue
            }
            guard money.minorUnits > 0 else { continue }
            let key = DirectionalBalanceKey(from: settlement.fromMemberId, to: settlement.toMemberId)
            let result = directionalMinorUnits[key, default: 0].subtractingReportingOverflow(money.minorUnits)
            guard !result.overflow else {
                anomalies.append(.init(sourceID: settlement.id.uuidString, reason: .arithmeticOverflow))
                continue
            }
            directionalMinorUnits[key] = result.partialValue
        }

        var processedPairs = Set<Set<UUID>>()
        var suggestions: [SettlementSuggestion] = []

        for (key, minorUnits) in directionalMinorUnits {
            let pair = Set([key.from, key.to])
            guard !processedPairs.contains(pair) else { continue }
            processedPairs.insert(pair)

            let reverseKey = DirectionalBalanceKey(from: key.to, to: key.from)
            let netResult = minorUnits.subtractingReportingOverflow(directionalMinorUnits[reverseKey, default: 0])
            guard !netResult.overflow else {
                anomalies.append(.init(sourceID: "pair-\(key.from)-\(key.to)", reason: .arithmeticOverflow))
                continue
            }
            let netMinorUnits = netResult.partialValue
            guard netMinorUnits != 0 else { continue }

            let fromId = netMinorUnits > 0 ? key.from : key.to
            let toId = netMinorUnits > 0 ? key.to : key.from
            guard netMinorUnits != Int64.min else {
                anomalies.append(.init(sourceID: "pair-\(key.from)-\(key.to)", reason: .arithmeticOverflow))
                continue
            }
            let amountMinorUnits = abs(netMinorUnits)

            if let from = membersById[fromId], let to = membersById[toId] {
                suggestions.append(SettlementSuggestion(
                    from: from,
                    to: to,
                    amountMinorUnits: amountMinorUnits,
                    currencyCode: currencyCode
                ))
            }
        }

        let sortedSuggestions = suggestions.sorted {
            if $0.amountMinorUnits == $1.amountMinorUnits {
                return $0.from.displayName < $1.from.displayName
            }
            return $0.amountMinorUnits > $1.amountMinorUnits
        }
        return SettlementSuggestionsComputation(suggestions: sortedSuggestions, anomalies: Array(Set(anomalies)))
    }

    /// Itemized explanation of the net balance between a debtor (`from`) and a
    /// creditor (`to`): every split bill and settlement that moves money between
    /// just those two members. The signed amounts sum to the pairwise net debt.
    static func breakdown(
        from debtor: BudgetMember,
        to creditor: BudgetMember,
        transactions: [Transaction],
        settlements: [Settlement] = []
    ) -> [BalanceLineItem] {
        let splitExpenses = transactions.filter { $0.type == .expense && !$0.splits.isEmpty }
        return breakdown(
            from: debtor,
            to: creditor,
            splitExpenses: splitExpenses,
            settlements: settlements
        )
    }

    static func breakdown(
        from debtor: BudgetMember,
        to creditor: BudgetMember,
        splitExpenses: [Transaction],
        settlements: [Settlement] = []
    ) -> [BalanceLineItem] {
        let debtorName = firstName(debtor)
        let creditorName = firstName(creditor)
        var items: [BalanceLineItem] = []
        items.reserveCapacity(splitExpenses.count)

        for transaction in splitExpenses {
            let debtorShare = transaction.consumedExpense(for: debtor.id)
            let creditorShare = transaction.consumedExpense(for: creditor.id)
            let payer = transaction.createdByMemberId

            if payer == creditor.id && debtorShare > 0 {
                // Creditor fronted the bill; debtor owes their share.
                items.append(
                    BalanceLineItem(
                        id: transaction.id.uuidString,
                        title: transaction.title,
                        subtitle: "\(creditorName) paid for \(debtorName)",
                        date: transaction.date,
                        category: transaction.category,
                        signedAmount: debtorShare,
                        kind: .debtorShare,
                        transactionId: transaction.id,
                        settlementId: nil
                    )
                )
            } else if payer == debtor.id && creditorShare > 0 {
                // Debtor fronted the bill; creditor's share reduces the debt.
                items.append(
                    BalanceLineItem(
                        id: transaction.id.uuidString,
                        title: transaction.title,
                        subtitle: "\(debtorName) paid for \(creditorName)",
                        date: transaction.date,
                        category: transaction.category,
                        signedAmount: -creditorShare,
                        kind: .creditorShare,
                        transactionId: transaction.id,
                        settlementId: nil
                    )
                )
            }
        }

        for settlement in settlements {
            if settlement.fromMemberId == debtor.id && settlement.toMemberId == creditor.id {
                items.append(
                    BalanceLineItem(
                        id: settlement.id.uuidString,
                        title: "Settled up",
                        subtitle: "\(debtorName) paid \(creditorName)",
                        date: settlement.date,
                        category: nil,
                        signedAmount: -settlement.amount,
                        kind: .settlement,
                        transactionId: nil,
                        settlementId: settlement.id
                    )
                )
            } else if settlement.fromMemberId == creditor.id && settlement.toMemberId == debtor.id {
                items.append(
                    BalanceLineItem(
                        id: settlement.id.uuidString,
                        title: "Settled up",
                        subtitle: "\(creditorName) paid \(debtorName)",
                        date: settlement.date,
                        category: nil,
                        signedAmount: settlement.amount,
                        kind: .settlement,
                        transactionId: nil,
                        settlementId: settlement.id
                    )
                )
            }
        }

        return items.sorted { $0.date > $1.date }
    }

    private static func firstName(_ member: BudgetMember) -> String {
        let first = member.displayName.split(separator: " ").first.map(String.init) ?? member.displayName
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? member.displayName : trimmed
    }

    static func expenseBreakdown(
        transactions: [Transaction],
        forMember memberId: UUID? = nil,
        currencyCode: String = CurrencyOption.usd.code
    ) -> [ExpenseCategoryBreakdown] {
        expenseBreakdownResult(
            transactions: transactions,
            forMember: memberId,
            currencyCode: currencyCode
        ).breakdown
    }

    static func expenseBreakdownResult(
        transactions: [Transaction],
        forMember memberId: UUID? = nil,
        currencyCode: String = CurrencyOption.usd.code
    ) -> ExpenseBreakdownComputation {
        var totalsByCategory: [TransactionCategory: [Money]] = [:]
        var anomalies: [MoneyAccounting.ComputationAnomaly] = []

        for transaction in transactions where transaction.type == .expense {
            let amounts: [Money]
            if let memberId {
                if transaction.isSplit {
                    amounts = transaction.splits
                        .filter { $0.memberId == memberId }
                        .compactMap {
                            switch MoneyAccounting.checkedAmount(for: $0, fallbackCurrencyCode: currencyCode) {
                            case .success(let money): return money
                            case .failure(let anomaly): anomalies.append(anomaly); return nil
                            }
                        }
                } else if transaction.createdByMemberId == memberId,
                          case .success(let money) = MoneyAccounting.checkedAmount(
                            for: transaction,
                            fallbackCurrencyCode: currencyCode
                          ) {
                    amounts = [money]
                } else {
                    if transaction.createdByMemberId == memberId,
                       case .failure(let anomaly) = MoneyAccounting.checkedAmount(for: transaction, fallbackCurrencyCode: currencyCode) {
                        anomalies.append(anomaly)
                    }
                    amounts = []
                }
            } else {
                switch MoneyAccounting.checkedAmount(for: transaction, fallbackCurrencyCode: currencyCode) {
                case .success(let money): amounts = [money]
                case .failure(let anomaly): anomalies.append(anomaly); amounts = []
                }
            }
            guard !amounts.isEmpty else { continue }
            totalsByCategory[transaction.category, default: []].append(contentsOf: amounts)
        }

        var breakdown: [ExpenseCategoryBreakdown] = []
        for (category, values) in totalsByCategory {
            switch MoneyAccounting.aggregateValue(
                values,
                currencyCode: currencyCode,
                sourceID: "dashboard-category-\(category.rawValue)"
            ) {
            case .success(let amount):
                breakdown.append(ExpenseCategoryBreakdown(category: category, amount: amount))
            case .failure(let anomaly):
                anomalies.append(anomaly)
                breakdown.append(ExpenseCategoryBreakdown(category: category, amount: 0))
            }
        }
        return ExpenseBreakdownComputation(
            breakdown: breakdown.sorted { $0.amount > $1.amount },
            anomalies: Array(Set(anomalies))
        )
    }
}

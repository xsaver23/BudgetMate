import Foundation

struct DashboardTotals {
    let currentBalance: Double
    let totalIncome: Double
    let totalExpenses: Double
    let remainingBudget: Double
}

struct ExpenseCategoryBreakdown: Identifiable {
    let category: TransactionCategory
    let amount: Double

    var id: String { category.rawValue }
}

/// A simplified "X pays Y" suggestion to clear split-bill debts.
struct SettlementSuggestion: Identifiable {
    let from: BudgetMember
    let to: BudgetMember
    let amount: Double

    var id: String { "\(from.id)-\(to.id)" }
}

private struct DirectionalBalanceKey: Hashable {
    let from: UUID
    let to: UUID
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
        forMember memberId: UUID? = nil
    ) -> DashboardTotals {
        let totalIncome = transactions
            .filter { $0.type == .income }
            .reduce(0.0) { partial, transaction in
                if let memberId {
                    return partial + (transaction.createdByMemberId == memberId ? transaction.amount : 0)
                }
                return partial + transaction.amount
            }

        let totalExpenses = transactions
            .filter { $0.type == .expense }
            .reduce(0.0) { partial, transaction in
                if let memberId {
                    return partial + transaction.consumedExpense(for: memberId)
                }
                return partial + transaction.amount
            }

        return DashboardTotals(
            currentBalance: totalIncome - totalExpenses,
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            remainingBudget: monthlyBudget - totalExpenses
        )
    }

    /// Net position per member from split bills (minus recorded settlements), in cents.
    /// Positive = the member is owed money; negative = the member owes money.
    static func netBalances(
        transactions: [Transaction],
        settlements: [Settlement] = []
    ) -> [UUID: Int] {
        let splitExpenses = transactions.filter { $0.type == .expense && !$0.splits.isEmpty }
        return netBalances(splitExpenses: splitExpenses, settlements: settlements)
    }

    static func netBalances(
        splitExpenses: [Transaction],
        settlements: [Settlement] = []
    ) -> [UUID: Int] {
        var netCents: [UUID: Int] = [:]

        for transaction in splitExpenses {
            var sharedCents = 0
            for split in transaction.splits {
                let cents = Int((split.amount * 100).rounded())
                netCents[split.memberId, default: 0] -= cents
                sharedCents += cents
            }
            netCents[transaction.createdByMemberId, default: 0] += sharedCents
        }

        for settlement in settlements {
            let cents = Int((settlement.amount * 100).rounded())
            netCents[settlement.fromMemberId, default: 0] += cents
            netCents[settlement.toMemberId, default: 0] -= cents
        }

        return netCents
    }

    /// Pairwise "who owes whom" balances. This favors clarity over minimizing
    /// the number of transfers, so users can see direct member-to-member debts.
    static func settlements(
        transactions: [Transaction],
        settlementRecords: [Settlement] = [],
        members: [BudgetMember]
    ) -> [SettlementSuggestion] {
        let splitExpenses = transactions.filter { $0.type == .expense && !$0.splits.isEmpty }
        return settlements(
            splitExpenses: splitExpenses,
            settlementRecords: settlementRecords,
            members: members
        )
    }

    static func settlements(
        splitExpenses: [Transaction],
        settlementRecords: [Settlement] = [],
        members: [BudgetMember]
    ) -> [SettlementSuggestion] {
        guard members.count > 1 else { return [] }

        let membersById = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var directionalCents: [DirectionalBalanceKey: Int] = [:]

        for transaction in splitExpenses {
            let payerId = transaction.createdByMemberId
            for split in transaction.splits where split.memberId != payerId {
                let cents = Int((split.amount * 100).rounded())
                guard cents > 0 else { continue }
                directionalCents[DirectionalBalanceKey(from: split.memberId, to: payerId), default: 0] += cents
            }
        }

        for settlement in settlementRecords {
            let cents = Int((settlement.amount * 100).rounded())
            guard cents > 0 else { continue }
            directionalCents[DirectionalBalanceKey(from: settlement.fromMemberId, to: settlement.toMemberId), default: 0] -= cents
        }

        var processedPairs = Set<Set<UUID>>()
        var suggestions: [SettlementSuggestion] = []

        for (key, cents) in directionalCents {
            let pair = Set([key.from, key.to])
            guard !processedPairs.contains(pair) else { continue }
            processedPairs.insert(pair)

            let reverseKey = DirectionalBalanceKey(from: key.to, to: key.from)
            let netCents = cents - directionalCents[reverseKey, default: 0]
            guard netCents != 0 else { continue }

            let fromId = netCents > 0 ? key.from : key.to
            let toId = netCents > 0 ? key.to : key.from
            let amount = Double(abs(netCents)) / 100

            if let from = membersById[fromId], let to = membersById[toId] {
                suggestions.append(SettlementSuggestion(from: from, to: to, amount: amount))
            }
        }

        return suggestions.sorted {
            if $0.amount == $1.amount {
                return $0.from.displayName < $1.from.displayName
            }
            return $0.amount > $1.amount
        }
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
        forMember memberId: UUID? = nil
    ) -> [ExpenseCategoryBreakdown] {
        var totalsByCategory: [TransactionCategory: Double] = [:]

        for transaction in transactions where transaction.type == .expense {
            let amount = memberId != nil
                ? transaction.consumedExpense(for: memberId!)
                : transaction.amount
            guard amount > 0 else { continue }
            totalsByCategory[transaction.category, default: 0] += amount
        }

        return totalsByCategory
            .map { ExpenseCategoryBreakdown(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }
}

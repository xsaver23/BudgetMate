import Foundation
import SwiftData

/// Generates a realistic set of demo transactions (including split bills) and
/// inserts them into a `ModelContext`. Used for previews and the in-app
/// "Load Sample Data" developer action.
enum SampleDataSeeder {
    /// One demo row: payer is `payerIndex` into `members`; `splitAmong` lists
    /// member indices to split across (`nil` = not split).
    private struct Spec {
        let title: String
        let amount: Double
        let type: TransactionType
        let category: TransactionCategory
        let payment: PaymentMethod?
        let payerIndex: Int
        let day: Int
        let monthsAgo: Int
        let splitAmong: [Int]?
        let recurrenceRule: String?

        init(
            title: String,
            amount: Double,
            type: TransactionType,
            category: TransactionCategory,
            payment: PaymentMethod?,
            payerIndex: Int,
            day: Int,
            monthsAgo: Int,
            splitAmong: [Int]?,
            recurrenceRule: String? = nil
        ) {
            self.title = title
            self.amount = amount
            self.type = type
            self.category = category
            self.payment = payment
            self.payerIndex = payerIndex
            self.day = day
            self.monthsAgo = monthsAgo
            self.splitAmong = splitAmong
            self.recurrenceRule = recurrenceRule
        }
    }

    enum Mode {
        case currentUserOnly
        case household
    }

    @MainActor
    @discardableResult
    static func seed(
        into context: ModelContext,
        members: [BudgetMember],
        ownerUserId: String = "local",
        mode: Mode = .household,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        guard !members.isEmpty else { return 0 }

        func member(_ index: Int) -> BudgetMember {
            members[index % members.count]
        }

        func date(day: Int, monthsAgo: Int = 0) -> Date {
            let base = calendar.date(byAdding: .month, value: -monthsAgo, to: referenceDate) ?? referenceDate
            var components = calendar.dateComponents([.year, .month], from: base)
            components.day = max(1, min(day, 28))
            return calendar.date(from: components) ?? base
        }

        func splitMemberIds(_ indices: [Int]) -> [UUID] {
            indices.compactMap { members[safe: $0]?.id }
        }

        let allIndices = Array(0..<members.count)
        let fourWay = members.count >= 4 ? [0, 1, 2, 3] : allIndices
        let pair01 = Array(allIndices.prefix(2))
        let monthly = Transaction.monthlyRecurrenceRule(until: nil)
        let sixMonthStop = Transaction.monthlyRecurrenceRule(
            until: calendar.date(byAdding: .month, value: 6, to: referenceDate)
        )

        let householdSpecs: [Spec] = [
            // Income — spread across household earners
            Spec(title: "Salary", amount: 3200, type: .income, category: .work, payment: nil, payerIndex: 0, day: 1, monthsAgo: 0, splitAmong: nil),
            Spec(title: "Salary", amount: 2750, type: .income, category: .work, payment: nil, payerIndex: 1, day: 1, monthsAgo: 0, splitAmong: nil),
            Spec(title: "Freelance", amount: 1400, type: .income, category: .work, payment: nil, payerIndex: 2, day: 3, monthsAgo: 0, splitAmong: nil),
            Spec(title: "Salary", amount: 2950, type: .income, category: .work, payment: nil, payerIndex: 3, day: 1, monthsAgo: 0, splitAmong: nil),

            // Shared household — split across everyone when 4+ members
            Spec(title: "Rent", amount: 2400, type: .expense, category: .rent, payment: .card, payerIndex: 0, day: 2, monthsAgo: 0, splitAmong: fourWay, recurrenceRule: monthly),
            Spec(title: "Electric", amount: 186, type: .expense, category: .bills, payment: .card, payerIndex: 1, day: 5, monthsAgo: 0, splitAmong: fourWay, recurrenceRule: monthly),
            Spec(title: "Internet", amount: 89, type: .expense, category: .bills, payment: .card, payerIndex: 0, day: 5, monthsAgo: 0, splitAmong: fourWay, recurrenceRule: monthly),
            Spec(title: "Groceries", amount: 168.40, type: .expense, category: .groceries, payment: .card, payerIndex: 2, day: 4, monthsAgo: 0, splitAmong: fourWay),
            Spec(title: "House Supplies", amount: 74.25, type: .expense, category: .shopping, payment: .card, payerIndex: 3, day: 7, monthsAgo: 0, splitAmong: fourWay),

            // Smaller group splits
            Spec(title: "Date Night Dinner", amount: 112.80, type: .expense, category: .restaurant, payment: .card, payerIndex: 0, day: 9, monthsAgo: 0, splitAmong: pair01),
            Spec(title: "Road Trip Gas", amount: 96.50, type: .expense, category: .gas, payment: .card, payerIndex: 2, day: 11, monthsAgo: 0, splitAmong: members.count >= 4 ? [1, 2, 3] : fourWay),
            Spec(title: "Movie Night", amount: 48, type: .expense, category: .entertainment, payment: .card, payerIndex: 3, day: 14, monthsAgo: 0, splitAmong: fourWay),

            // Individual expenses
            Spec(title: "Phone Plan", amount: 60, type: .expense, category: .bills, payment: .card, payerIndex: 1, day: 5, monthsAgo: 0, splitAmong: nil, recurrenceRule: monthly),
            Spec(title: "Netflix", amount: 15.99, type: .expense, category: .subscription, payment: .card, payerIndex: 0, day: 6, monthsAgo: 0, splitAmong: nil, recurrenceRule: monthly),
            Spec(title: "Gym", amount: 45, type: .expense, category: .health, payment: .card, payerIndex: 2, day: 8, monthsAgo: 0, splitAmong: nil, recurrenceRule: sixMonthStop),
            Spec(title: "Coffee", amount: 6.75, type: .expense, category: .food, payment: .cash, payerIndex: 3, day: 10, monthsAgo: 0, splitAmong: nil),
            Spec(title: "Pharmacy", amount: 23.10, type: .expense, category: .health, payment: .card, payerIndex: 0, day: 12, monthsAgo: 0, splitAmong: nil),
            Spec(title: "Transit Pass", amount: 40, type: .expense, category: .transportation, payment: .card, payerIndex: 1, day: 15, monthsAgo: 0, splitAmong: nil),
            Spec(title: "New Sneakers", amount: 120, type: .expense, category: .shopping, payment: .paypal, payerIndex: 2, day: 18, monthsAgo: 0, splitAmong: nil),
            Spec(title: "E-transfer from friend", amount: 50, type: .income, category: .eTransfer, payment: nil, payerIndex: 3, day: 22, monthsAgo: 0, splitAmong: nil),

            // More shared groceries to build who-owes-whom
            Spec(title: "Groceries", amount: 142.50, type: .expense, category: .groceries, payment: .card, payerIndex: 1, day: 16, monthsAgo: 0, splitAmong: fourWay),
            Spec(title: "Takeout", amount: 58.20, type: .expense, category: .restaurant, payment: .card, payerIndex: 3, day: 20, monthsAgo: 0, splitAmong: fourWay),

            // Previous month
            Spec(title: "Rent", amount: 2400, type: .expense, category: .rent, payment: .card, payerIndex: 0, day: 2, monthsAgo: 1, splitAmong: fourWay),
            Spec(title: "Groceries", amount: 131.80, type: .expense, category: .groceries, payment: .card, payerIndex: 2, day: 11, monthsAgo: 1, splitAmong: fourWay),
            Spec(title: "Weekend BBQ", amount: 95, type: .expense, category: .food, payment: .card, payerIndex: 1, day: 18, monthsAgo: 1, splitAmong: fourWay)
        ]

        let currentUserSpecs: [Spec] = [
            Spec(title: "Salary", amount: 4200, type: .income, category: .work, payment: nil, payerIndex: 0, day: 1, monthsAgo: 0, splitAmong: nil),
            Spec(title: "Freelance Project", amount: 650, type: .income, category: .work, payment: nil, payerIndex: 0, day: 6, monthsAgo: 0, splitAmong: nil),
            Spec(title: "Rent", amount: 1800, type: .expense, category: .rent, payment: .card, payerIndex: 0, day: 2, monthsAgo: 0, splitAmong: nil, recurrenceRule: monthly),
            Spec(title: "Groceries", amount: 148.35, type: .expense, category: .groceries, payment: .card, payerIndex: 0, day: 4, monthsAgo: 0, splitAmong: nil),
            Spec(title: "Internet", amount: 89, type: .expense, category: .bills, payment: .card, payerIndex: 0, day: 5, monthsAgo: 0, splitAmong: nil, recurrenceRule: monthly),
            Spec(title: "Phone Plan", amount: 60, type: .expense, category: .bills, payment: .card, payerIndex: 0, day: 7, monthsAgo: 0, splitAmong: nil, recurrenceRule: monthly),
            Spec(title: "Coffee", amount: 6.75, type: .expense, category: .food, payment: .cash, payerIndex: 0, day: 10, monthsAgo: 0, splitAmong: nil),
            Spec(title: "Pharmacy", amount: 23.10, type: .expense, category: .health, payment: .card, payerIndex: 0, day: 12, monthsAgo: 0, splitAmong: nil),
            Spec(title: "Transit Pass", amount: 120, type: .expense, category: .transportation, payment: .card, payerIndex: 0, day: 15, monthsAgo: 0, splitAmong: nil, recurrenceRule: sixMonthStop),
            Spec(title: "Dinner", amount: 42.80, type: .expense, category: .restaurant, payment: .card, payerIndex: 0, day: 18, monthsAgo: 0, splitAmong: nil),
            Spec(title: "Groceries", amount: 131.80, type: .expense, category: .groceries, payment: .card, payerIndex: 0, day: 11, monthsAgo: 1, splitAmong: nil),
            Spec(title: "Takeout", amount: 38.50, type: .expense, category: .restaurant, payment: .card, payerIndex: 0, day: 20, monthsAgo: 1, splitAmong: nil)
        ]

        let specs = mode == .currentUserOnly ? currentUserSpecs : householdSpecs

        for spec in specs {
            let payer = member(spec.payerIndex)
            let transaction = Transaction(
                title: spec.title,
                amount: spec.amount,
                type: spec.type,
                category: spec.category,
                paymentMethod: spec.payment,
                createdByMemberId: payer.id,
                date: date(day: spec.day, monthsAgo: spec.monthsAgo),
                recurrenceRule: spec.recurrenceRule,
                ownerUserId: ownerUserId
            )
            context.insert(transaction)

            if let splitIndices = spec.splitAmong {
                let participantIds = splitMemberIds(splitIndices)
                guard participantIds.count > 1 else { continue }
                for entry in equalSplit(total: spec.amount, among: participantIds, payerId: payer.id) {
                    let split = TransactionSplit(
                        memberId: entry.memberId,
                        amount: entry.amount,
                        transaction: transaction
                    )
                    context.insert(split)
                }
            }
        }

        return specs.count
    }

    /// Splits a total into equal cent-accurate shares, putting any remainder
    /// cents on the payer.
    static func equalSplit(
        total: Double,
        among memberIds: [UUID],
        payerId: UUID
    ) -> [(memberId: UUID, amount: Double)] {
        guard !memberIds.isEmpty else { return [] }

        let ordered = memberIds.sorted { lhs, rhs in
            if lhs == payerId { return true }
            if rhs == payerId { return false }
            return lhs.uuidString < rhs.uuidString
        }

        let totalCents = Int((total * 100).rounded())
        let base = totalCents / ordered.count
        var remainder = totalCents % ordered.count

        return ordered.map { id in
            var cents = base
            if remainder > 0 {
                cents += 1
                remainder -= 1
            }
            return (id, Double(cents) / 100)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

import Foundation

enum RecurringTransactionResolver {
    static func transactions(
        in interval: DateInterval,
        from transactions: [Transaction],
        calendar: Calendar = .current,
        alreadyDeduplicated: Bool = false
    ) -> [Transaction] {
        let source = alreadyDeduplicated ? transactions : uniqueTransactions(from: transactions)
        return source.flatMap { transaction in
            occurrences(of: transaction, in: interval, calendar: calendar)
        }
        .sorted(by: newestFirst)
    }

    private static func uniqueTransactions(from transactions: [Transaction]) -> [Transaction] {
        var transactionsById: [UUID: Transaction] = [:]

        for transaction in transactions {
            guard let existing = transactionsById[transaction.id] else {
                transactionsById[transaction.id] = transaction
                continue
            }

            if newestFirst(transaction, existing) {
                transactionsById[transaction.id] = transaction
            }
        }

        return transactionsById.values.sorted(by: newestFirst)
    }

    private static func newestFirst(_ lhs: Transaction, _ rhs: Transaction) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func occurrences(of transaction: Transaction, in interval: DateInterval, calendar: Calendar) -> [Transaction] {
        if interval.contains(transaction.date) {
            return [transaction]
        }

        guard transaction.isMonthlyRecurring,
              transaction.date < interval.end,
              let occurrenceDate = monthlyOccurrenceDate(for: transaction.date, in: interval, calendar: calendar) else {
            return []
        }

        if occurrenceDate < transaction.date {
            return []
        }

        if let endDate = transaction.recurrenceEndDate,
           occurrenceDate > calendar.startOfDay(for: endDate) {
            return []
        }

        return [copy(transaction, occurrenceDate: occurrenceDate)]
    }

    private static func monthlyOccurrenceDate(for sourceDate: Date, in interval: DateInterval, calendar: Calendar) -> Date? {
        let sourceComponents = calendar.dateComponents([.day, .hour, .minute, .second], from: sourceDate)
        let intervalComponents = calendar.dateComponents([.year, .month], from: interval.start)
        var targetComponents = DateComponents()
        targetComponents.year = intervalComponents.year
        targetComponents.month = intervalComponents.month
        targetComponents.day = min(sourceComponents.day ?? 1, daysInMonth(for: interval.start, calendar: calendar))
        targetComponents.hour = sourceComponents.hour
        targetComponents.minute = sourceComponents.minute
        targetComponents.second = sourceComponents.second
        return calendar.date(from: targetComponents)
    }

    private static func daysInMonth(for date: Date, calendar: Calendar) -> Int {
        calendar.range(of: .day, in: .month, for: date)?.count ?? 28
    }

    private static func copy(_ transaction: Transaction, occurrenceDate: Date) -> Transaction {
        let copy = Transaction(
            id: transaction.id,
            title: transaction.title,
            amount: transaction.amount,
            type: transaction.type,
            category: transaction.category,
            paymentMethod: transaction.paymentMethod,
            createdByMemberId: transaction.createdByMemberId,
            date: occurrenceDate,
            createdAt: transaction.createdAt,
            recurrenceRule: transaction.recurrenceRule,
            ownerUserId: transaction.ownerUserId
        )
        copy.recurringSourceId = transaction.id

        for split in transaction.splits {
            let splitCopy = TransactionSplit(
                id: split.id,
                memberId: split.memberId,
                amount: split.amount,
                transaction: copy
            )
            copy.splits.append(splitCopy)
        }

        return copy
    }
}

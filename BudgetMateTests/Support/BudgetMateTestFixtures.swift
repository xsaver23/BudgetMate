import Foundation
@testable import BudgetMate

enum BudgetMateTestFixtures {
    static let aliceUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let bobUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let carolUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    static let personalBudgetID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
    static let sharedBudgetID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!

    static let aliceMemberID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
    static let bobMemberID = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
    static let carolMemberID = UUID(uuidString: "00000000-0000-0000-0000-000000000023")!
    static let invitedMemberID = UUID(uuidString: "00000000-0000-0000-0000-000000000024")!

    static let incomeTransactionID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static let expenseTransactionID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    static let equalSplitTransactionID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
    static let customSplitTransactionID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
    static let recurringTransactionID = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!

    static let firstSplitID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    static let secondSplitID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    static let thirdSplitID = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
    static let settlementID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!

    static let referenceDate = makeDate(year: 2025, month: 1, day: 15, hour: 12)
    static let januaryThirtyFirst = makeDate(year: 2025, month: 1, day: 31, hour: 9)
    static let februaryFirst = makeDate(year: 2025, month: 2, day: 1, hour: 0)
    static let marchFirst = makeDate(year: 2025, month: 3, day: 1, hour: 0)

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static func makeDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return utcCalendar.date(from: components)!
    }

    static var alice: BudgetMember {
        BudgetMember(
            id: aliceMemberID,
            displayName: "Alice Adams",
            email: "alice@example.com",
            initials: "AA",
            color: "#3B82F6",
            authUserId: aliceUserID,
            role: .owner,
            inviteStatus: .active,
            joinedDate: referenceDate,
            createdDate: referenceDate
        )
    }

    static var bob: BudgetMember {
        BudgetMember(
            id: bobMemberID,
            displayName: "Bob Brown",
            email: "bob@example.com",
            initials: "BB",
            color: "#F97316",
            authUserId: bobUserID,
            role: .member,
            inviteStatus: .active,
            joinedDate: referenceDate.addingTimeInterval(60),
            createdDate: referenceDate.addingTimeInterval(60)
        )
    }

    static var carol: BudgetMember {
        BudgetMember(
            id: carolMemberID,
            displayName: "Carol Clark",
            email: "carol@example.com",
            initials: "CC",
            color: "#10B981",
            authUserId: carolUserID,
            role: .member,
            inviteStatus: .active,
            joinedDate: referenceDate.addingTimeInterval(120),
            createdDate: referenceDate.addingTimeInterval(120)
        )
    }

    static var invitedMember: BudgetMember {
        BudgetMember(
            id: invitedMemberID,
            displayName: "Invited Member",
            email: "invite@example.com",
            initials: "IM",
            color: "#8B5CF6",
            role: .member,
            inviteStatus: .invited,
            joinedDate: nil,
            createdDate: referenceDate.addingTimeInterval(180)
        )
    }

    static var personalBudget: Budget {
        Budget(
            id: personalBudgetID,
            name: "Alice's Budget",
            createdByUserId: aliceUserID,
            members: [alice],
            createdDate: referenceDate
        )
    }

    static var sharedBudget: Budget {
        Budget(
            id: sharedBudgetID,
            name: "Adams Household",
            createdByUserId: aliceUserID,
            members: [alice, bob, invitedMember],
            createdDate: referenceDate
        )
    }

    static func income(
        id: UUID = incomeTransactionID,
        amount: Double = 2_500,
        memberId: UUID = aliceMemberID,
        date: Date = referenceDate
    ) -> Transaction {
        Transaction(
            id: id,
            title: "Paycheck",
            amount: amount,
            type: .income,
            category: .salary,
            paymentMethod: .cash,
            createdByMemberId: memberId,
            date: date,
            createdAt: referenceDate,
            ownerUserId: aliceUserID.uuidString
        )
    }

    static func expense(
        id: UUID = expenseTransactionID,
        title: String = "Groceries",
        amount: Double = 120,
        category: TransactionCategory = .groceries,
        payerId: UUID = aliceMemberID,
        date: Date = referenceDate,
        recurrenceRule: String? = nil
    ) -> Transaction {
        Transaction(
            id: id,
            title: title,
            amount: amount,
            type: .expense,
            category: category,
            paymentMethod: .card,
            createdByMemberId: payerId,
            date: date,
            createdAt: referenceDate,
            recurrenceRule: recurrenceRule,
            ownerUserId: sharedBudgetID.uuidString
        )
    }

    static func equalSplitExpense(
        id: UUID = equalSplitTransactionID,
        amount: Double = 100,
        payerId: UUID = aliceMemberID,
        date: Date = referenceDate
    ) -> Transaction {
        let transaction = expense(
            id: id,
            title: "Dinner",
            amount: amount,
            category: .restaurant,
            payerId: payerId,
            date: date
        )
        let share = amount / 2
        let first = TransactionSplit(id: firstSplitID, memberId: aliceMemberID, amount: share, transaction: transaction)
        let second = TransactionSplit(id: secondSplitID, memberId: bobMemberID, amount: share, transaction: transaction)
        transaction.splits = [first, second]
        return transaction
    }

    static func customSplitExpense(
        id: UUID = customSplitTransactionID,
        amount: Double = 100,
        payerId: UUID = aliceMemberID,
        date: Date = referenceDate
    ) -> Transaction {
        let transaction = expense(
            id: id,
            title: "Utilities",
            amount: amount,
            category: .bills,
            payerId: payerId,
            date: date
        )
        let first = TransactionSplit(id: firstSplitID, memberId: aliceMemberID, amount: amount * 0.4, transaction: transaction)
        let second = TransactionSplit(id: secondSplitID, memberId: bobMemberID, amount: amount * 0.6, transaction: transaction)
        transaction.splits = [first, second]
        return transaction
    }

    static func recurringExpense(
        id: UUID = recurringTransactionID,
        date: Date = januaryThirtyFirst,
        endDate: Date? = nil
    ) -> Transaction {
        expense(
            id: id,
            title: "Rent",
            amount: 1_200,
            category: .rent,
            date: date,
            recurrenceRule: Transaction.monthlyRecurrenceRule(until: endDate)
        )
    }

    static func settlement(
        id: UUID = settlementID,
        fromMemberId: UUID = bobMemberID,
        toMemberId: UUID = aliceMemberID,
        amount: Double = 20,
        date: Date = referenceDate.addingTimeInterval(3_600)
    ) -> Settlement {
        Settlement(
            id: id,
            fromMemberId: fromMemberId,
            toMemberId: toMemberId,
            amount: amount,
            date: date,
            ownerUserId: sharedBudgetID.uuidString
        )
    }

    static var settings: BudgetSettings {
        BudgetSettings(
            monthlyBudget: 0,
            currencyCode: "USD",
            appearance: .system,
            categoryBudgets: [
                TransactionCategory.groceries.rawValue: 400,
                TransactionCategory.restaurant.rawValue: 250
            ],
            categoryEmojis: [TransactionCategory.groceries.rawValue: "🥕"]
        )
    }

    static var pendingDeletion: PendingCloudDeletion {
        PendingCloudDeletion(
            entity: .transaction,
            recordId: equalSplitTransactionID,
            userScopeId: aliceUserID.uuidString,
            budgetScopeId: sharedBudgetID.uuidString
        )
    }

    static var cloudSettingsRow: CloudBudgetSettingsRow {
        CloudBudgetSettingsRow(settings: settings, userId: aliceUserID, budgetId: sharedBudgetID)
    }

    static var cloudMemberRow: CloudBudgetMemberRow {
        CloudBudgetMemberRow(member: bob, userId: bobUserID, budgetId: sharedBudgetID)
    }

    static var cloudTransactionRow: CloudTransactionRow {
        CloudTransactionRow(
            transaction: equalSplitExpense(),
            userId: aliceUserID,
            budgetId: sharedBudgetID
        )
    }

    static var cloudSettlementRow: CloudSettlementRow {
        CloudSettlementRow(
            settlement: settlement(),
            userId: aliceUserID,
            budgetId: sharedBudgetID
        )
    }

    static func isolatedDefaults() -> UserDefaults {
        let suiteName = "BudgetMateTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }
}

import Foundation
import SwiftData
@testable import BudgetMate

/// Deterministically materializes the exact pre-versioning app schema in a
/// file-backed store. The fixture deliberately omits a migration plan.
@MainActor
enum LegacyUnversionedStoreFixture {
    static let expenseID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let incomeID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    static let firstSplitID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    static let secondSplitID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    static let orphanSplitID = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
    static let settlementID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    static let firstMemberID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
    static let secondMemberID = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!

    static let expenseDate = Date(timeIntervalSince1970: 1_704_067_200)
    static let incomeDate = Date(timeIntervalSince1970: 1_704_153_600)
    static let settlementDate = Date(timeIntervalSince1970: 1_704_240_000)
    static let ownerUserID = "50000000-0000-0000-0000-000000000001"

    static var schema: Schema {
        Schema([
            Transaction.self,
            TransactionSplit.self,
            Settlement.self
        ])
    }

    static func create(at storeURL: URL) throws {
        let legacySchema = schema
        let configuration = ModelConfiguration(
            "BudgetMatePR01AFixture",
            schema: legacySchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: legacySchema,
            configurations: [configuration]
        )
        let context = container.mainContext

        let expense = Transaction(
            id: expenseID,
            title: "Legacy groceries",
            amount: 123.45,
            type: .expense,
            category: .groceries,
            paymentMethod: .card,
            createdByMemberId: firstMemberID,
            date: expenseDate,
            createdAt: expenseDate,
            recurrenceRule: "monthly|until=2024-12-31",
            ownerUserId: ownerUserID
        )
        expense.needsSync = true

        let firstSplit = TransactionSplit(
            id: firstSplitID,
            memberId: firstMemberID,
            amount: 61.72,
            transaction: expense
        )
        let secondSplit = TransactionSplit(
            id: secondSplitID,
            memberId: secondMemberID,
            amount: 61.73,
            transaction: expense
        )
        expense.splits = [firstSplit, secondSplit]
        let orphanSplit = TransactionSplit(
            id: orphanSplitID,
            memberId: firstMemberID,
            amount: 9.99,
            transaction: nil
        )

        let income = Transaction(
            id: incomeID,
            title: "Legacy pay",
            amount: 2_500,
            type: .income,
            category: .work,
            paymentMethod: nil,
            createdByMemberId: secondMemberID,
            date: incomeDate,
            createdAt: incomeDate,
            recurrenceRule: nil,
            ownerUserId: ownerUserID
        )

        let settlement = Settlement(
            id: settlementID,
            fromMemberId: secondMemberID,
            toMemberId: firstMemberID,
            amount: 25.50,
            date: settlementDate,
            ownerUserId: ownerUserID
        )
        settlement.needsSync = true

        context.insert(expense)
        context.insert(income)
        context.insert(orphanSplit)
        context.insert(settlement)
        try context.save()
    }
}

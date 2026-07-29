import Foundation
import SwiftData
@testable import BudgetMate

/// Deterministically materializes the exact pre-versioning app schema in a
/// file-backed store. The fixture deliberately omits a migration plan.
struct LegacySchemaRelationshipContract: Equatable {
    let destination: String
    let inverseName: String
    let deleteRule: String
    let isToOne: Bool
}

struct LegacySchemaPhysicalContract: Equatable {
    let entities: [String: [String: Bool]]
    let relationships: [String: LegacySchemaRelationshipContract]
}

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

    /// Independent contract transcribed from the shipping unversioned model
    /// surface. It is intentionally not derived from BudgetMateSchemaV1.
    static let shippingSchemaContract = LegacySchemaPhysicalContract(
        entities: [
            "Settlement": [
                "amount": false,
                "date": false,
                "fromMemberId": false,
                "id": false,
                "needsSync": false,
                "ownerUserId": false,
                "toMemberId": false
            ],
            "Transaction": [
                "amount": false,
                "category": false,
                "createdAt": false,
                "createdByMemberId": false,
                "date": false,
                "id": false,
                "needsSync": false,
                "ownerUserId": false,
                "paymentMethod": true,
                "recurrenceRule": true,
                "splits": false,
                "title": false,
                "type": false
            ],
            "TransactionSplit": [
                "amount": false,
                "id": false,
                "memberId": false,
                "transaction": true
            ]
        ],
        relationships: [
            "Transaction.splits": LegacySchemaRelationshipContract(
                destination: "TransactionSplit",
                inverseName: "transaction",
                deleteRule: "cascade",
                isToOne: false
            ),
            "TransactionSplit.transaction": LegacySchemaRelationshipContract(
                destination: "Transaction",
                inverseName: "splits",
                deleteRule: "nullify",
                isToOne: true
            )
        ]
    )

    static var schema: Schema {
        Schema([
            BudgetMateSchemaV1.Transaction.self,
            BudgetMateSchemaV1.TransactionSplit.self,
            BudgetMateSchemaV1.Settlement.self
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

        let expense = BudgetMateSchemaV1.Transaction(
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

        let firstSplit = BudgetMateSchemaV1.TransactionSplit(
            id: firstSplitID,
            memberId: firstMemberID,
            amount: 61.72,
            transaction: expense
        )
        let secondSplit = BudgetMateSchemaV1.TransactionSplit(
            id: secondSplitID,
            memberId: secondMemberID,
            amount: 61.73,
            transaction: expense
        )
        expense.splits = [firstSplit, secondSplit]
        let orphanSplit = BudgetMateSchemaV1.TransactionSplit(
            id: orphanSplitID,
            memberId: firstMemberID,
            amount: 9.99,
            transaction: nil
        )

        let income = BudgetMateSchemaV1.Transaction(
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

        let settlement = BudgetMateSchemaV1.Settlement(
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

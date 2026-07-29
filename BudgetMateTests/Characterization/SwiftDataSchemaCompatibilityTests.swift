import Foundation
import SwiftData
import XCTest
@testable import BudgetMate

@MainActor
final class SwiftDataSchemaCompatibilityTests: XCTestCase {
    func testVersionedV1ExactlyMatchesTheShippingUnversionedSchema() throws {
        let versionedSchema = Schema(versionedSchema: BudgetMateSchemaV1.self)

        XCTAssertEqual(
            physicalContract(in: versionedSchema),
            LegacyUnversionedStoreFixture.shippingSchemaContract
        )
        XCTAssertEqual(versionedSchema.version, Schema.Version(1, 0, 0))
        XCTAssertEqual(BudgetMateSchemaMigrationPlan.schemas.count, 3)
        XCTAssertEqual(
            ObjectIdentifier(BudgetMateSchemaMigrationPlan.schemas[0]),
            ObjectIdentifier(BudgetMateSchemaV1.self)
        )
        XCTAssertEqual(BudgetMateSchemaMigrationPlan.stages.count, 2)

        let transaction = try XCTUnwrap(versionedSchema.entitiesByName["Transaction"])
        let splits = try XCTUnwrap(transaction.relationshipsByName["splits"])
        XCTAssertEqual(splits.destination, "TransactionSplit")
        XCTAssertEqual(splits.inverseName, "transaction")
        XCTAssertEqual(splits.deleteRule, .cascade)
        XCTAssertFalse(splits.isToOneRelationship)

        let split = try XCTUnwrap(versionedSchema.entitiesByName["TransactionSplit"])
        let parent = try XCTUnwrap(split.relationshipsByName["transaction"])
        XCTAssertEqual(parent.destination, "Transaction")
        XCTAssertEqual(parent.inverseName, "splits")
        XCTAssertEqual(parent.deleteRule, .nullify)
        XCTAssertTrue(parent.isToOneRelationship)
    }

    func testVersionedV2PreservesEntityAndRelationshipIdentityWithOptionalMoneyFields() throws {
        let v1 = Schema(versionedSchema: BudgetMateSchemaV1.self)
        let v2 = Schema(versionedSchema: BudgetMateSchemaV2.self)

        XCTAssertEqual(v2.version, Schema.Version(2, 0, 0))
        XCTAssertEqual(
            Set(v2.entities.map(\.name)),
            Set(v1.entities.map(\.name))
        )
        XCTAssertEqual(
            Set(BudgetMateSchemaMigrationPlan.schemas.map { $0.versionIdentifier }),
            [
                Schema.Version(1, 0, 0),
                Schema.Version(2, 0, 0),
                Schema.Version(3, 0, 0)
            ]
        )

        for entityName in ["Transaction", "TransactionSplit", "Settlement"] {
            let oldEntity = try XCTUnwrap(v1.entitiesByName[entityName])
            let newEntity = try XCTUnwrap(v2.entitiesByName[entityName])
            let oldProperties = Set(oldEntity.properties.map(\.name))
            XCTAssertTrue(
                oldProperties.isSubset(of: Set(newEntity.properties.map(\.name))),
                "V2 removed a V1 property from \(entityName)"
            )
        }

        let transaction = try XCTUnwrap(v2.entitiesByName["Transaction"])
        XCTAssertEqual(transaction.attributesByName["amountMinorUnits"]?.isOptional, true)
        XCTAssertEqual(transaction.attributesByName["currencyCode"]?.isOptional, true)
        let splits = try XCTUnwrap(transaction.relationshipsByName["splits"])
        XCTAssertEqual(splits.destination, "TransactionSplit")
        XCTAssertEqual(splits.inverseName, "transaction")
        XCTAssertEqual(splits.deleteRule, .cascade)

        let split = try XCTUnwrap(v2.entitiesByName["TransactionSplit"])
        let parent = try XCTUnwrap(split.relationshipsByName["transaction"])
        XCTAssertEqual(parent.destination, "Transaction")
        XCTAssertEqual(parent.inverseName, "splits")
        XCTAssertEqual(parent.deleteRule, .nullify)
        XCTAssertEqual(split.attributesByName["amountMinorUnits"]?.isOptional, true)
        XCTAssertEqual(split.attributesByName["currencyCode"]?.isOptional, true)

        let settlement = try XCTUnwrap(v2.entitiesByName["Settlement"])
        XCTAssertEqual(settlement.attributesByName["amountMinorUnits"]?.isOptional, true)
        XCTAssertEqual(settlement.attributesByName["currencyCode"]?.isOptional, true)
    }

    func testVersionedV3AddsOptionalCreatorAndConflictMetadata() throws {
        let v2 = Schema(versionedSchema: BudgetMateSchemaV2.self)
        let v3 = Schema(versionedSchema: BudgetMateSchemaV3.self)

        XCTAssertEqual(v3.version, Schema.Version(3, 0, 0))
        XCTAssertEqual(
            Set(BudgetMateSchemaMigrationPlan.schemas.map { $0.versionIdentifier }),
            [
                Schema.Version(1, 0, 0),
                Schema.Version(2, 0, 0),
                Schema.Version(3, 0, 0)
            ]
        )

        for entityName in ["Transaction", "TransactionSplit", "Settlement"] {
            let oldEntity = try XCTUnwrap(v2.entitiesByName[entityName])
            let newEntity = try XCTUnwrap(v3.entitiesByName[entityName])
            XCTAssertTrue(
                Set(oldEntity.properties.map(\.name)).isSubset(of: Set(newEntity.properties.map(\.name))),
                "V3 removed a V2 property from \(entityName)"
            )
        }

        let transaction = try XCTUnwrap(v3.entitiesByName["Transaction"])
        XCTAssertEqual(transaction.attributesByName["createdByUserId"]?.isOptional, true)
        XCTAssertEqual(transaction.attributesByName["rowVersion"]?.isOptional, true)
        XCTAssertEqual(transaction.attributesByName["lastMutationId"]?.isOptional, true)

        let settlement = try XCTUnwrap(v3.entitiesByName["Settlement"])
        XCTAssertEqual(settlement.attributesByName["createdByUserId"]?.isOptional, true)
        XCTAssertEqual(settlement.attributesByName["rowVersion"]?.isOptional, true)
        XCTAssertEqual(settlement.attributesByName["lastMutationId"]?.isOptional, true)
    }

    func testVersionedV2StoreMigratesToV3WithoutInventingIdentityOrVersion() throws {
        let location = try makeStoreLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }

        let v2Schema = Schema(versionedSchema: BudgetMateSchemaV2.self)
        let v2Configuration = ModelConfiguration(
            "BudgetMateV2GateCFixture",
            schema: v2Schema,
            url: location.storeURL,
            cloudKitDatabase: .none
        )
        let v2Container = try ModelContainer(
            for: v2Schema,
            configurations: [v2Configuration]
        )
        let transaction = BudgetMateSchemaV2.Transaction(
            title: "V2 transaction",
            amount: 12.34,
            amountMinorUnits: 1234,
            currencyCode: "CAD",
            type: .expense,
            category: .food,
            createdByMemberId: LegacyUnversionedStoreFixture.firstMemberID,
            ownerUserId: LegacyUnversionedStoreFixture.ownerUserID
        )
        let settlement = BudgetMateSchemaV2.Settlement(
            fromMemberId: LegacyUnversionedStoreFixture.secondMemberID,
            toMemberId: LegacyUnversionedStoreFixture.firstMemberID,
            amount: 2.50,
            amountMinorUnits: 250,
            currencyCode: "CAD",
            ownerUserId: LegacyUnversionedStoreFixture.ownerUserID
        )
        v2Container.mainContext.insert(transaction)
        v2Container.mainContext.insert(settlement)
        try v2Container.mainContext.save()

        try withVersionedStore(at: location.storeURL) { context in
            let migratedTransaction = try XCTUnwrap(
                try context.fetch(FetchDescriptor<Transaction>()).first
            )
            let migratedSettlement = try XCTUnwrap(
                try context.fetch(FetchDescriptor<Settlement>()).first
            )
            XCTAssertEqual(migratedTransaction.title, "V2 transaction")
            XCTAssertEqual(migratedTransaction.amountMinorUnits, 1234)
            XCTAssertEqual(migratedTransaction.currencyCode, "CAD")
            XCTAssertNil(migratedTransaction.createdByUserId)
            XCTAssertNil(migratedTransaction.rowVersion)
            XCTAssertNil(migratedTransaction.lastMutationId)
            XCTAssertNil(migratedSettlement.createdByUserId)
            XCTAssertNil(migratedSettlement.rowVersion)
            XCTAssertNil(migratedSettlement.lastMutationId)
        }
    }

    func testFreshVersionedFileBackedStoreSavesAndReopens() throws {
        let location = try makeStoreLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }

        try withVersionedStore(at: location.storeURL) { context in
            let transaction = Transaction(
                id: LegacyUnversionedStoreFixture.expenseID,
                title: "Fresh transaction",
                amount: 42.25,
                type: .expense,
                category: .food,
                createdByMemberId: LegacyUnversionedStoreFixture.firstMemberID,
                date: LegacyUnversionedStoreFixture.expenseDate,
                createdAt: LegacyUnversionedStoreFixture.expenseDate,
                ownerUserId: LegacyUnversionedStoreFixture.ownerUserID
            )
            context.insert(transaction)
            try context.save()
        }

        let reopened = try versionedSnapshot(at: location.storeURL)
        XCTAssertEqual(reopened.transactions.count, 1)
        XCTAssertEqual(reopened.transactions[0].id, LegacyUnversionedStoreFixture.expenseID)
        XCTAssertEqual(reopened.transactions[0].title, "Fresh transaction")
        XCTAssertEqual(reopened.transactions[0].amount, 42.25, accuracy: 0.001)
        XCTAssertTrue(reopened.splits.isEmpty)
        XCTAssertTrue(reopened.settlements.isEmpty)
    }

    func testVersionedV1OpensUpdatesAndReopensTheLegacyFileBackedStore() throws {
        let location = try makeStoreLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }

        try LegacyUnversionedStoreFixture.create(at: location.storeURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.storeURL.path))

        let before = try legacySnapshot(at: location.storeURL)
        assertInitialLegacySnapshot(before)

        let directlyOpened = try versionedSnapshot(at: location.storeURL)
        assertInitialLegacySnapshot(directlyOpened)

        try withVersionedStore(at: location.storeURL) { context in
            let transactions = try context.fetch(FetchDescriptor<Transaction>())
            let splits = try context.fetch(FetchDescriptor<TransactionSplit>())
            let expense = try XCTUnwrap(
                transactions.first { $0.id == LegacyUnversionedStoreFixture.expenseID }
            )
            let income = try XCTUnwrap(
                transactions.first { $0.id == LegacyUnversionedStoreFixture.incomeID }
            )
            let settlements = try context.fetch(FetchDescriptor<Settlement>())
            let settlement = try XCTUnwrap(
                settlements.first { $0.id == LegacyUnversionedStoreFixture.settlementID }
            )
            let firstSplit = try XCTUnwrap(
                splits.first { $0.id == LegacyUnversionedStoreFixture.firstSplitID }
            )

            expense.title = "Updated groceries"
            expense.amount = 125.00
            expense.paymentMethod = .cash
            income.recurrenceRule = "monthly"
            firstSplit.amount = 62.00
            settlement.needsSync = false
            try context.save()
        }

        let reopened = try versionedSnapshot(at: location.storeURL)
        XCTAssertEqual(reopened.transactions.count, 2)
        XCTAssertEqual(reopened.splits.count, 3)
        XCTAssertEqual(reopened.settlements.count, 1)

        let expense = try XCTUnwrap(
            reopened.transactions.first {
                $0.id == LegacyUnversionedStoreFixture.expenseID
            }
        )
        XCTAssertEqual(expense.title, "Updated groceries")
        XCTAssertEqual(expense.amount, 125.00, accuracy: 0.001)
        XCTAssertEqual(expense.paymentMethod, .cash)
        XCTAssertEqual(
            expense.splitIDs,
            [
                LegacyUnversionedStoreFixture.firstSplitID,
                LegacyUnversionedStoreFixture.secondSplitID
            ]
        )

        let income = try XCTUnwrap(
            reopened.transactions.first {
                $0.id == LegacyUnversionedStoreFixture.incomeID
            }
        )
        XCTAssertEqual(income.recurrenceRule, "monthly")
        XCTAssertNil(income.paymentMethod)
        XCTAssertTrue(income.splitIDs.isEmpty)

        let settlement = try XCTUnwrap(reopened.settlements.first)
        XCTAssertEqual(settlement.id, LegacyUnversionedStoreFixture.settlementID)
        XCTAssertFalse(settlement.needsSync)
        XCTAssertEqual(
            Set(reopened.splits.compactMap(\.transactionID)),
            [LegacyUnversionedStoreFixture.expenseID]
        )
        let firstSplit = try XCTUnwrap(
            reopened.splits.first {
                $0.id == LegacyUnversionedStoreFixture.firstSplitID
            }
        )
        XCTAssertEqual(firstSplit.amount, 62.00, accuracy: 0.001)
        let orphanSplit = try XCTUnwrap(
            reopened.splits.first {
                $0.id == LegacyUnversionedStoreFixture.orphanSplitID
            }
        )
        XCTAssertNil(orphanSplit.transactionID)
    }

    private func assertInitialLegacySnapshot(
        _ snapshot: StoreSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(snapshot.transactions.count, 2, file: file, line: line)
        XCTAssertEqual(snapshot.splits.count, 3, file: file, line: line)
        XCTAssertEqual(snapshot.settlements.count, 1, file: file, line: line)

        guard let expense = snapshot.transactions.first(where: {
            $0.id == LegacyUnversionedStoreFixture.expenseID
        }) else {
            XCTFail("Missing legacy expense", file: file, line: line)
            return
        }
        XCTAssertEqual(expense.title, "Legacy groceries", file: file, line: line)
        XCTAssertEqual(expense.amount, 123.45, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(expense.type, .expense, file: file, line: line)
        XCTAssertEqual(expense.category, .groceries, file: file, line: line)
        XCTAssertEqual(expense.paymentMethod, .card, file: file, line: line)
        XCTAssertEqual(
            expense.createdByMemberID,
            LegacyUnversionedStoreFixture.firstMemberID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            expense.date,
            LegacyUnversionedStoreFixture.expenseDate,
            file: file,
            line: line
        )
        XCTAssertEqual(
            expense.createdAt,
            LegacyUnversionedStoreFixture.expenseDate,
            file: file,
            line: line
        )
        XCTAssertEqual(expense.recurrenceRule, "monthly|until=2024-12-31", file: file, line: line)
        XCTAssertEqual(
            expense.ownerUserID,
            LegacyUnversionedStoreFixture.ownerUserID,
            file: file,
            line: line
        )
        XCTAssertTrue(expense.needsSync, file: file, line: line)
        XCTAssertEqual(
            expense.splitIDs,
            [
                LegacyUnversionedStoreFixture.firstSplitID,
                LegacyUnversionedStoreFixture.secondSplitID
            ],
            file: file,
            line: line
        )

        guard let income = snapshot.transactions.first(where: {
            $0.id == LegacyUnversionedStoreFixture.incomeID
        }) else {
            XCTFail("Missing legacy income", file: file, line: line)
            return
        }
        XCTAssertEqual(income.title, "Legacy pay", file: file, line: line)
        XCTAssertEqual(income.amount, 2_500, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(income.type, .income, file: file, line: line)
        XCTAssertEqual(income.category, .work, file: file, line: line)
        XCTAssertNil(income.paymentMethod, file: file, line: line)
        XCTAssertNil(income.recurrenceRule, file: file, line: line)
        XCTAssertEqual(
            income.createdByMemberID,
            LegacyUnversionedStoreFixture.secondMemberID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            income.date,
            LegacyUnversionedStoreFixture.incomeDate,
            file: file,
            line: line
        )
        XCTAssertEqual(
            income.createdAt,
            LegacyUnversionedStoreFixture.incomeDate,
            file: file,
            line: line
        )
        XCTAssertEqual(
            income.ownerUserID,
            LegacyUnversionedStoreFixture.ownerUserID,
            file: file,
            line: line
        )
        XCTAssertFalse(income.needsSync, file: file, line: line)
        XCTAssertEqual(income.splitIDs, [], file: file, line: line)

        guard let firstSplit = snapshot.splits.first(where: {
            $0.id == LegacyUnversionedStoreFixture.firstSplitID
        }) else {
            XCTFail("Missing legacy split", file: file, line: line)
            return
        }
        XCTAssertEqual(
            firstSplit.memberID,
            LegacyUnversionedStoreFixture.firstMemberID,
            file: file,
            line: line
        )
        XCTAssertEqual(firstSplit.amount, 61.72, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(
            firstSplit.transactionID,
            LegacyUnversionedStoreFixture.expenseID,
            file: file,
            line: line
        )
        guard let secondSplit = snapshot.splits.first(where: {
            $0.id == LegacyUnversionedStoreFixture.secondSplitID
        }) else {
            XCTFail("Missing second legacy split", file: file, line: line)
            return
        }
        XCTAssertEqual(
            secondSplit.memberID,
            LegacyUnversionedStoreFixture.secondMemberID,
            file: file,
            line: line
        )
        XCTAssertEqual(secondSplit.amount, 61.73, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(
            secondSplit.transactionID,
            LegacyUnversionedStoreFixture.expenseID,
            file: file,
            line: line
        )
        guard let orphanSplit = snapshot.splits.first(where: {
            $0.id == LegacyUnversionedStoreFixture.orphanSplitID
        }) else {
            XCTFail("Missing legacy orphan split", file: file, line: line)
            return
        }
        XCTAssertEqual(
            orphanSplit.memberID,
            LegacyUnversionedStoreFixture.firstMemberID,
            file: file,
            line: line
        )
        XCTAssertEqual(orphanSplit.amount, 9.99, accuracy: 0.001, file: file, line: line)
        XCTAssertNil(orphanSplit.transactionID, file: file, line: line)

        guard let settlement = snapshot.settlements.first else {
            XCTFail("Missing legacy settlement", file: file, line: line)
            return
        }
        XCTAssertEqual(
            settlement.id,
            LegacyUnversionedStoreFixture.settlementID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            settlement.fromMemberID,
            LegacyUnversionedStoreFixture.secondMemberID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            settlement.toMemberID,
            LegacyUnversionedStoreFixture.firstMemberID,
            file: file,
            line: line
        )
        XCTAssertEqual(settlement.amount, 25.50, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(
            settlement.date,
            LegacyUnversionedStoreFixture.settlementDate,
            file: file,
            line: line
        )
        XCTAssertEqual(
            settlement.ownerUserID,
            LegacyUnversionedStoreFixture.ownerUserID,
            file: file,
            line: line
        )
        XCTAssertTrue(settlement.needsSync, file: file, line: line)
    }

    private func physicalContract(in schema: Schema) -> LegacySchemaPhysicalContract {
        var relationships: [String: LegacySchemaRelationshipContract] = [:]
        for entity in schema.entities {
            for property in entity.properties {
                guard let relationship = entity.relationshipsByName[property.name] else {
                    continue
                }
                relationships[entity.name + "." + relationship.name] = LegacySchemaRelationshipContract(
                    destination: relationship.destination,
                    inverseName: relationship.inverseName ?? "",
                    deleteRule: String(describing: relationship.deleteRule),
                    isToOne: relationship.isToOneRelationship
                )
            }
        }
        return LegacySchemaPhysicalContract(
            entities: entityContract(in: schema),
            relationships: relationships
        )
    }

    private func entityContract(in schema: Schema) -> [String: [String: Bool]] {
        Dictionary(uniqueKeysWithValues: schema.entities.map { entity in
            (
                entity.name,
                Dictionary(uniqueKeysWithValues: entity.properties.map {
                    ($0.name, $0.isOptional)
                })
            )
        })
    }

    private func makeStoreLocation() throws -> (directory: URL, storeURL: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BudgetMateSchemaCompatibility-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return (
            directory,
            directory.appendingPathComponent("BudgetMateLegacy.store")
        )
    }

    private func legacySnapshot(at storeURL: URL) throws -> StoreSnapshot {
        let schema = LegacyUnversionedStoreFixture.schema
        let configuration = ModelConfiguration(
            "BudgetMatePR01AFixture",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return try snapshotV1(from: container.mainContext)
    }

    private func versionedSnapshot(at storeURL: URL) throws -> StoreSnapshot {
        try withVersionedStore(at: storeURL) { context in
            try snapshotV2(from: context)
        }
    }

    private func withVersionedStore<Result>(
        at storeURL: URL,
        operation: (ModelContext) throws -> Result
    ) throws -> Result {
        let schema = BudgetMateSchema.current
        let configuration = ModelConfiguration(
            "BudgetMatePR01AFixture",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: BudgetMateSchemaMigrationPlan.self,
            configurations: [configuration]
        )
        return try operation(container.mainContext)
    }

    private func snapshotV1(from context: ModelContext) throws -> StoreSnapshot {
        let transactions = try context.fetch(
            FetchDescriptor<BudgetMateSchemaV1.Transaction>()
        )
            .map { TransactionSnapshot(v1: $0) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let splits = try context.fetch(
            FetchDescriptor<BudgetMateSchemaV1.TransactionSplit>()
        )
            .map { SplitSnapshot(v1: $0) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let settlements = try context.fetch(
            FetchDescriptor<BudgetMateSchemaV1.Settlement>()
        )
            .map { SettlementSnapshot(v1: $0) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        return StoreSnapshot(
            transactions: transactions,
            splits: splits,
            settlements: settlements
        )
    }

    private func snapshotV2(from context: ModelContext) throws -> StoreSnapshot {
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
            .map { TransactionSnapshot(v2: $0) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let splits = try context.fetch(FetchDescriptor<TransactionSplit>())
            .map { SplitSnapshot(v2: $0) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let settlements = try context.fetch(FetchDescriptor<Settlement>())
            .map { SettlementSnapshot(v2: $0) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        return StoreSnapshot(
            transactions: transactions,
            splits: splits,
            settlements: settlements
        )
    }
}

private struct StoreSnapshot {
    let transactions: [TransactionSnapshot]
    let splits: [SplitSnapshot]
    let settlements: [SettlementSnapshot]
}

private struct TransactionSnapshot {
    let id: UUID
    let title: String
    let amount: Double
    let type: TransactionType
    let category: TransactionCategory
    let paymentMethod: PaymentMethod?
    let createdByMemberID: UUID
    let date: Date
    let createdAt: Date
    let recurrenceRule: String?
    let ownerUserID: String
    let needsSync: Bool
    let splitIDs: [UUID]

    init(v1 transaction: BudgetMateSchemaV1.Transaction) {
        id = transaction.id
        title = transaction.title
        amount = transaction.amount
        type = transaction.type
        category = transaction.category
        paymentMethod = transaction.paymentMethod
        createdByMemberID = transaction.createdByMemberId
        date = transaction.date
        createdAt = transaction.createdAt
        recurrenceRule = transaction.recurrenceRule
        ownerUserID = transaction.ownerUserId
        needsSync = transaction.needsSync
        splitIDs = transaction.splits
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    init(v2 transaction: Transaction) {
        id = transaction.id
        title = transaction.title
        amount = transaction.amount
        type = transaction.type
        category = transaction.category
        paymentMethod = transaction.paymentMethod
        createdByMemberID = transaction.createdByMemberId
        date = transaction.date
        createdAt = transaction.createdAt
        recurrenceRule = transaction.recurrenceRule
        ownerUserID = transaction.ownerUserId
        needsSync = transaction.needsSync
        splitIDs = transaction.splits
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }
}

private struct SplitSnapshot {
    let id: UUID
    let memberID: UUID
    let amount: Double
    let transactionID: UUID?

    init(v1 split: BudgetMateSchemaV1.TransactionSplit) {
        id = split.id
        memberID = split.memberId
        amount = split.amount
        transactionID = split.transaction?.id
    }

    init(v2 split: TransactionSplit) {
        id = split.id
        memberID = split.memberId
        amount = split.amount
        transactionID = split.transaction?.id
    }
}

private struct SettlementSnapshot {
    let id: UUID
    let fromMemberID: UUID
    let toMemberID: UUID
    let amount: Double
    let date: Date
    let ownerUserID: String
    let needsSync: Bool

    init(v1 settlement: BudgetMateSchemaV1.Settlement) {
        id = settlement.id
        fromMemberID = settlement.fromMemberId
        toMemberID = settlement.toMemberId
        amount = settlement.amount
        date = settlement.date
        ownerUserID = settlement.ownerUserId
        needsSync = settlement.needsSync
    }

    init(v2 settlement: Settlement) {
        id = settlement.id
        fromMemberID = settlement.fromMemberId
        toMemberID = settlement.toMemberId
        amount = settlement.amount
        date = settlement.date
        ownerUserID = settlement.ownerUserId
        needsSync = settlement.needsSync
    }
}

import Foundation
import SwiftData

/// Immutable representation of the shipping SwiftData schema.
///
/// This type is deliberately self-contained. Do not add new properties to
/// these nested models; future schema versions own their own model types.
enum BudgetMateSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Transaction.self, TransactionSplit.self, Settlement.self]
    }

    @Model
    final class Transaction {
        var id: UUID
        var title: String
        var amount: Double
        var type: TransactionType
        var category: TransactionCategory
        var paymentMethod: PaymentMethod?
        var createdByMemberId: UUID
        var date: Date
        var createdAt: Date
        var recurrenceRule: String?
        var ownerUserId: String
        var needsSync: Bool = false
        @Transient var recurringSourceId: UUID?

        @Relationship(deleteRule: .cascade, inverse: \TransactionSplit.transaction)
        var splits: [TransactionSplit] = []

        init(
            id: UUID = UUID(),
            title: String,
            amount: Double,
            type: TransactionType,
            category: TransactionCategory,
            paymentMethod: PaymentMethod? = nil,
            createdByMemberId: UUID,
            date: Date = .now,
            createdAt: Date = .now,
            recurrenceRule: String? = nil,
            ownerUserId: String = "local"
        ) {
            self.id = id
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            self.title = trimmedTitle.isEmpty ? "Untitled" : trimmedTitle
            self.amount = max(0, amount)
            self.type = type
            self.category = category
            self.paymentMethod = paymentMethod
            self.createdByMemberId = createdByMemberId
            self.date = date
            self.createdAt = createdAt
            self.recurrenceRule = recurrenceRule
            self.ownerUserId = ownerUserId
        }
    }

    @Model
    final class TransactionSplit {
        var id: UUID
        var memberId: UUID
        var amount: Double
        var transaction: BudgetMateSchemaV1.Transaction?

        init(
            id: UUID = UUID(),
            memberId: UUID,
            amount: Double,
            transaction: BudgetMateSchemaV1.Transaction? = nil
        ) {
            self.id = id
            self.memberId = memberId
            self.amount = max(0, amount)
            self.transaction = transaction
        }
    }

    @Model
    final class Settlement {
        var id: UUID
        var fromMemberId: UUID
        var toMemberId: UUID
        var amount: Double
        var date: Date
        var ownerUserId: String
        var needsSync: Bool = false

        init(
            id: UUID = UUID(),
            fromMemberId: UUID,
            toMemberId: UUID,
            amount: Double,
            date: Date = .now,
            ownerUserId: String = "local"
        ) {
            self.id = id
            self.fromMemberId = fromMemberId
            self.toMemberId = toMemberId
            self.amount = max(0, amount)
            self.date = date
            self.ownerUserId = ownerUserId
        }
    }
}

/// Additive local bridge schema. Every V1 persisted property remains present;
/// the exact-money fields are optional until the explicit backfill runs.
enum BudgetMateSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Transaction.self, TransactionSplit.self, Settlement.self]
    }

    @Model
    final class Transaction {
        var id: UUID
        var title: String
        var amount: Double
        var amountMinorUnits: Int64?
        var currencyCode: String?
        var type: TransactionType
        var category: TransactionCategory
        var paymentMethod: PaymentMethod?
        var createdByMemberId: UUID
        var date: Date
        var createdAt: Date
        var recurrenceRule: String?
        var ownerUserId: String
        var needsSync: Bool = false
        @Transient var recurringSourceId: UUID?

        @Relationship(deleteRule: .cascade, inverse: \TransactionSplit.transaction)
        var splits: [TransactionSplit] = []

        init(
            id: UUID = UUID(),
            title: String,
            amount: Double,
            amountMinorUnits: Int64? = nil,
            currencyCode: String? = nil,
            type: TransactionType,
            category: TransactionCategory,
            paymentMethod: PaymentMethod? = nil,
            createdByMemberId: UUID,
            date: Date = .now,
            createdAt: Date = .now,
            recurrenceRule: String? = nil,
            ownerUserId: String = "local"
        ) {
            self.id = id
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            self.title = trimmedTitle.isEmpty ? "Untitled" : trimmedTitle
            self.amount = max(0, amount)
            self.amountMinorUnits = amountMinorUnits
            self.currencyCode = currencyCode
            self.type = type
            self.category = category
            self.paymentMethod = paymentMethod
            self.createdByMemberId = createdByMemberId
            self.date = date
            self.createdAt = createdAt
            self.recurrenceRule = recurrenceRule
            self.ownerUserId = ownerUserId
        }
    }

    @Model
    final class TransactionSplit {
        var id: UUID
        var memberId: UUID
        var amount: Double
        var amountMinorUnits: Int64?
        var currencyCode: String?
        var transaction: BudgetMateSchemaV2.Transaction?

        init(
            id: UUID = UUID(),
            memberId: UUID,
            amount: Double,
            amountMinorUnits: Int64? = nil,
            currencyCode: String? = nil,
            transaction: BudgetMateSchemaV2.Transaction? = nil
        ) {
            self.id = id
            self.memberId = memberId
            self.amount = max(0, amount)
            self.amountMinorUnits = amountMinorUnits
            self.currencyCode = currencyCode
            self.transaction = transaction
        }
    }

    @Model
    final class Settlement {
        var id: UUID
        var fromMemberId: UUID
        var toMemberId: UUID
        var amount: Double
        var amountMinorUnits: Int64?
        var currencyCode: String?
        var date: Date
        var ownerUserId: String
        var needsSync: Bool = false

        init(
            id: UUID = UUID(),
            fromMemberId: UUID,
            toMemberId: UUID,
            amount: Double,
            amountMinorUnits: Int64? = nil,
            currencyCode: String? = nil,
            date: Date = .now,
            ownerUserId: String = "local"
        ) {
            self.id = id
            self.fromMemberId = fromMemberId
            self.toMemberId = toMemberId
            self.amount = max(0, amount)
            self.amountMinorUnits = amountMinorUnits
            self.currencyCode = currencyCode
            self.date = date
            self.ownerUserId = ownerUserId
        }
    }
}

/// App-facing aliases intentionally resolve only to the current schema.
typealias Transaction = BudgetMateSchemaV2.Transaction
typealias TransactionSplit = BudgetMateSchemaV2.TransactionSplit
typealias Settlement = BudgetMateSchemaV2.Settlement

enum BudgetMateSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BudgetMateSchemaV1.self, BudgetMateSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: BudgetMateSchemaV1.self,
                toVersion: BudgetMateSchemaV2.self
            )
        ]
    }
}

enum BudgetMateSchema {
    static let currentVersion = Schema.Version(2, 0, 0)
    static let currentVersionString = "2.0.0"

    static var current: Schema {
        Schema(versionedSchema: BudgetMateSchemaV2.self)
    }
}

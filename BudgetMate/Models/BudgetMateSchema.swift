import SwiftData

/// The shipping SwiftData schema, now named and versioned without changing its
/// model identities or persisted shape.
///
/// `Transaction`, `TransactionSplit`, and `Settlement` are historical V1
/// contracts. Do not add, remove, rename, or otherwise change their persisted
/// properties. Introduce a new `VersionedSchema` instead.
enum BudgetMateSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Transaction.self,
            TransactionSplit.self,
            Settlement.self
        ]
    }
}

enum BudgetMateSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BudgetMateSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum BudgetMateSchema {
    static var current: Schema {
        Schema(versionedSchema: BudgetMateSchemaV1.self)
    }
}

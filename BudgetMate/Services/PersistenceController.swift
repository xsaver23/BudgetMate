import Foundation
import OSLog
import SwiftData

final class PersistenceController {
    static let shared = PersistenceController()
    private static let launchLogger = Logger(subsystem: "BudgetMate", category: "Launch")
    private static let launchSignposter = OSSignposter(subsystem: "BudgetMate", category: "Launch")

    let container: ModelContainer

    init(inMemory: Bool = false) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let signpostState = Self.launchSignposter.beginInterval("ModelContainer Open")
        defer {
            Self.launchSignposter.endInterval("ModelContainer Open", signpostState)
            let duration = ProcessInfo.processInfo.systemUptime - startedAt
            Self.launchLogger.notice(
                "ModelContainer opened after \(duration, privacy: .public) seconds"
            )
        }

        let schema = Schema([
            Transaction.self,
            TransactionSplit.self,
            Settlement.self
        ])
        do {
            container = try Self.makeContainer(schema: schema, inMemory: inMemory)
        } catch {
            // Never delete a financial-data store automatically. A migration,
            // disk, or transient open failure needs diagnosis; rebuilding here
            // silently erased offline transactions before they could sync.
            fatalError("Could not open the BudgetMate data store. Local data was left untouched. Error: \(error)")
        }
    }

    private static func makeContainer(schema: Schema, inMemory: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

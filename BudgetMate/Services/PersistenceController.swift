import Foundation
import SwiftData

final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    init(inMemory: Bool = false) {
        let schema = Schema([
            Transaction.self,
            TransactionSplit.self,
            Settlement.self
        ])
        do {
            container = try Self.makeContainer(schema: schema, inMemory: inMemory)
        } catch let initialError {
            guard !inMemory else {
                fatalError("Could not create in-memory ModelContainer: \(initialError)")
            }

            // For local/offline v1, recover from schema changes by rebuilding local store.
            do {
                try Self.deleteDefaultStoreFiles()
                container = try Self.makeContainer(schema: schema, inMemory: false)
            } catch let recoveryError {
                fatalError("Could not create ModelContainer. Initial error: \(initialError), recovery error: \(recoveryError)")
            }
        }
    }

    private static func makeContainer(schema: Schema, inMemory: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func deleteDefaultStoreFiles() throws {
        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first

        guard let appSupportURL else { return }

        let filenames = [
            "default.store",
            "default.store-wal",
            "default.store-shm"
        ]

        for filename in filenames {
            let fileURL = appSupportURL.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}

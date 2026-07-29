import Foundation
import OSLog
import SwiftData

/// The information needed to find the local store without reconstructing a
/// guessed Application Support path. `ModelConfiguration.url` is the source
/// of truth for the production store location.
struct PersistenceStoreDescriptor: Equatable, Sendable {
    let storeURL: URL
    let isStoredInMemoryOnly: Bool
    let schemaVersion: String

    init(
        storeURL: URL,
        isStoredInMemoryOnly: Bool = false,
        schemaVersion: String = "1.0.0"
    ) {
        self.storeURL = storeURL
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        self.schemaVersion = schemaVersion
    }
}

struct PersistenceSession {
    let container: ModelContainer
    let descriptor: PersistenceStoreDescriptor
}

enum PersistenceOpenFailureReason: String, Codable, Sendable {
    case injectedForTesting
    case storeUnavailable
    case incompatibleStore
    case interruptedRecovery
    case unknown
}

/// A deliberately redacted opening error. The underlying SwiftData error is
/// logged by the boundary that caught it, but never shown in recovery UI.
struct PersistenceOpenFailure: Error, LocalizedError, Sendable {
    let descriptor: PersistenceStoreDescriptor
    let reason: PersistenceOpenFailureReason

    var errorDescription: String? {
        switch reason {
        case .injectedForTesting:
            return "Injected persistence failure."
        case .storeUnavailable:
            return "The local data store could not be opened."
        case .incompatibleStore:
            return "The local data store is not compatible with this version."
        case .interruptedRecovery:
            return "An interrupted local-data recovery could not be completed safely."
        case .unknown:
            return "The local data store could not be opened."
        }
    }
}

@MainActor
protocol PersistenceContainerFactory {
    func makeSession() throws -> PersistenceSession
}

@MainActor
struct ClosurePersistenceContainerFactory: PersistenceContainerFactory {
    private let make: @MainActor () throws -> PersistenceSession

    init(make: @escaping @MainActor () throws -> PersistenceSession) {
        self.make = make
    }

    func makeSession() throws -> PersistenceSession {
        try make()
    }
}

@MainActor
struct LivePersistenceContainerFactory: PersistenceContainerFactory {
    let inMemory: Bool
    let storeURL: URL?

    init(inMemory: Bool = false, storeURL: URL? = nil) {
        self.inMemory = inMemory
        self.storeURL = storeURL
    }

    func makeSession() throws -> PersistenceSession {
        try PersistenceController(inMemory: inMemory, storeURL: storeURL).session
    }
}

@MainActor
final class PersistenceController {
    private static let launchLogger = Logger(subsystem: "BudgetMate", category: "Launch")
    private static let launchSignposter = OSSignposter(subsystem: "BudgetMate", category: "Launch")

    let session: PersistenceSession
    var container: ModelContainer { session.container }

    init(inMemory: Bool = false, storeURL: URL? = nil) throws {
        let signpostState = Self.launchSignposter.beginInterval("ModelContainer Open")
        defer {
            Self.launchSignposter.endInterval("ModelContainer Open", signpostState)
            Self.launchLogger.notice("ModelContainer open attempt finished")
        }

        let schema = BudgetMateSchema.current
        let configuration = Self.makeConfiguration(
            schema: schema,
            inMemory: inMemory,
            storeURL: storeURL
        )
        let descriptor = PersistenceStoreDescriptor(
            storeURL: configuration.url,
            isStoredInMemoryOnly: inMemory
        )

        do {
            if !inMemory {
                try PersistenceRecoveryService.recoverInterruptedReplacement(for: descriptor)
            }
            let container = try ModelContainer(
                for: schema,
                migrationPlan: BudgetMateSchemaMigrationPlan.self,
                configurations: [configuration]
            )
            session = PersistenceSession(container: container, descriptor: descriptor)
        } catch let failure as PersistenceOpenFailure {
            throw failure
        } catch {
            Self.launchLogger.error("ModelContainer open failed")
            throw PersistenceOpenFailure(
                descriptor: descriptor,
                reason: Self.reason(for: error)
            )
        }
    }

    static func descriptor(inMemory: Bool = false, storeURL: URL? = nil) -> PersistenceStoreDescriptor {
        let configuration = makeConfiguration(
            schema: BudgetMateSchema.current,
            inMemory: inMemory,
            storeURL: storeURL
        )
        return PersistenceStoreDescriptor(
            storeURL: configuration.url,
            isStoredInMemoryOnly: inMemory
        )
    }

    private static func makeConfiguration(
        schema: Schema,
        inMemory: Bool,
        storeURL: URL?
    ) -> ModelConfiguration {
        if let storeURL {
            return ModelConfiguration(
                "BudgetMate",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        }

        // Keep the production default exactly as PR01A defined it. SwiftData
        // chooses the URL; callers capture the resolved value above.
        return ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
    }

    private static func reason(for error: Error) -> PersistenceOpenFailureReason {
        let text = String(describing: error).lowercased()
        if text.contains("migration") || text.contains("schema") || text.contains("incompatible") {
            return .incompatibleStore
        }
        return .storeUnavailable
    }
}

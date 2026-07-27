import SwiftData
@testable import BudgetMate

@MainActor
final class InMemoryModelContainer {
    private let persistenceController: PersistenceController

    let container: ModelContainer
    let context: ModelContext

    init() {
        persistenceController = PersistenceController(inMemory: true)
        container = persistenceController.container
        context = container.mainContext
    }
}

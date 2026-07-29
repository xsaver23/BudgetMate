import Foundation
import SwiftData

enum PreviewContainer {
    @MainActor
    static var seeded: ModelContainer {
        let container = try! PersistenceController(inMemory: true).container
        SampleDataSeeder.seed(
            into: container.mainContext,
            members: MemberSampleData.members
        )
        return container
    }
}

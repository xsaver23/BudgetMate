import SwiftData
import XCTest
@testable import BudgetMate

@MainActor
final class ScopedPersistenceCharacterizationTests: XCTestCase {
    func testInMemorySwiftDataContainerStoresOnlyRowsForRequestedBudgetScope() throws {
        let store = InMemoryModelContainer()
        let personalTransaction = BudgetMateTestFixtures.expense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000110")!,
            amount: 10
        )
        personalTransaction.ownerUserId = BudgetMateTestFixtures.personalBudgetID.uuidString

        let sharedTransaction = BudgetMateTestFixtures.expense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
            amount: 20
        )
        sharedTransaction.ownerUserId = BudgetMateTestFixtures.sharedBudgetID.uuidString

        let personalSettlement = BudgetMateTestFixtures.settlement(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
            amount: 5
        )
        personalSettlement.ownerUserId = BudgetMateTestFixtures.personalBudgetID.uuidString

        store.context.insert(personalTransaction)
        store.context.insert(sharedTransaction)
        store.context.insert(personalSettlement)
        try store.context.save()

        let personalScope = BudgetMateTestFixtures.personalBudgetID.uuidString
        let transactionDescriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.ownerUserId == personalScope }
        )
        let settlementDescriptor = FetchDescriptor<Settlement>(
            predicate: #Predicate { $0.ownerUserId == personalScope }
        )

        let transactions = try store.context.fetch(transactionDescriptor)
        let settlements = try store.context.fetch(settlementDescriptor)
        XCTAssertEqual(transactions.map(\.id), [personalTransaction.id])
        XCTAssertEqual(settlements.map(\.id), [personalSettlement.id])
    }

    func testSettingsRemainScopedToTheSelectedBudget() {
        let defaults = BudgetMateTestFixtures.isolatedDefaults()
        let store = SettingsStore(userDefaults: defaults)

        store.switchUser(to: BudgetMateTestFixtures.personalBudgetID.uuidString)
        store.updateCurrencyCode("CAD")
        store.updateCategoryBudget(300, for: .groceries)

        store.switchUser(to: BudgetMateTestFixtures.sharedBudgetID.uuidString)
        XCTAssertEqual(store.settings.currencyCode, "USD")
        XCTAssertEqual(store.budgetAmount(for: .groceries), 0, accuracy: 0.001)
        store.updateCurrencyCode("EUR")

        store.switchUser(to: BudgetMateTestFixtures.personalBudgetID.uuidString)
        XCTAssertEqual(store.settings.currencyCode, "CAD")
        XCTAssertEqual(store.budgetAmount(for: .groceries), 300, accuracy: 0.001)
        XCTAssertNotEqual(store.settings.currencyCode, "EUR")
    }

    func testMembersRemainScopedToTheSelectedBudget() {
        let defaults = BudgetMateTestFixtures.isolatedDefaults()
        let initialBudget = BudgetMateTestFixtures.personalBudget
        let repository = LocalBudgetRepository(
            userDefaults: defaults,
            userScopeId: BudgetMateTestFixtures.aliceUserID.uuidString,
            fallbackBudget: initialBudget
        )
        let viewModel = MemberViewModel(
            repository: repository,
            userDefaults: defaults,
            userScopeId: BudgetMateTestFixtures.aliceUserID.uuidString
        )

        viewModel.switchUser(
            to: BudgetMateTestFixtures.aliceUserID.uuidString,
            budgetScopeId: BudgetMateTestFixtures.personalBudgetID.uuidString,
            email: "alice@example.com"
        )
        viewModel.replaceMembersWithLocalChanges([BudgetMateTestFixtures.alice])

        viewModel.switchUser(
            to: BudgetMateTestFixtures.aliceUserID.uuidString,
            budgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            email: "alice@example.com"
        )
        viewModel.replaceMembersWithLocalChanges([
            BudgetMateTestFixtures.alice,
            BudgetMateTestFixtures.bob,
            BudgetMateTestFixtures.invitedMember
        ])

        viewModel.switchUser(
            to: BudgetMateTestFixtures.aliceUserID.uuidString,
            budgetScopeId: BudgetMateTestFixtures.personalBudgetID.uuidString,
            email: "alice@example.com"
        )
        XCTAssertEqual(viewModel.members.map(\.id), [BudgetMateTestFixtures.aliceMemberID])

        viewModel.switchUser(
            to: BudgetMateTestFixtures.aliceUserID.uuidString,
            budgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            email: "alice@example.com"
        )
        XCTAssertEqual(viewModel.members.map(\.id), [
            BudgetMateTestFixtures.aliceMemberID,
            BudgetMateTestFixtures.bobMemberID,
            BudgetMateTestFixtures.invitedMemberID
        ])
    }
}

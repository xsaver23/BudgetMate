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

    func testClearAllGuardrailHasNoEnabledActionAndExplainsRecoveryRequirement() {
        let restriction = DestructiveActionGuardrails.clearAll

        XCTAssertFalse(restriction.isEnabled)
        XCTAssertEqual(restriction.title, "Clear All Transactions")
        XCTAssertTrue(restriction.message.localizedCaseInsensitiveContains("temporarily unavailable"))
        XCTAssertTrue(restriction.message.localizedCaseInsensitiveContains("atomic"))
        XCTAssertTrue(restriction.message.localizedCaseInsensitiveContains("recoverable"))
        XCTAssertEqual(restriction.accessibilityIdentifier, "settings.clearAllUnavailable")
    }

    func testAcceptedMemberRemovalGuardrailProtectsSharedTransactionHistory() {
        let restriction = DestructiveActionGuardrails.memberRemoval(for: BudgetMateTestFixtures.bob)

        XCTAssertFalse(restriction.isEnabled)
        XCTAssertTrue(restriction.title.contains(BudgetMateTestFixtures.bob.displayName))
        XCTAssertTrue(restriction.message.localizedCaseInsensitiveContains("accepted member"))
        XCTAssertTrue(restriction.message.localizedCaseInsensitiveContains("transaction history"))
        XCTAssertTrue(restriction.accessibilityIdentifier.contains("acceptedRemovalUnavailable"))
    }

    func testInvitePlaceholderRemovalIsAlsoUnavailableUntilItIsProvenHistorySafe() {
        let restriction = DestructiveActionGuardrails.memberRemoval(for: BudgetMateTestFixtures.invitedMember)

        XCTAssertFalse(restriction.isEnabled)
        XCTAssertTrue(restriction.title.localizedCaseInsensitiveContains("cancel invite"))
        XCTAssertTrue(restriction.message.localizedCaseInsensitiveContains("temporarily unavailable"))
        XCTAssertTrue(restriction.message.localizedCaseInsensitiveContains("history-safe"))
        XCTAssertTrue(restriction.accessibilityIdentifier.contains("inviteCancellationUnavailable"))
    }

    func testMemberRemovalGuardrailBlocksLegacyAndAmbiguousIdentityShapes() {
        let activeWithoutAuthIdentity = BudgetMember(
            displayName: "Legacy Member",
            email: "legacy@example.com",
            initials: "LM",
            color: "#3B82F6",
            authUserId: nil,
            role: .member,
            inviteStatus: .active
        )
        let pendingWithAuthIdentity = BudgetMember(
            displayName: "Ambiguous Member",
            email: "ambiguous@example.com",
            initials: "AM",
            color: "#F97316",
            authUserId: BudgetMateTestFixtures.carolUserID,
            role: .member,
            inviteStatus: .pending
        )

        for member in [activeWithoutAuthIdentity, pendingWithAuthIdentity] {
            let restriction = DestructiveActionGuardrails.memberRemoval(for: member)
            XCTAssertFalse(restriction.isEnabled)
            XCTAssertTrue(restriction.message.localizedCaseInsensitiveContains("temporarily unavailable"))
        }
    }

    func testPersonalBudgetRecordMutationsRemainAvailable() {
        let decision = SharedRecordMutationCapability.decision(
            currentUserScopeId: BudgetMateTestFixtures.aliceUserID.uuidString,
            activeBudgetScopeId: BudgetMateTestFixtures.aliceUserID.uuidString,
            recordBudgetScopeId: BudgetMateTestFixtures.aliceUserID.uuidString,
            members: []
        )

        XCTAssertTrue(decision.isAllowed)
        XCTAssertEqual(decision.reason, .personalBudget)
        XCTAssertNil(decision.readOnlyMessage)
    }

    func testAuthenticatedHouseholdOwnerCanMutateSharedRecords() {
        let decision = SharedRecordMutationCapability.decision(
            currentUserScopeId: BudgetMateTestFixtures.aliceUserID.uuidString,
            activeBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            recordBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            members: [BudgetMateTestFixtures.alice, BudgetMateTestFixtures.bob]
        )

        XCTAssertTrue(decision.isAllowed)
        XCTAssertEqual(decision.reason, .householdOwner)
    }

    func testRegularHouseholdMemberCannotMutateSharedRecords() {
        let decision = SharedRecordMutationCapability.decision(
            currentUserScopeId: BudgetMateTestFixtures.bobUserID.uuidString,
            activeBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            recordBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            members: [BudgetMateTestFixtures.alice, BudgetMateTestFixtures.bob]
        )

        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.reason, .restrictedSharedMember)
        XCTAssertEqual(
            decision.readOnlyMessage,
            "Only the household owner can edit or delete shared records right now."
        )
    }

    func testUnverifiedOwnerDisplayRoleDoesNotGrantSharedMutationAuthority() {
        let unmatchedOwner = BudgetMember(
            displayName: "Unverified Owner",
            email: "alice@example.com",
            initials: "UO",
            color: "#3B82F6",
            authUserId: nil,
            role: .owner,
            inviteStatus: .active
        )
        let decision = SharedRecordMutationCapability.decision(
            currentUserScopeId: BudgetMateTestFixtures.aliceUserID.uuidString,
            activeBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            recordBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            members: [unmatchedOwner]
        )

        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.reason, .restrictedSharedMember)
    }

    func testAmbiguousAuthenticatedMemberIdentityFailsClosed() {
        let legacyAlias = BudgetMember(
            id: BudgetMateTestFixtures.aliceUserID,
            displayName: "Legacy Alice",
            email: "alice@example.com",
            initials: "LA",
            color: "#F97316",
            authUserId: nil,
            role: .member,
            inviteStatus: .active
        )
        let decision = SharedRecordMutationCapability.decision(
            currentUserScopeId: BudgetMateTestFixtures.aliceUserID.uuidString,
            activeBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            recordBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            members: [BudgetMateTestFixtures.alice, legacyAlias]
        )

        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.reason, .restrictedSharedMember)
    }

    func testRecordFromInactiveBudgetFailsClosed() {
        let decision = SharedRecordMutationCapability.decision(
            currentUserScopeId: BudgetMateTestFixtures.aliceUserID.uuidString,
            activeBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            recordBudgetScopeId: BudgetMateTestFixtures.aliceUserID.uuidString,
            members: [BudgetMateTestFixtures.alice]
        )

        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.reason, .restrictedSharedMember)
    }
}

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

    func testGateDSharedBudgetActionsAreUnavailable() {
        let leaveRestriction = DestructiveActionGuardrails.leaveSharedBudget
        XCTAssertFalse(leaveRestriction.isEnabled)
        XCTAssertTrue(leaveRestriction.message.localizedCaseInsensitiveContains("temporarily unavailable"))
        XCTAssertEqual(leaveRestriction.accessibilityIdentifier, "settings.leaveSharedBudgetUnavailable")

        let inviteRestriction = DestructiveActionGuardrails.inviteCreation
        XCTAssertFalse(inviteRestriction.isEnabled)
        XCTAssertTrue(inviteRestriction.message.localizedCaseInsensitiveContains("invites"))
        XCTAssertEqual(inviteRestriction.accessibilityIdentifier, "budgetMembers.invitesUnavailable")
    }

    func testReleaseSupabaseConfigurationRejectsUnsafeValuesButKeepsHostOnlyHTTPS() {
        XCTAssertNil(SupabaseConfig.validatedProjectURL(rawValue: nil, allowHTTP: false))
        XCTAssertNil(SupabaseConfig.validatedProjectURL(rawValue: "your-project.supabase.co", allowHTTP: false))
        XCTAssertNil(SupabaseConfig.validatedProjectURL(rawValue: "http://budgetmate.supabase.co", allowHTTP: false))
        XCTAssertNil(SupabaseConfig.validatedProjectURL(rawValue: "https://localhost", allowHTTP: false))
        XCTAssertNil(SupabaseConfig.validatedProjectURL(rawValue: "https://127.0.0.1", allowHTTP: false))
        XCTAssertNil(SupabaseConfig.validatedProjectURL(rawValue: "https://configuration.invalid", allowHTTP: false))
        XCTAssertNil(SupabaseConfig.validatedProjectURL(rawValue: "https://example.com", allowHTTP: false))
        XCTAssertEqual(
            SupabaseConfig.validatedProjectURL(rawValue: "budgetmate.supabase.co", allowHTTP: false)?.scheme,
            "https"
        )
        XCTAssertEqual(
            SupabaseConfig.validatedProjectURL(rawValue: "http://localhost:54321", allowHTTP: true)?.scheme,
            "http"
        )
        XCTAssertNil(SupabaseConfig.validatedPublishableKey("your-publishable-key"))
        XCTAssertNil(SupabaseConfig.validatedPublishableKey("missing-publishable-key"))
        XCTAssertNil(SupabaseConfig.validatedPublishableKey("placeholder-key"))
        XCTAssertEqual(SupabaseConfig.validatedPublishableKey("beta-publishable-key"), "beta-publishable-key")
    }

    func testCloudSyncStoreRejectsGateDInviteAndLeaveCallsBeforeNetworkAccess() async {
        let store = CloudSyncStore()

        do {
            _ = try await store.ensureSharedBudget(name: "Should not be created", userScopeId: "user")
            XCTFail("Gate D must prevent shared-budget creation through the invite path.")
        } catch SupabaseBudgetSyncError.sharedBudgetInvitesUnavailable {
            // Expected.
        } catch {
            XCTFail("Unexpected shared-budget creation error: \(error)")
        }

        do {
            try await store.inviteMember(
                displayName: "Should not be invited",
                email: "blocked@example.com",
                userScopeId: "user",
                budgetId: UUID()
            )
            XCTFail("Gate D must prevent invite creation before network access.")
        } catch SupabaseBudgetSyncError.sharedBudgetInvitesUnavailable {
            // Expected.
        } catch {
            XCTFail("Unexpected invite error: \(error)")
        }

        do {
            try await store.leaveBudget(userScopeId: "user", budgetScopeId: UUID().uuidString)
            XCTFail("Gate D must prevent leaving a shared budget before network access.")
        } catch SupabaseBudgetSyncError.sharedBudgetLeaveUnavailable {
            // Expected.
        } catch {
            XCTFail("Unexpected leave-budget error: \(error)")
        }
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
            members: [BudgetMateTestFixtures.alice, BudgetMateTestFixtures.bob],
            serverGateEnabled: true
        )

        XCTAssertTrue(decision.isAllowed)
        XCTAssertEqual(decision.reason, .householdOwner)
    }

    func testRegularHouseholdMemberCannotMutateSharedRecords() {
        let decision = SharedRecordMutationCapability.decision(
            currentUserScopeId: BudgetMateTestFixtures.bobUserID.uuidString,
            activeBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            recordBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            members: [BudgetMateTestFixtures.alice, BudgetMateTestFixtures.bob],
            serverGateEnabled: true
        )

        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.reason, .restrictedSharedMember)
        XCTAssertEqual(
            decision.readOnlyMessage,
            "Only the household owner or the authenticated record creator can edit or delete shared records right now."
        )
    }

    func testActiveHouseholdMemberCanCreateSharedRecordsWhenGateIsEnabled() {
        let decision = SharedRecordMutationCapability.decision(
            currentUserScopeId: BudgetMateTestFixtures.bobUserID.uuidString,
            activeBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            recordBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            members: [BudgetMateTestFixtures.alice, BudgetMateTestFixtures.bob],
            operation: .create,
            serverGateEnabled: true
        )

        XCTAssertTrue(decision.isAllowed)
        XCTAssertEqual(decision.reason, .activeHouseholdMemberCreating)
        XCTAssertNil(decision.readOnlyMessage)
    }

    func testSharedRecordCreationStillFailsClosedWhenGateIsDisabled() {
        let decision = SharedRecordMutationCapability.decision(
            currentUserScopeId: BudgetMateTestFixtures.bobUserID.uuidString,
            activeBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            recordBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            members: [BudgetMateTestFixtures.alice, BudgetMateTestFixtures.bob],
            operation: .create,
            serverGateEnabled: false
        )

        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.reason, .sharedDataSafetyDisabled)
    }

    func testSharedDataSafetyGateFailsClosedBeforeServerActivation() {
        let decision = SharedRecordMutationCapability.decision(
            currentUserScopeId: BudgetMateTestFixtures.aliceUserID.uuidString,
            activeBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            recordBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            members: [BudgetMateTestFixtures.alice, BudgetMateTestFixtures.bob]
        )

        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.reason, .sharedDataSafetyDisabled)
        XCTAssertEqual(decision.readOnlyMessage, SharedDataSafetyGate.readOnlyMessage)
    }

    func testEnabledGateCConfigurationPreservesSharedOwnerCapabilityRules() {
        let configuration = GateCClientRolloutConfiguration(values: [
            GateCClientRolloutConfiguration.serverReadyKey: "YES",
            GateCClientRolloutConfiguration.sharedDataSafetyKey: "YES",
            GateCClientRolloutConfiguration.moneyServerBridgeKey: "YES"
        ])
        let decision = SharedRecordMutationCapability.decision(
            currentUserScopeId: BudgetMateTestFixtures.aliceUserID.uuidString,
            activeBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            recordBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            members: [BudgetMateTestFixtures.alice, BudgetMateTestFixtures.bob],
            serverGateEnabled: configuration.isEnabled
        )

        XCTAssertTrue(decision.isAllowed)
        XCTAssertEqual(decision.reason, .householdOwner)
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
            members: [unmatchedOwner],
            serverGateEnabled: true
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
            members: [BudgetMateTestFixtures.alice, legacyAlias],
            serverGateEnabled: true
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

    func testCurrencyChangeIsAvailableAfterValidatedEmptyHistory() {
        for budgetScopeId in [
            BudgetMateTestFixtures.personalBudgetID.uuidString,
            BudgetMateTestFixtures.sharedBudgetID.uuidString
        ] {
            let decision = CurrencyChangeGuardrail.decision(
                activeBudgetScopeId: budgetScopeId,
                presentedBudgetScopeId: budgetScopeId,
                isHistoryValidated: true,
                isSyncing: false,
                history: currencyHistory(budgetScopeId: budgetScopeId)
            )

            XCTAssertTrue(decision.isAllowed)
            XCTAssertEqual(decision.reason, .available)
        }
    }

    func testCurrencyChangeWaitsForCurrentBudgetHistoryValidation() {
        let emptyHistory = currencyHistory()

        for decision in [
            CurrencyChangeGuardrail.decision(
                activeBudgetScopeId: BudgetMateTestFixtures.personalBudgetID.uuidString,
                presentedBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
                isHistoryValidated: true,
                isSyncing: false,
                history: emptyHistory
            ),
            CurrencyChangeGuardrail.decision(
                activeBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
                presentedBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
                isHistoryValidated: false,
                isSyncing: false,
                history: emptyHistory
            ),
            CurrencyChangeGuardrail.decision(
                activeBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
                presentedBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
                isHistoryValidated: true,
                isSyncing: true,
                history: emptyHistory
            )
        ] {
            XCTAssertFalse(decision.isAllowed)
            XCTAssertEqual(decision.reason, .checkingHistory)
        }
    }

    func testEveryStoredFinancialRecordKindLocksCurrency() {
        let activeScope = BudgetMateTestFixtures.sharedBudgetID.uuidString
        let histories = [
            currencyHistory(
                transactionOwnerScopeIds: [activeScope]
            ),
            currencyHistory(
                splitTransactionOwnerScopeIds: [activeScope]
            ),
            currencyHistory(
                settlementOwnerScopeIds: [activeScope]
            )
        ]

        for history in histories {
            let decision = CurrencyChangeGuardrail.decision(
                activeBudgetScopeId: activeScope,
                presentedBudgetScopeId: activeScope,
                isHistoryValidated: true,
                isSyncing: false,
                history: history
            )

            XCTAssertFalse(decision.isAllowed)
            XCTAssertEqual(decision.reason, .financialHistory)
        }
    }

    func testOtherKnownBudgetRecordsDoNotLockValidatedEmptyScope() {
        let history = currencyHistory(
            transactionOwnerScopeIds: [BudgetMateTestFixtures.personalBudgetID.uuidString],
            splitTransactionOwnerScopeIds: [BudgetMateTestFixtures.personalBudgetID.uuidString],
            settlementOwnerScopeIds: [BudgetMateTestFixtures.personalBudgetID.uuidString]
        )

        XCTAssertEqual(history.state, .knownEmpty)
    }

    func testLegacyOrOrphanRecordScopesFailClosed() {
        for history in [
            currencyHistory(transactionOwnerScopeIds: ["local"]),
            currencyHistory(settlementOwnerScopeIds: ["malformed-scope"]),
            currencyHistory(splitTransactionOwnerScopeIds: [nil])
        ] {
            let decision = CurrencyChangeGuardrail.decision(
                activeBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
                presentedBudgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
                isHistoryValidated: true,
                isSyncing: false,
                history: history
            )

            XCTAssertEqual(history.state, .unknown)
            XCTAssertFalse(decision.isAllowed)
            XCTAssertEqual(decision.reason, .unverifiedHistory)
        }
    }

    func testEveryStoredCategoryBudgetKeyLocksCurrency() {
        let keys = [
            TransactionCategory.groceries.rawValue,
            BudgetSettings.monthBudgetKey(
                monthKey: "2026-07",
                categoryRawValue: TransactionCategory.rent.rawValue
            ),
            TransactionCategory.hiddenMarkerKey(for: .restaurant)
        ]

        for key in keys {
            XCTAssertEqual(currencyHistory(categoryBudgetKeys: [key]).state, .populated)
        }
    }

    func testRemoteCategoryBaselineAndRacingLocalEditRemainLocked() {
        let budgetScopeId = BudgetMateTestFixtures.sharedBudgetID.uuidString
        let store = SettingsStore(userDefaults: BudgetMateTestFixtures.isolatedDefaults())
        store.switchUser(to: budgetScopeId)
        let remoteSettings = BudgetSettings(
            monthlyBudget: 0,
            currencyCode: CurrencyOption.cad.code,
            categoryBudgets: [TransactionCategory.groceries.rawValue: 0]
        )

        store.updateAppearance(.dark)
        store.recordCloudSettingsBaseline(remoteSettings)

        let history = CurrencyFinancialHistorySnapshot(
            budgetScopeId: budgetScopeId,
            transactionOwnerScopeIds: [],
            splitTransactionOwnerScopeIds: [],
            settlementOwnerScopeIds: [],
            categoryBudgetKeys: Array(store.settings.categoryBudgets.keys),
            hasPreviouslyObservedFinancialHistory: store.hasObservedFinancialHistory
        )
        let decision = CurrencyChangeGuardrail.decision(
            activeBudgetScopeId: budgetScopeId,
            presentedBudgetScopeId: budgetScopeId,
            isHistoryValidated:
                store.hasObservedCloudSettingsBaseline &&
                store.pendingCloudSyncToken == nil,
            isSyncing: false,
            history: history
        )

        XCTAssertTrue(store.hasObservedCloudSettingsBaseline)
        XCTAssertTrue(store.hasObservedFinancialHistory)
        XCTAssertNotNil(store.pendingCloudSyncToken)
        XCTAssertEqual(store.settings.currencyCode, CurrencyOption.cad.code)
        XCTAssertEqual(history.state, .populated)
        XCTAssertFalse(decision.isAllowed)
    }

    func testRemoteRecordBaselineAdoptsCurrencyBeforePendingSettingsPush() {
        let budgetScopeId = BudgetMateTestFixtures.sharedBudgetID.uuidString
        let store = SettingsStore(userDefaults: BudgetMateTestFixtures.isolatedDefaults())
        store.switchUser(to: budgetScopeId)
        store.updateAppearance(.dark)
        let remoteSettings = BudgetSettings(
            monthlyBudget: 0,
            currencyCode: CurrencyOption.cad.code,
            categoryBudgets: [:]
        )

        store.recordCloudSettingsBaseline(
            remoteSettings,
            hasRemoteFinancialRecords: true
        )

        XCTAssertTrue(store.hasObservedCloudSettingsBaseline)
        XCTAssertTrue(store.hasObservedFinancialHistory)
        XCTAssertEqual(store.settings.currencyCode, CurrencyOption.cad.code)
        XCTAssertNotNil(store.pendingCloudSyncToken)
    }

    func testObservedCategoryHistorySurvivesSettingsReset() {
        let store = SettingsStore(userDefaults: BudgetMateTestFixtures.isolatedDefaults())
        store.switchUser(to: BudgetMateTestFixtures.sharedBudgetID.uuidString)
        store.updateCategoryBudget(0, for: .groceries)
        XCTAssertTrue(store.hasObservedFinancialHistory)

        store.resetSettings(preservingCurrencyCode: true)

        XCTAssertTrue(store.settings.categoryBudgets.isEmpty)
        XCTAssertTrue(store.hasObservedFinancialHistory)
    }

    func testObservedCurrencyGuardStateIsBudgetScoped() {
        let store = SettingsStore(userDefaults: BudgetMateTestFixtures.isolatedDefaults())
        store.switchUser(to: BudgetMateTestFixtures.sharedBudgetID.uuidString)
        store.recordCloudSettingsBaseline(
            BudgetMateTestFixtures.settings,
            hasRemoteFinancialRecords: true
        )
        XCTAssertTrue(store.hasObservedCloudSettingsBaseline)
        XCTAssertTrue(store.hasObservedFinancialHistory)

        store.switchUser(to: BudgetMateTestFixtures.personalBudgetID.uuidString)

        XCTAssertFalse(store.hasObservedCloudSettingsBaseline)
        XCTAssertFalse(store.hasObservedFinancialHistory)
    }

    func testPositiveLegacyMonthlyBudgetDecodesIntoLockingCategoryEntry() throws {
        let data = try XCTUnwrap(
            """
            {
              "monthlyBudget": 250,
              "currencySymbol": "$",
              "appearance": "system"
            }
            """.data(using: .utf8)
        )
        let decoded = try JSONDecoder().decode(BudgetSettings.self, from: data)

        XCTAssertEqual(
            currencyHistory(categoryBudgetKeys: Array(decoded.categoryBudgets.keys)).state,
            .populated
        )
    }

    func testFreshMutationSnapshotClosesPreviouslyEmptyCurrencyAction() throws {
        let persistence = InMemoryModelContainer()
        let budgetScopeId = BudgetMateTestFixtures.sharedBudgetID.uuidString
        let staleHistory = try CurrencyChangeGuardrail.snapshot(
            in: persistence.context,
            budgetScopeId: budgetScopeId,
            categoryBudgetKeys: []
        )
        XCTAssertEqual(staleHistory.state, .knownEmpty)

        persistence.context.insert(BudgetMateTestFixtures.expense())

        let freshHistory = try CurrencyChangeGuardrail.snapshot(
            in: persistence.context,
            budgetScopeId: budgetScopeId,
            categoryBudgetKeys: []
        )
        let freshDecision = CurrencyChangeGuardrail.decision(
            activeBudgetScopeId: budgetScopeId,
            presentedBudgetScopeId: budgetScopeId,
            isHistoryValidated: true,
            isSyncing: false,
            history: freshHistory
        )

        XCTAssertEqual(freshHistory.state, .populated)
        XCTAssertFalse(freshDecision.isAllowed)
    }

    func testFreshResetDecisionPreservesCurrencyAfterStaleEmptyState() throws {
        let persistence = InMemoryModelContainer()
        let budgetScopeId = BudgetMateTestFixtures.sharedBudgetID.uuidString
        let defaults = BudgetMateTestFixtures.isolatedDefaults()
        let store = SettingsStore(userDefaults: defaults)
        store.updateCurrencyCode(CurrencyOption.cad.code)

        let staleHistory = try CurrencyChangeGuardrail.snapshot(
            in: persistence.context,
            budgetScopeId: budgetScopeId,
            categoryBudgetKeys: []
        )
        XCTAssertEqual(staleHistory.state, .knownEmpty)

        persistence.context.insert(BudgetMateTestFixtures.settlement())
        let freshHistory = try CurrencyChangeGuardrail.snapshot(
            in: persistence.context,
            budgetScopeId: budgetScopeId,
            categoryBudgetKeys: []
        )
        let freshDecision = CurrencyChangeGuardrail.decision(
            activeBudgetScopeId: budgetScopeId,
            presentedBudgetScopeId: budgetScopeId,
            isHistoryValidated: true,
            isSyncing: false,
            history: freshHistory
        )

        store.resetSettings(preservingCurrencyCode: !freshDecision.isAllowed)

        XCTAssertFalse(freshDecision.isAllowed)
        XCTAssertEqual(store.settings.currencyCode, CurrencyOption.cad.code)
    }

    func testResetSettingsCanPreserveLockedCurrency() {
        let defaults = BudgetMateTestFixtures.isolatedDefaults()
        let store = SettingsStore(userDefaults: defaults)
        store.updateCurrencyCode(CurrencyOption.cad.code)
        store.updateCategoryBudget(200, for: .groceries)

        store.resetSettings(preservingCurrencyCode: true)

        XCTAssertEqual(store.settings.currencyCode, CurrencyOption.cad.code)
        XCTAssertTrue(store.settings.categoryBudgets.isEmpty)
        XCTAssertEqual(store.settings.appearance, .system)
    }

    func testFirstCloudHydrationAdoptsCurrencyBaselineBeforeLocking() {
        let store = SettingsStore(userDefaults: BudgetMateTestFixtures.isolatedDefaults())
        let cloudSettings = BudgetSettings(
            monthlyBudget: 0,
            currencyCode: CurrencyOption.cad.code,
            appearance: .dark,
            categoryBudgets: [TransactionCategory.groceries.rawValue: 0]
        )

        store.replaceSettings(
            cloudSettings,
            preservingEstablishedCurrency: true
        )

        XCTAssertEqual(store.settings.currencyCode, CurrencyOption.cad.code)
        XCTAssertEqual(store.settings.appearance, .dark)
        XCTAssertNil(store.pendingCloudSyncToken)
    }

    func testDefaultFirstHydrationStillEstablishesProtectedBaseline() {
        let store = SettingsStore(userDefaults: BudgetMateTestFixtures.isolatedDefaults())
        store.replaceSettings(
            .default,
            preservingEstablishedCurrency: true
        )

        let conflictingCloudSettings = BudgetSettings(
            monthlyBudget: 0,
            currencyCode: CurrencyOption.cad.code,
            categoryBudgets: [TransactionCategory.groceries.rawValue: 0]
        )
        store.replaceSettings(
            conflictingCloudSettings,
            preservingEstablishedCurrency: true
        )

        XCTAssertEqual(store.settings.currencyCode, CurrencyOption.usd.code)
        XCTAssertNotNil(store.pendingCloudSyncToken)
    }

    func testLaterCloudConflictPreservesEstablishedCurrencyAndQueuesRepair() {
        let defaults = BudgetMateTestFixtures.isolatedDefaults()
        let store = SettingsStore(userDefaults: defaults)
        store.updateCurrencyCode(CurrencyOption.eur.code)
        if let token = store.pendingCloudSyncToken {
            store.markCloudSyncSucceeded(token)
        }

        let conflictingCloudSettings = BudgetSettings(
            monthlyBudget: 0,
            currencyCode: CurrencyOption.cad.code,
            appearance: .dark,
            categoryBudgets: [TransactionCategory.groceries.rawValue: 0]
        )
        store.replaceSettings(
            conflictingCloudSettings,
            preservingEstablishedCurrency: true
        )

        XCTAssertEqual(store.settings.currencyCode, CurrencyOption.eur.code)
        XCTAssertEqual(store.settings.appearance, .dark)
        XCTAssertNotNil(store.pendingCloudSyncToken)
    }

    private func currencyHistory(
        budgetScopeId: String = BudgetMateTestFixtures.sharedBudgetID.uuidString,
        transactionOwnerScopeIds: [String] = [],
        splitTransactionOwnerScopeIds: [String?] = [],
        settlementOwnerScopeIds: [String] = [],
        categoryBudgetKeys: [String] = []
    ) -> CurrencyFinancialHistorySnapshot {
        CurrencyFinancialHistorySnapshot(
            budgetScopeId: budgetScopeId,
            transactionOwnerScopeIds: transactionOwnerScopeIds,
            splitTransactionOwnerScopeIds: splitTransactionOwnerScopeIds,
            settlementOwnerScopeIds: settlementOwnerScopeIds,
            categoryBudgetKeys: categoryBudgetKeys
        )
    }
}

import Foundation
import XCTest
@testable import BudgetMate

@MainActor
final class CloudPersistenceCharacterizationTests: XCTestCase {
    func testCloudSettingsAndMemberRowsRoundTripWithoutABackend() throws {
        let settingsData = try JSONEncoder().encode(BudgetMateTestFixtures.cloudSettingsRow)
        let decodedSettings = try JSONDecoder().decode(CloudBudgetSettingsRow.self, from: settingsData)
        let settings = decodedSettings.makeSettings()

        XCTAssertEqual(decodedSettings.userId, BudgetMateTestFixtures.aliceUserID)
        XCTAssertEqual(decodedSettings.budgetId, BudgetMateTestFixtures.sharedBudgetID)
        XCTAssertEqual(settings.currencyCode, BudgetMateTestFixtures.settings.currencyCode)
        XCTAssertEqual(settings.categoryBudgets, BudgetMateTestFixtures.settings.categoryBudgets)

        let memberData = try JSONEncoder().encode(BudgetMateTestFixtures.cloudMemberRow)
        let decodedMember = try JSONDecoder().decode(CloudBudgetMemberRow.self, from: memberData)
        try decodedMember.validateDates()
        let member = decodedMember.makeMember()

        XCTAssertEqual(member.id, BudgetMateTestFixtures.bob.id)
        XCTAssertEqual(member.email, "bob@example.com")
        XCTAssertEqual(member.inviteStatus, .active)
    }

    func testCloudTransactionRowPreservesSplitPayloadAndCanBeAppliedIdempotently() throws {
        let row = BudgetMateTestFixtures.cloudTransactionRow
        let data = try JSONEncoder().encode(row)
        let decoded = try JSONDecoder().decode(CloudTransactionRow.self, from: data)
        try decoded.validateDates()

        let local = decoded.makeTransaction(
            ownerUserId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            validMemberIds: [BudgetMateTestFixtures.aliceMemberID, BudgetMateTestFixtures.bobMemberID]
        )
        local.splits = decoded.splits.map {
            TransactionSplit(
                id: $0.id,
                memberId: $0.memberId,
                amount: $0.amount,
                transaction: local
            )
        }

        XCTAssertEqual(decoded.splits.count, 2)
        XCTAssertEqual(decoded.splits.map(\.amount).reduce(0, +), decoded.amount, accuracy: 0.001)
        XCTAssertTrue(
            decoded.matches(
                local,
                ownerUserId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
                memberAliases: [:],
                validMemberIds: [BudgetMateTestFixtures.aliceMemberID, BudgetMateTestFixtures.bobMemberID]
            )
        )
        XCTAssertTrue(decoded.splitsMatch(local, memberAliases: [:]))
    }

    func testCloudSettlementRowRoundTripsAndKeepsBusinessDateCompatibilityField() throws {
        let row = BudgetMateTestFixtures.cloudSettlementRow
        let data = try JSONEncoder().encode(row)
        let decoded = try JSONDecoder().decode(CloudSettlementRow.self, from: data)
        try decoded.validateDate()

        let local = decoded.makeSettlement(ownerUserId: BudgetMateTestFixtures.sharedBudgetID.uuidString)

        XCTAssertEqual(decoded.id, BudgetMateTestFixtures.settlementID)
        XCTAssertEqual(decoded.occurredOn?.count, 10)
        XCTAssertTrue(
            decoded.matches(
                local,
                ownerUserId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
                memberAliases: [:]
            )
        )
    }

    func testPendingCloudDeletionEncodingAndRestorationAreStable() throws {
        let expected = BudgetMateTestFixtures.pendingDeletion
        let encoded = try JSONEncoder().encode([expected])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        let first = try XCTUnwrap(object.first)

        XCTAssertEqual(first["entity"] as? String, "transaction")
        XCTAssertEqual(first["recordId"] as? String, expected.recordId.uuidString)
        XCTAssertEqual(first["userScopeId"] as? String, expected.userScopeId)
        XCTAssertEqual(first["budgetScopeId"] as? String, expected.budgetScopeId)

        let defaults = BudgetMateTestFixtures.isolatedDefaults()
        defaults.set(
            CloudSyncStore.currentPendingCloudDeletionSafetyVersion,
            forKey: CloudSyncStore.pendingCloudDeletionSafetyVersionKey
        )
        defaults.set(encoded, forKey: CloudSyncStore.pendingCloudDeletionsKey)
        let restored = CloudSyncStore.loadPendingCloudDeletions(
            from: defaults,
            key: CloudSyncStore.pendingCloudDeletionsKey
        )

        XCTAssertEqual(restored, [expected])
    }

    func testGateCPendingDeletionPreservesExpectedVersionAndMutationID() throws {
        let mutationId = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa0010")!
        let expected = PendingCloudDeletion(
            entity: .settlement,
            recordId: BudgetMateTestFixtures.settlementID,
            userScopeId: BudgetMateTestFixtures.aliceUserID.uuidString,
            budgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            expectedRowVersion: 7,
            mutationId: mutationId
        )
        let defaults = BudgetMateTestFixtures.isolatedDefaults()
        defaults.set(
            CloudSyncStore.currentPendingCloudDeletionSafetyVersion,
            forKey: CloudSyncStore.pendingCloudDeletionSafetyVersionKey
        )
        defaults.set(
            try JSONEncoder().encode([expected]),
            forKey: CloudSyncStore.pendingCloudDeletionsKey
        )

        let restored = CloudSyncStore.loadPendingCloudDeletions(
            from: defaults,
            key: CloudSyncStore.pendingCloudDeletionsKey
        )
        XCTAssertEqual(restored, [expected])
        XCTAssertEqual(restored.first?.expectedRowVersion, 7)
        XCTAssertEqual(restored.first?.mutationId, mutationId)
    }

    func testLegacyDirtyRowsReceiveStableMutationIDsBeforeAnyRPC() {
        let transaction = BudgetMateTestFixtures.expense()
        let settlement = BudgetMateTestFixtures.settlement()
        transaction.needsSync = true
        settlement.needsSync = true

        XCTAssertTrue(
            SupabaseBudgetSyncService.shouldDeferFinancialWrites(
                transactions: [transaction],
                settlements: [settlement]
            )
        )
        XCTAssertTrue(
            SupabaseBudgetSyncService.prepareMutationIDs(
                transactions: [transaction],
                settlements: [settlement]
            )
        )
        let transactionMutationID = transaction.lastMutationId
        let settlementMutationID = settlement.lastMutationId
        XCTAssertNotNil(transactionMutationID)
        XCTAssertNotNil(settlementMutationID)

        XCTAssertFalse(
            SupabaseBudgetSyncService.prepareMutationIDs(
                transactions: [transaction],
                settlements: [settlement]
            )
        )
        XCTAssertEqual(transaction.lastMutationId, transactionMutationID)
        XCTAssertEqual(settlement.lastMutationId, settlementMutationID)
    }

    func testCorruptPendingCloudDeletionDataRestoresAsEmpty() {
        let defaults = BudgetMateTestFixtures.isolatedDefaults()
        defaults.set(
            CloudSyncStore.currentPendingCloudDeletionSafetyVersion,
            forKey: CloudSyncStore.pendingCloudDeletionSafetyVersionKey
        )
        defaults.set(Data("not-json".utf8), forKey: CloudSyncStore.pendingCloudDeletionsKey)

        let restored = CloudSyncStore.loadPendingCloudDeletions(
            from: defaults,
            key: CloudSyncStore.pendingCloudDeletionsKey
        )

        XCTAssertTrue(restored.isEmpty)
    }

    func testLegacyMemberRemovalBatchIsDiscardedBeforeItCanReplay() throws {
        let defaults = BudgetMateTestFixtures.isolatedDefaults()
        defaults.set(
            CloudSyncStore.currentPendingCloudDeletionSafetyVersion,
            forKey: CloudSyncStore.pendingCloudDeletionSafetyVersionKey
        )
        let sharedScope = BudgetMateTestFixtures.sharedBudgetID.uuidString
        let personalScope = BudgetMateTestFixtures.personalBudgetID.uuidString
        let userScope = BudgetMateTestFixtures.aliceUserID.uuidString
        let legacyBatch = [
            PendingCloudDeletion(
                entity: .transaction,
                recordId: BudgetMateTestFixtures.expenseTransactionID,
                userScopeId: userScope,
                budgetScopeId: sharedScope
            ),
            PendingCloudDeletion(
                entity: .member,
                recordId: BudgetMateTestFixtures.bobMemberID,
                userScopeId: userScope,
                budgetScopeId: sharedScope
            ),
            PendingCloudDeletion(
                entity: .membership,
                recordId: BudgetMateTestFixtures.bobUserID,
                userScopeId: userScope,
                budgetScopeId: sharedScope
            ),
            PendingCloudDeletion(
                entity: .transaction,
                recordId: BudgetMateTestFixtures.incomeTransactionID,
                userScopeId: userScope,
                budgetScopeId: personalScope
            )
        ]
        defaults.set(
            try JSONEncoder().encode(legacyBatch),
            forKey: CloudSyncStore.pendingCloudDeletionsKey
        )

        let restored = CloudSyncStore.loadPendingCloudDeletions(
            from: defaults,
            key: CloudSyncStore.pendingCloudDeletionsKey
        )

        XCTAssertEqual(restored, [legacyBatch[3]])
        let persistedData = try XCTUnwrap(
            defaults.data(forKey: CloudSyncStore.pendingCloudDeletionsKey)
        )
        XCTAssertEqual(
            try JSONDecoder().decode([PendingCloudDeletion].self, from: persistedData),
            restored
        )
    }

    func testLegacyMembershipOnlyBatchAlsoBlocksSameScopeReplay() throws {
        let defaults = BudgetMateTestFixtures.isolatedDefaults()
        defaults.set(
            CloudSyncStore.currentPendingCloudDeletionSafetyVersion,
            forKey: CloudSyncStore.pendingCloudDeletionSafetyVersionKey
        )
        let sharedScope = BudgetMateTestFixtures.sharedBudgetID.uuidString
        let userScope = BudgetMateTestFixtures.aliceUserID.uuidString
        let legacyBatch = [
            PendingCloudDeletion(
                entity: .settlement,
                recordId: BudgetMateTestFixtures.settlementID,
                userScopeId: userScope,
                budgetScopeId: sharedScope
            ),
            PendingCloudDeletion(
                entity: .membership,
                recordId: BudgetMateTestFixtures.bobUserID,
                userScopeId: userScope,
                budgetScopeId: sharedScope
            )
        ]
        defaults.set(
            try JSONEncoder().encode(legacyBatch),
            forKey: CloudSyncStore.pendingCloudDeletionsKey
        )

        let restored = CloudSyncStore.loadPendingCloudDeletions(
            from: defaults,
            key: CloudSyncStore.pendingCloudDeletionsKey
        )

        XCTAssertTrue(restored.isEmpty)
    }

    func testPreGuardrailTransactionOnlyPrefixIsDiscardedOnUpgrade() throws {
        let defaults = BudgetMateTestFixtures.isolatedDefaults()
        let legacyTransactionOnlyPrefix = [
            PendingCloudDeletion(
                entity: .transaction,
                recordId: BudgetMateTestFixtures.expenseTransactionID,
                userScopeId: BudgetMateTestFixtures.aliceUserID.uuidString,
                budgetScopeId: BudgetMateTestFixtures.sharedBudgetID.uuidString
            )
        ]
        defaults.set(
            try JSONEncoder().encode(legacyTransactionOnlyPrefix),
            forKey: CloudSyncStore.pendingCloudDeletionsKey
        )

        let restored = CloudSyncStore.loadPendingCloudDeletions(
            from: defaults,
            key: CloudSyncStore.pendingCloudDeletionsKey
        )

        XCTAssertTrue(restored.isEmpty)
        XCTAssertNil(defaults.data(forKey: CloudSyncStore.pendingCloudDeletionsKey))
        XCTAssertEqual(
            defaults.integer(forKey: CloudSyncStore.pendingCloudDeletionSafetyVersionKey),
            CloudSyncStore.currentPendingCloudDeletionSafetyVersion
        )
    }

    func testMoneyServerBridgeRolloutDefaultsOffAndOmitsAdditiveWrites() throws {
        XCTAssertFalse(MoneyServerBridgeRollout.isEnabled)

        let transaction = BudgetMateTestFixtures.equalSplitExpense()
        transaction.amountMinorUnits = 10_000
        transaction.currencyCode = "USD"
        for split in transaction.splits {
            split.amountMinorUnits = 5_000
            split.currencyCode = "USD"
        }
        let transactionRow = CloudTransactionRow(
            transaction: transaction,
            userId: BudgetMateTestFixtures.aliceUserID,
            budgetId: BudgetMateTestFixtures.sharedBudgetID
        )
        let transactionObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(transactionRow)
            ) as? [String: Any]
        )
        XCTAssertNil(transactionObject["amount_minor_units"])
        XCTAssertNil(transactionObject["currency_code"])
        XCTAssertNil(transactionObject["splits_minor_units"])

        var exactSettings = BudgetMateTestFixtures.settings
        exactSettings.categoryBudgetsMinorUnits = [
            TransactionCategory.groceries.rawValue: 40_000,
            TransactionCategory.restaurant.rawValue: 25_000
        ]
        exactSettings.categoryVisibility = [
            TransactionCategory.groceries.rawValue: .visible,
            TransactionCategory.restaurant.rawValue: .visible
        ]
        let settingsRow = CloudBudgetSettingsRow(
            settings: exactSettings,
            userId: BudgetMateTestFixtures.aliceUserID,
            budgetId: BudgetMateTestFixtures.sharedBudgetID
        )
        let settingsObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(settingsRow)
            ) as? [String: Any]
        )
        XCTAssertNil(settingsObject["category_budgets_minor_units"])
        XCTAssertNil(settingsObject["category_visibility"])
    }

    func testGateCConfigurationDefaultsDisabledAndPreservesPendingWrites() {
        let configuration = GateCClientRolloutConfiguration(values: [:])
        XCTAssertEqual(configuration.state, .disabled)
        XCTAssertFalse(configuration.isEnabled)
        XCTAssertFalse(SharedDataSafetyGate.isEnabled(configuration: configuration))
        XCTAssertFalse(MoneyServerBridgeRollout.isEnabled(configuration: configuration))
        XCTAssertTrue(configuration.disabledMessage.localizedCaseInsensitiveContains("temporarily unavailable"))

        let transaction = BudgetMateTestFixtures.expense()
        let settlement = BudgetMateTestFixtures.settlement()
        transaction.needsSync = true
        settlement.needsSync = true

        XCTAssertTrue(
            SupabaseBudgetSyncService.shouldDeferFinancialWrites(
                transactions: [transaction],
                settlements: [settlement],
                gateEnabled: configuration.isEnabled
            )
        )
        XCTAssertTrue(transaction.needsSync)
        XCTAssertTrue(settlement.needsSync)
    }

    func testGateCConfigurationEnablesBothGatesOnlyAfterServerReadiness() {
        let configuration = GateCClientRolloutConfiguration(values: [
            GateCClientRolloutConfiguration.serverReadyKey: "YES",
            GateCClientRolloutConfiguration.sharedDataSafetyKey: "YES",
            GateCClientRolloutConfiguration.moneyServerBridgeKey: "YES"
        ])

        XCTAssertEqual(configuration.state, .enabled)
        XCTAssertTrue(configuration.isEnabled)
        XCTAssertTrue(SharedDataSafetyGate.isEnabled(configuration: configuration))
        XCTAssertTrue(MoneyServerBridgeRollout.isEnabled(configuration: configuration))
        XCTAssertFalse(
            SupabaseBudgetSyncService.shouldDeferFinancialWrites(
                transactions: [BudgetMateTestFixtures.expense()],
                settlements: [],
                gateEnabled: configuration.isEnabled
            )
        )
    }

    func testGateCConfigurationFailsClosedForInconsistentOrInvalidConfiguration() {
        let inconsistent = GateCClientRolloutConfiguration(values: [
            GateCClientRolloutConfiguration.serverReadyKey: "YES",
            GateCClientRolloutConfiguration.sharedDataSafetyKey: "YES",
            GateCClientRolloutConfiguration.moneyServerBridgeKey: "NO"
        ])
        let serverNotReady = GateCClientRolloutConfiguration(values: [
            GateCClientRolloutConfiguration.serverReadyKey: "NO",
            GateCClientRolloutConfiguration.sharedDataSafetyKey: "YES",
            GateCClientRolloutConfiguration.moneyServerBridgeKey: "YES"
        ])
        let invalid = GateCClientRolloutConfiguration(values: [
            GateCClientRolloutConfiguration.serverReadyKey: "YES",
            GateCClientRolloutConfiguration.sharedDataSafetyKey: "true",
            GateCClientRolloutConfiguration.moneyServerBridgeKey: "YES"
        ])

        for configuration in [inconsistent, serverNotReady, invalid] {
            XCTAssertEqual(configuration.state, .inconsistent)
            XCTAssertFalse(configuration.isEnabled)
            XCTAssertFalse(SharedDataSafetyGate.isEnabled(configuration: configuration))
            XCTAssertFalse(MoneyServerBridgeRollout.isEnabled(configuration: configuration))
            XCTAssertTrue(configuration.disabledMessage.localizedCaseInsensitiveContains("configuration is incomplete"))
        }
    }

    func testSharedDataSafetyRPCSelectionUsesTheDedicatedMutationEndpoints() {
        XCTAssertEqual(SharedDataSafetyMutationRPC.transaction.name, "mutate_budget_transaction")
        XCTAssertEqual(SharedDataSafetyMutationRPC.settlement.name, "mutate_budget_settlement")
    }

    func testEnabledMoneyServerBridgeDualFieldsRoundTripWithoutChangingLegacyValues() throws {
        let transaction = BudgetMateTestFixtures.equalSplitExpense()
        transaction.amountMinorUnits = 10_000
        transaction.currencyCode = "USD"
        for split in transaction.splits {
            split.amountMinorUnits = 5_000
            split.currencyCode = "USD"
        }
        let row = CloudTransactionRow(
            transaction: transaction,
            userId: BudgetMateTestFixtures.aliceUserID,
            budgetId: BudgetMateTestFixtures.sharedBudgetID,
            rolloutEnabled: true
        )
        let data = try JSONEncoder().encode(row)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual((object["amount_minor_units"] as? NSNumber)?.int64Value, 10_000)
        XCTAssertEqual(object["currency_code"] as? String, "USD")
        XCTAssertEqual((object["splits_minor_units"] as? [[String: Any]])?.count, 2)

        let decoded = try JSONDecoder().decode(CloudTransactionRow.self, from: data)
        try decoded.validateDates(rolloutEnabled: true)
        let local = decoded.makeTransaction(
            ownerUserId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
            rolloutEnabled: true
        )
        XCTAssertEqual(local.amount, transaction.amount)
        XCTAssertEqual(local.amountMinorUnits, 10_000)
        XCTAssertEqual(local.currencyCode, "USD")

        var settings = BudgetMateTestFixtures.settings
        settings.categoryBudgetsMinorUnits = [
            TransactionCategory.groceries.rawValue: 40_000,
            TransactionCategory.restaurant.rawValue: 25_000
        ]
        settings.categoryVisibility = [
            TransactionCategory.groceries.rawValue: .visible,
            TransactionCategory.restaurant.rawValue: .visible
        ]
        let settingsRow = CloudBudgetSettingsRow(
            settings: settings,
            userId: BudgetMateTestFixtures.aliceUserID,
            budgetId: BudgetMateTestFixtures.sharedBudgetID,
            rolloutEnabled: true
        )
        let settingsData = try JSONEncoder().encode(settingsRow)
        let decodedSettings = try JSONDecoder().decode(
            CloudBudgetSettingsRow.self,
            from: settingsData
        )
        try decodedSettings.validateMoneyContract(rolloutEnabled: true)
        XCTAssertEqual(
            decodedSettings.makeSettings(
                rolloutEnabled: true
            ).categoryBudgetsMinorUnits,
            settings.categoryBudgetsMinorUnits
        )

        let settlement = BudgetMateTestFixtures.settlement(amount: 20)
        settlement.amountMinorUnits = 2_000
        settlement.currencyCode = "USD"
        let settlementRow = CloudSettlementRow(
            settlement: settlement,
            userId: BudgetMateTestFixtures.aliceUserID,
            budgetId: BudgetMateTestFixtures.sharedBudgetID,
            rolloutEnabled: true
        )
        let settlementData = try JSONEncoder().encode(settlementRow)
        let decodedSettlement = try JSONDecoder().decode(
            CloudSettlementRow.self,
            from: settlementData
        )
        try decodedSettlement.validateDate(rolloutEnabled: true)
        XCTAssertEqual(
            decodedSettlement.makeSettlement(
                ownerUserId: BudgetMateTestFixtures.sharedBudgetID.uuidString,
                rolloutEnabled: true
            ).amountMinorUnits,
            2_000
        )
    }

    func testEnabledMoneyServerBridgeRejectsContradictoryExactFields() throws {
        let transaction = BudgetMateTestFixtures.expense(amount: 12.34)
        transaction.amountMinorUnits = 1_234
        transaction.currencyCode = "USD"
        let row = CloudTransactionRow(
            transaction: transaction,
            userId: BudgetMateTestFixtures.aliceUserID,
            budgetId: BudgetMateTestFixtures.sharedBudgetID,
            rolloutEnabled: true
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(row)
            ) as? [String: Any]
        )
        object["amount_minor_units"] = 999
        let contradictory = try JSONDecoder().decode(
            CloudTransactionRow.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertThrowsError(
            try contradictory.validateDates(rolloutEnabled: true)
        ) { error in
            guard let syncError = error as? SupabaseBudgetSyncError,
                  case .invalidCloudMoneyContract = syncError else {
                return XCTFail("Expected invalidCloudMoneyContract, received \(error)")
            }
        }
    }
}

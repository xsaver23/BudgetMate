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
}

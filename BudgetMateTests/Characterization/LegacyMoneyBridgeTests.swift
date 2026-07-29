import Foundation
import SwiftData
import XCTest
@testable import BudgetMate

@MainActor
final class LegacyMoneyBridgeTests: XCTestCase {
    func testV1FileBackfillViaControllerPreservesLegacyDataAndReopens() throws {
        let location = try makeStoreLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        try LegacyUnversionedStoreFixture.create(at: location.storeURL)

        do {
            let persistence = try PersistenceController(
                storeURL: location.storeURL,
                verifiedCurrencySource: StaticVerifiedCurrencySource(currencyCode: "CAD")
            )
            let context = persistence.container.mainContext
            let transactions = try context.fetch(FetchDescriptor<Transaction>())
            let splits = try context.fetch(FetchDescriptor<TransactionSplit>())
            let settlements = try context.fetch(FetchDescriptor<Settlement>())

            XCTAssertEqual(transactions.count, 2)
            XCTAssertEqual(splits.count, 3)
            XCTAssertEqual(settlements.count, 1)

            let transactionByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
            let expense = try XCTUnwrap(transactionByID[LegacyUnversionedStoreFixture.expenseID])
            let income = try XCTUnwrap(transactionByID[LegacyUnversionedStoreFixture.incomeID])
            XCTAssertEqual(expense.amount, 123.45, accuracy: 0.0001)
            XCTAssertEqual(expense.amountMinorUnits, 12345)
            XCTAssertEqual(expense.currencyCode, "CAD")
            XCTAssertEqual(expense.date, LegacyUnversionedStoreFixture.expenseDate)
            XCTAssertEqual(
                Set(expense.splits.map(\.id)),
                [LegacyUnversionedStoreFixture.firstSplitID, LegacyUnversionedStoreFixture.secondSplitID]
            )
            XCTAssertEqual(income.amount, 2_500, accuracy: 0.0001)
            XCTAssertEqual(income.amountMinorUnits, 250_000)
            XCTAssertEqual(income.currencyCode, "CAD")
            XCTAssertEqual(income.date, LegacyUnversionedStoreFixture.incomeDate)

            let splitByID = Dictionary(uniqueKeysWithValues: splits.map { ($0.id, $0) })
            XCTAssertEqual(splitByID[LegacyUnversionedStoreFixture.firstSplitID]?.amountMinorUnits, 6172)
            XCTAssertEqual(splitByID[LegacyUnversionedStoreFixture.secondSplitID]?.amountMinorUnits, 6173)
            XCTAssertEqual(splitByID[LegacyUnversionedStoreFixture.orphanSplitID]?.amountMinorUnits, 999)
            XCTAssertNil(splitByID[LegacyUnversionedStoreFixture.orphanSplitID]?.transaction)
            XCTAssertEqual(
                splits.compactMap(\.amountMinorUnits).reduce(0, +),
                13_344
            )

            let settlement = try XCTUnwrap(settlements.first)
            XCTAssertEqual(settlement.id, LegacyUnversionedStoreFixture.settlementID)
            XCTAssertEqual(settlement.amount, 25.50, accuracy: 0.0001)
            XCTAssertEqual(settlement.amountMinorUnits, 2550)
            XCTAssertEqual(settlement.currencyCode, "CAD")
            XCTAssertEqual(settlement.date, LegacyUnversionedStoreFixture.settlementDate)
        }

        do {
            let reopened = try PersistenceController(
                storeURL: location.storeURL,
                verifiedCurrencySource: StaticVerifiedCurrencySource(currencyCode: "CAD")
            )
            let transactions = try reopened.container.mainContext.fetch(FetchDescriptor<Transaction>())
            let splits = try reopened.container.mainContext.fetch(FetchDescriptor<TransactionSplit>())
            let settlements = try reopened.container.mainContext.fetch(FetchDescriptor<Settlement>())
            XCTAssertEqual(transactions.count, 2)
            XCTAssertEqual(splits.count, 3)
            XCTAssertEqual(settlements.count, 1)
            XCTAssertEqual(
                transactions.first(where: { $0.id == LegacyUnversionedStoreFixture.expenseID })?.amountMinorUnits,
                12_345
            )
            XCTAssertEqual(
                splits.first(where: { $0.id == LegacyUnversionedStoreFixture.secondSplitID })?.amountMinorUnits,
                6173
            )
            XCTAssertEqual(settlements.first?.amountMinorUnits, 2550)
        }

        XCTAssertNil(
            try LegacyMoneyAnomalyStore.load(
                at: LegacyMoneyAnomalyStore.storeURL(forStoreURL: location.storeURL)
            )
        )
    }

    func testMissingCurrencyLeavesExactFieldsNilButAllowsRecoveryReopen() throws {
        let location = try makeStoreLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        try LegacyUnversionedStoreFixture.create(at: location.storeURL)
        let reportURL = LegacyMoneyAnomalyStore.storeURL(forStoreURL: location.storeURL)

        do {
            let persistence = try PersistenceController(storeURL: location.storeURL)
            let context = persistence.container.mainContext
            let transactions = try context.fetch(FetchDescriptor<Transaction>())
            XCTAssertTrue(transactions.allSatisfy { $0.amountMinorUnits == nil && $0.currencyCode == nil })
        }

        let report = try XCTUnwrap(LegacyMoneyAnomalyStore.load(at: reportURL))
        XCTAssertTrue(report.isBlocking)
        XCTAssertEqual(report.anomalies.count, 6)
        let reportData = try JSONEncoder().encode(report)
        let reportText = String(decoding: reportData, as: UTF8.self)
        XCTAssertFalse(reportText.contains("123.45"))
        XCTAssertFalse(reportText.contains("2500"))

        let reopened = try PersistenceController(storeURL: location.storeURL)
        let transactions = try reopened.container.mainContext.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(transactions.count, 2)
        XCTAssertTrue(transactions.allSatisfy { $0.amountMinorUnits == nil })
    }

    func testExistingExactFieldsAreCheckedAgainstDeterministicLegacyConversion() throws {
        let persistence = try PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let valid = Transaction(
            title: "Valid exact pair",
            amount: 12.34,
            amountMinorUnits: 1234,
            currencyCode: "USD",
            type: .expense,
            category: .food,
            createdByMemberId: UUID()
        )
        let contradictory = Transaction(
            title: "Contradictory exact pair",
            amount: 12.34,
            amountMinorUnits: 1235,
            currencyCode: "USD",
            type: .expense,
            category: .food,
            createdByMemberId: UUID()
        )
        context.insert(valid)
        context.insert(contradictory)
        try context.save()

        let result = try LegacyMoneyBackfillService().backfill(context: context)
        XCTAssertFalse(result.isExactMoneyCutoverAllowed)
        XCTAssertEqual(
            result.anomalyReport.anomalies.filter { $0.reason == .contradictoryExactFields }.count,
            1
        )
        XCTAssertEqual(valid.amountMinorUnits, 1234)
        XCTAssertEqual(contradictory.amountMinorUnits, 1235)
    }

    func testLegacySettingsBlobClassifiesMarkersMonthsAndWritesV2ContractMarker() throws {
        let legacyData = Data(
            #"""
            {
              "monthlyBudget": 0,
              "currencySymbol": "$",
              "appearance": "system",
              "categoryBudgets": {
                "__hiddenCategory__restaurant": 999999,
                "food": 12.34,
                "__monthBudget__:2026-07:food": 5.67
              },
              "categoryEmojis": {}
            }
            """#.utf8
        )
        let legacySettings = try JSONDecoder().decode(BudgetSettings.self, from: legacyData)
        let migrated = LegacyBudgetSettingsMigrator.migrate(
            legacySettings,
            currencySource: StaticVerifiedCurrencySource(currencyCode: "USD")
        )

        XCTAssertFalse(migrated.anomalyReport.isBlocking)
        XCTAssertEqual(migrated.settings.categoryBudgetsMinorUnits["food"], 1234)
        XCTAssertEqual(
            migrated.settings.categoryBudgetsMinorUnits[
                BudgetSettings.monthBudgetKey(monthKey: "2026-07", categoryRawValue: "food")
            ],
            567
        )
        XCTAssertNil(migrated.settings.categoryBudgetsMinorUnits["__hiddenCategory__restaurant"])
        XCTAssertEqual(migrated.settings.categoryVisibility["restaurant"], .hidden)
        XCTAssertEqual(migrated.settings.categoryVisibility["food"], .visible)
        XCTAssertEqual(migrated.settings.categoryBudgets["__hiddenCategory__restaurant"], 999999)

        let encoded = try JSONEncoder().encode(migrated.settings)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual((object["settingsContractVersion"] as? NSNumber)?.intValue, 2)
        XCTAssertNotNil(object["categoryBudgets"])
        XCTAssertNotNil(object["categoryBudgetsMinorUnits"])
        XCTAssertNotNil(object["categoryVisibility"])
    }

    func testLegacySettingsMigratorAuditsOrphanExactKeysAndKeepsMarkersAsVisibilityOnly() throws {
        let hiddenMarker = TransactionCategory.hiddenMarkerKey(for: .restaurant)
        var settings = BudgetSettings(
            monthlyBudget: 0,
            currencyCode: "USD",
            categoryBudgets: [
                "food": 12.34,
                hiddenMarker: 999
            ],
            categoryBudgetsMinorUnits: [
                "food": 1234,
                "orphan": 77
            ]
        )
        settings.categoryBudgetsMinorUnits[hiddenMarker] = 999_999

        let migrated = LegacyBudgetSettingsMigrator.migrate(
            settings,
            currencySource: StaticVerifiedCurrencySource(currencyCode: "USD")
        )

        XCTAssertFalse(migrated.isExactMoneyCutoverAllowed)
        XCTAssertTrue(
            migrated.anomalyReport.anomalies.contains {
                $0.identifier == "orphan" && $0.reason == .incompleteExactFields
            }
        )
        XCTAssertEqual(migrated.settings.categoryBudgetsMinorUnits["orphan"], 77)
        XCTAssertNil(migrated.settings.categoryBudgetsMinorUnits[hiddenMarker])
        XCTAssertEqual(migrated.settings.categoryVisibility["restaurant"], .hidden)
    }

    func testSettingsStoreCategoryVisibilityTracksUpsertRenameAndRemove() throws {
        let suiteName = "BudgetMateVisibility-(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reportURL = try makeTemporaryURL(filename: "visibility-anomalies.json")
        defer { try? FileManager.default.removeItem(at: reportURL.deletingLastPathComponent()) }
        defaults.set(
            Data(
                #"{"monthlyBudget":0,"currencyCode":"USD","categoryBudgets":{"__hiddenCategory__restaurant":1}}"#.utf8
            ),
            forKey: "budgetmate.settings.local"
        )

        let store = SettingsStore(
            userDefaults: defaults,
            verifiedCurrencySource: StaticVerifiedCurrencySource(currencyCode: "USD"),
            anomalyReportURL: reportURL
        )
        XCTAssertEqual(store.settings.categoryVisibility["restaurant"], .hidden)
        XCTAssertTrue(store.hiddenExpenseCategoryRawValues().contains("restaurant"))

        store.upsertCategory(.restaurant, budgetAmount: 20)
        XCTAssertEqual(store.settings.categoryVisibility["restaurant"], .visible)
        XCTAssertFalse(store.hiddenExpenseCategoryRawValues().contains("restaurant"))

        store.removeCategory(.restaurant)
        XCTAssertEqual(store.settings.categoryVisibility["restaurant"], .hidden)
        XCTAssertTrue(store.hiddenExpenseCategoryRawValues().contains("restaurant"))

        let custom = TransactionCategory("custom")
        store.renameCategory(from: .restaurant, to: custom)
        XCTAssertEqual(store.settings.categoryVisibility["restaurant"], .hidden)
        XCTAssertEqual(store.settings.categoryVisibility[custom.rawValue], .visible)
        XCTAssertFalse(store.hiddenExpenseCategoryRawValues().contains(custom.rawValue))

        store.removeCategory(custom)
        XCTAssertNil(store.settings.categoryVisibility[custom.rawValue])
        XCTAssertFalse(store.hiddenExpenseCategoryRawValues().contains(custom.rawValue))
    }

    func testSettingsCurrencySourceMismatchBlocksWithoutScalingUnderWrongCurrency() throws {
        let settings = BudgetSettings(
            monthlyBudget: 0,
            currencyCode: "JPY",
            categoryBudgets: ["food": 1.23]
        )

        let migrated = LegacyBudgetSettingsMigrator.migrate(
            settings,
            currencySource: StaticVerifiedCurrencySource(currencyCode: "USD")
        )

        XCTAssertFalse(migrated.isExactMoneyCutoverAllowed)
        XCTAssertTrue(
            migrated.anomalyReport.anomalies.contains {
                $0.reason == .currencyMismatch && $0.field == "currencyCode"
            }
        )
        XCTAssertNil(migrated.settings.categoryBudgetsMinorUnits["food"])
    }

    func testLegacyMonthlyBudgetFallbackUsesZeroFractionCurrency() throws {
        let legacyData = Data(
            #"{"monthlyBudget":250,"currencySymbol":"¥","categoryBudgets":{}}"#.utf8
        )
        let decoded = try JSONDecoder().decode(BudgetSettings.self, from: legacyData)
        XCTAssertEqual(decoded.currencyCode, "JPY")
        XCTAssertEqual(decoded.categoryBudgets[TransactionCategory.other.rawValue], 250)

        let migrated = LegacyBudgetSettingsMigrator.migrate(
            decoded,
            currencySource: StaticVerifiedCurrencySource(currencyCode: "JPY")
        )
        XCTAssertEqual(migrated.settings.categoryBudgetsMinorUnits[TransactionCategory.other.rawValue], 250)
        XCTAssertFalse(migrated.anomalyReport.isBlocking)
    }

    func testSettingsStoreRoundTripsV1BlobAndPersistsV2ExactPayload() throws {
        let suiteName = "BudgetMateLegacyMoney-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reportURL = try makeTemporaryURL(filename: "settings-anomalies.json")
        defer { try? FileManager.default.removeItem(at: reportURL.deletingLastPathComponent()) }
        let legacyData = Data(
            #"{"monthlyBudget":0,"currencyCode":"CAD","categoryBudgets":{"food":12.34}}"#.utf8
        )
        defaults.set(legacyData, forKey: "budgetmate.settings.local")

        let first = SettingsStore(
            userDefaults: defaults,
            verifiedCurrencySource: StaticVerifiedCurrencySource(currencyCode: "CAD"),
            anomalyReportURL: reportURL
        )
        XCTAssertEqual(first.settings.categoryBudgets["food"], 12.34)
        XCTAssertEqual(first.settings.categoryBudgetsMinorUnits["food"], 1234)
        XCTAssertEqual(first.lastMoneyMigrationAnomalyReport.anomalies, [])

        let persisted = try XCTUnwrap(defaults.data(forKey: "budgetmate.settings.local"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: persisted) as? [String: Any])
        XCTAssertEqual((object["settingsContractVersion"] as? NSNumber)?.intValue, 2)

        let reopened = SettingsStore(
            userDefaults: defaults,
            verifiedCurrencySource: StaticVerifiedCurrencySource(currencyCode: "CAD"),
            anomalyReportURL: reportURL
        )
        XCTAssertEqual(reopened.settings.categoryBudgetsMinorUnits["food"], 1234)
        XCTAssertEqual(reopened.settings.categoryBudgets["food"], 12.34)
        XCTAssertNil(try LegacyMoneyAnomalyStore.load(at: reportURL))
    }

    func testMalformedNonfiniteOutOfRangeAndUnsupportedCurrencySettingsBlockSafely() throws {
        let settings = BudgetSettings(
            monthlyBudget: 0,
            currencyCode: "USD",
            categoryBudgets: [
                "nan": .nan,
                "huge": .greatestFiniteMagnitude
            ]
        )
        let anomalies = LegacyBudgetSettingsMigrator.migrate(
            settings,
            currencySource: StaticVerifiedCurrencySource(currencyCode: "USD")
        ).anomalyReport.anomalies
        XCTAssertTrue(anomalies.contains { $0.reason == .nonFiniteLegacyValue })
        XCTAssertTrue(anomalies.contains { $0.reason == .outOfRange })

        let unsupported = LegacyBudgetSettingsMigrator.migrate(
            settings,
            currencySource: StaticVerifiedCurrencySource(currencyCode: "KWD")
        )
        XCTAssertFalse(CurrencyMetadata.isSupported("KWD"))
        XCTAssertTrue(unsupported.anomalyReport.anomalies.allSatisfy { $0.reason == .unsupportedCurrency })
        XCTAssertTrue(unsupported.settings.categoryBudgetsMinorUnits.isEmpty)

        let suiteName = "BudgetMateMalformed-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: "budgetmate.settings.local")
        let reportURL = try makeTemporaryURL(filename: "malformed-settings.json")
        defer { try? FileManager.default.removeItem(at: reportURL.deletingLastPathComponent()) }
        let store = SettingsStore(userDefaults: defaults, anomalyReportURL: reportURL)
        XCTAssertEqual(store.lastMoneyMigrationAnomalyReport.anomalies.first?.reason, .malformedSettingsBlob)
        XCTAssertEqual(try LegacyMoneyAnomalyStore.load(at: reportURL)?.anomalies.count, 1)
    }

    func testConverterCoversZeroTwoAndThreeFractionFixturesWithAwayFromZeroTies() throws {
        let jpy = try CurrencyMetadata(code: "JPY")
        XCTAssertEqual(try minorUnits(LegacyDoubleMoneyConverter.convert(1.5, metadata: jpy)), 2)
        XCTAssertEqual(try minorUnits(LegacyDoubleMoneyConverter.convert(-1.5, metadata: jpy)), -2)

        let usd = try CurrencyMetadata(code: "USD")
        XCTAssertEqual(try minorUnits(LegacyDoubleMoneyConverter.convert(1.005, metadata: usd)), 101)
        XCTAssertEqual(try minorUnits(LegacyDoubleMoneyConverter.convert(-1.005, metadata: usd)), -101)

        let threeDigits = try XCTUnwrap(ValidatedLegacyFractionDigits(3))
        XCTAssertEqual(
            try minorUnits(
                LegacyDoubleMoneyConverter.convert(1.2345, fractionDigits: threeDigits)
            ),
            1235
        )
        XCTAssertEqual(
            try minorUnits(
                LegacyDoubleMoneyConverter.convert(-1.2345, fractionDigits: threeDigits)
            ),
            -1235
        )
        XCTAssertEqual(
            LegacyDoubleMoneyConverter.convert(.nan, metadata: usd),
            .failure(.nonFinite)
        )
        XCTAssertEqual(
            LegacyDoubleMoneyConverter.convert(.greatestFiniteMagnitude, metadata: usd),
            .failure(.outOfRange)
        )
    }

    func testThreeFractionSettingsPayloadRoundTripsThroughValidatedSeam() throws {
        let threeDigits = try XCTUnwrap(ValidatedLegacyFractionDigits(3))
        let exact = try minorUnits(
            LegacyDoubleMoneyConverter.convert(1.2345, fractionDigits: threeDigits)
        )
        let settings = BudgetSettings(
            monthlyBudget: 0,
            currencyCode: "USD",
            categoryBudgets: ["fuel": 1.2345],
            categoryBudgetsMinorUnits: ["fuel": exact],
            categoryVisibility: ["fuel": .visible]
        )
        let reopened = try JSONDecoder().decode(
            BudgetSettings.self,
            from: JSONEncoder().encode(settings)
        )
        XCTAssertEqual(try XCTUnwrap(reopened.categoryBudgets["fuel"]), 1.2345, accuracy: 0.00001)
        XCTAssertEqual(reopened.categoryBudgetsMinorUnits["fuel"], 1235)
        XCTAssertEqual(reopened.categoryVisibility["fuel"], .visible)
    }

    func testAnomalyReportIsAtomicCompleteProtectedAndSanitized() throws {
        let reportURL = try makeTemporaryURL(filename: "anomaly-report.json")
        defer { try? FileManager.default.removeItem(at: reportURL.deletingLastPathComponent()) }
        let report = LegacyMoneyAnomalyReport(anomalies: [
            LegacyMoneyMigrationAnomaly(
                entity: "transaction",
                identifier: "opaque-id",
                field: "amount",
                reason: .outOfRange
            )
        ])

        try LegacyMoneyAnomalyStore.save(report, at: reportURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: reportURL.path)
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(protection, .complete)
        }
        XCTAssertEqual(try LegacyMoneyAnomalyStore.load(at: reportURL), report)
        XCTAssertFalse(String(decoding: try Data(contentsOf: reportURL), as: UTF8.self).contains("123.45"))

        try LegacyMoneyAnomalyStore.save(LegacyMoneyAnomalyReport(), at: reportURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path))
    }

    private func minorUnits(
        _ result: Result<Int64, LegacyMoneyConversionError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Int64 {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            XCTFail("Unexpected conversion failure: \(error)", file: file, line: line)
            throw error
        }
    }

    private func makeStoreLocation() throws -> (directory: URL, storeURL: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BudgetMateLegacyMoney-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return (directory, directory.appendingPathComponent("BudgetMate.store"))
    }

    private func makeTemporaryURL(filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BudgetMateLegacyMoneyReport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory.appendingPathComponent(filename)
    }

}

import Foundation
import SwiftData

/// The household currency used by a backfill must come from an authority that
/// has already verified it. The bridge never derives one from a symbol or a
/// local default.
protocol VerifiedCurrencySource: Sendable {
    var verifiedCurrencyCode: String? { get }
}

struct StaticVerifiedCurrencySource: VerifiedCurrencySource, Equatable, Sendable {
    let verifiedCurrencyCode: String?

    init(currencyCode: String?) {
        verifiedCurrencyCode = currencyCode
    }
}

enum LegacyMoneyMigrationAnomalyReason: String, Codable, Equatable, Sendable {
    case currencyNotEstablished
    case unsupportedCurrency
    case nonFiniteLegacyValue
    case malformedLegacyDecimal
    case outOfRange
    case incompleteExactFields
    case contradictoryExactFields
    case currencyMismatch
    case malformedSettingsKey
    case malformedSettingsBlob
}

struct LegacyMoneyMigrationAnomaly: Codable, Equatable, Sendable {
    let entity: String
    let identifier: String
    let field: String
    let reason: LegacyMoneyMigrationAnomalyReason
}

struct LegacyMoneyAnomalyReport: Codable, Equatable, Sendable {
    var anomalies: [LegacyMoneyMigrationAnomaly]

    init(anomalies: [LegacyMoneyMigrationAnomaly] = []) {
        self.anomalies = anomalies
    }

    var isBlocking: Bool { !anomalies.isEmpty }

    mutating func append(
        entity: String,
        identifier: String,
        field: String,
        reason: LegacyMoneyMigrationAnomalyReason
    ) {
        anomalies.append(
            LegacyMoneyMigrationAnomaly(
                entity: entity,
                identifier: identifier,
                field: field,
                reason: reason
            )
        )
    }
}

struct LegacyMoneyBackfillResult: Equatable, Sendable {
    let convertedTransactionCount: Int
    let convertedSplitCount: Int
    let convertedSettlementCount: Int
    let anomalyReport: LegacyMoneyAnomalyReport

    var isExactMoneyCutoverAllowed: Bool {
        !anomalyReport.isBlocking
    }
}

enum LegacyMoneyConversionError: Error, Equatable, Sendable {
    case nonFinite
    case malformedDecimal
    case outOfRange
}

struct ValidatedLegacyFractionDigits: Equatable, Sendable {
    let value: Int

    init?(_ value: Int) {
        guard (0...18).contains(value) else { return nil }
        self.value = value
    }
}

/// Converts a legacy Double exactly once through its shortest round-trip
/// decimal spelling. All scaling and rounding after that point use Decimal;
/// no new binary floating-point arithmetic is introduced.
enum LegacyDoubleMoneyConverter {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let minimumMinorUnits = "-9223372036854775808"
    private static let maximumMinorUnits = "9223372036854775807"

    static func convert(
        _ legacyValue: Double,
        metadata: CurrencyMetadata
    ) -> Result<Int64, LegacyMoneyConversionError> {
        guard let fractionDigits = ValidatedLegacyFractionDigits(metadata.fractionDigits) else {
            return .failure(.outOfRange)
        }
        return convert(legacyValue, fractionDigits: fractionDigits)
    }

    /// Test seam for currencies not selectable in this app. Production
    /// callers must use the metadata overload above.
    static func convert(
        _ legacyValue: Double,
        fractionDigits: ValidatedLegacyFractionDigits
    ) -> Result<Int64, LegacyMoneyConversionError> {
        guard legacyValue.isFinite else { return .failure(.nonFinite) }

        let roundTripDecimal = String(legacyValue)
        guard var decimal = Decimal(
            string: roundTripDecimal,
            locale: posixLocale
        ) else {
            return .failure(.outOfRange)
        }

        var scale = Decimal(1)
        var ten = Decimal(10)
        for _ in 0..<fractionDigits.value {
            var scaled = Decimal()
            guard NSDecimalMultiply(&scaled, &scale, &ten, .plain) == .noError else {
                return .failure(.outOfRange)
            }
            scale = scaled
        }

        var scaledDecimal = Decimal()
        guard NSDecimalMultiply(&scaledDecimal, &decimal, &scale, .plain) == .noError,
              !NSDecimalIsNotANumber(&scaledDecimal) else {
            return .failure(.outOfRange)
        }

        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaledDecimal, 0, .plain)

        guard var minimum = Decimal(
            string: minimumMinorUnits,
            locale: posixLocale
        ), var maximum = Decimal(
            string: maximumMinorUnits,
            locale: posixLocale
        ) else {
            return .failure(.outOfRange)
        }
        guard NSDecimalCompare(&rounded, &minimum) != .orderedAscending,
              NSDecimalCompare(&rounded, &maximum) != .orderedDescending else {
            return .failure(.outOfRange)
        }

        return .success(NSDecimalNumber(decimal: rounded).int64Value)
    }
}

/// Backfills V2 record fields after SwiftData has performed the one schema
/// transition. It is intentionally injectable so an unknown household
/// currency leaves exact fields nil and records a blocking anomaly.
struct LegacyMoneyBackfillService {
    private let currencySource: any VerifiedCurrencySource

    init(currencySource: (any VerifiedCurrencySource)? = nil) {
        self.currencySource = currencySource ?? StaticVerifiedCurrencySource(currencyCode: nil)
    }

    func backfill(context: ModelContext) throws -> LegacyMoneyBackfillResult {
        var report = LegacyMoneyAnomalyReport()
        var convertedTransactions = 0
        var convertedSplits = 0
        var convertedSettlements = 0
        var changed = false

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        for transaction in transactions {
            let action = fill(
                legacyValue: transaction.amount,
                minorUnits: transaction.amountMinorUnits,
                currencyCode: transaction.currencyCode,
                entity: "transaction",
                identifier: transaction.id.uuidString,
                field: "amount",
                report: &report
            ) { minorUnits, currencyCode in
                transaction.amountMinorUnits = minorUnits
                transaction.currencyCode = currencyCode
            }
            changed = changed || action.didChange
            if action.didConvert { convertedTransactions += 1 }
        }

        let splits = try context.fetch(FetchDescriptor<TransactionSplit>())
        for split in splits {
            let action = fill(
                legacyValue: split.amount,
                minorUnits: split.amountMinorUnits,
                currencyCode: split.currencyCode,
                entity: "transactionSplit",
                identifier: split.id.uuidString,
                field: "amount",
                report: &report
            ) { minorUnits, currencyCode in
                split.amountMinorUnits = minorUnits
                split.currencyCode = currencyCode
            }
            changed = changed || action.didChange
            if action.didConvert { convertedSplits += 1 }
        }

        let settlements = try context.fetch(FetchDescriptor<Settlement>())
        for settlement in settlements {
            let action = fill(
                legacyValue: settlement.amount,
                minorUnits: settlement.amountMinorUnits,
                currencyCode: settlement.currencyCode,
                entity: "settlement",
                identifier: settlement.id.uuidString,
                field: "amount",
                report: &report
            ) { minorUnits, currencyCode in
                settlement.amountMinorUnits = minorUnits
                settlement.currencyCode = currencyCode
            }
            changed = changed || action.didChange
            if action.didConvert { convertedSettlements += 1 }
        }

        if changed {
            try context.save()
        }

        return LegacyMoneyBackfillResult(
            convertedTransactionCount: convertedTransactions,
            convertedSplitCount: convertedSplits,
            convertedSettlementCount: convertedSettlements,
            anomalyReport: report
        )
    }

    private struct FieldAction {
        let didChange: Bool
        let didConvert: Bool
    }

    private func fill(
        legacyValue: Double,
        minorUnits: Int64?,
        currencyCode: String?,
        entity: String,
        identifier: String,
        field: String,
        report: inout LegacyMoneyAnomalyReport,
        write: (Int64, String) -> Void
    ) -> FieldAction {
        switch (minorUnits, currencyCode) {
        case let (minorUnits?, currencyCode?):
            guard let metadata = try? CurrencyMetadata(code: currencyCode) else {
                report.append(
                    entity: entity,
                    identifier: identifier,
                    field: field,
                    reason: .unsupportedCurrency
                )
                return FieldAction(didChange: false, didConvert: false)
            }
            switch LegacyDoubleMoneyConverter.convert(legacyValue, metadata: metadata) {
            case .success(let reproducibleMinorUnits) where reproducibleMinorUnits == minorUnits:
                if currencyCode != metadata.code {
                    write(minorUnits, metadata.code)
                    return FieldAction(didChange: true, didConvert: false)
                }
                return FieldAction(didChange: false, didConvert: false)
            case .success:
                report.append(
                    entity: entity,
                    identifier: identifier,
                    field: field,
                    reason: .contradictoryExactFields
                )
                return FieldAction(didChange: false, didConvert: false)
            case .failure(let error):
                report.append(
                    entity: entity,
                    identifier: identifier,
                    field: field,
                    reason: Self.reason(for: error)
                )
                return FieldAction(didChange: false, didConvert: false)
            }

        case (.some, nil), (nil, .some):
            report.append(
                entity: entity,
                identifier: identifier,
                field: field,
                reason: .incompleteExactFields
            )
            return FieldAction(didChange: false, didConvert: false)

        case (nil, nil):
            guard let metadata = verifiedMetadata(report: &report, entity: entity, identifier: identifier, field: field) else {
                return FieldAction(didChange: false, didConvert: false)
            }
            switch LegacyDoubleMoneyConverter.convert(legacyValue, metadata: metadata) {
            case .success(let convertedMinorUnits):
                write(convertedMinorUnits, metadata.code)
                return FieldAction(didChange: true, didConvert: true)
            case .failure(let error):
                report.append(
                    entity: entity,
                    identifier: identifier,
                    field: field,
                    reason: Self.reason(for: error)
                )
                return FieldAction(didChange: false, didConvert: false)
            }
        }
    }

    private func verifiedMetadata(
        report: inout LegacyMoneyAnomalyReport,
        entity: String,
        identifier: String,
        field: String
    ) -> CurrencyMetadata? {
        guard let code = currencySource.verifiedCurrencyCode else {
            report.append(
                entity: entity,
                identifier: identifier,
                field: field,
                reason: .currencyNotEstablished
            )
            return nil
        }
        guard let metadata = try? CurrencyMetadata(code: code) else {
            report.append(
                entity: entity,
                identifier: identifier,
                field: field,
                reason: .unsupportedCurrency
            )
            return nil
        }
        return metadata
    }

    private static func reason(
        for error: LegacyMoneyConversionError
    ) -> LegacyMoneyMigrationAnomalyReason {
        switch error {
        case .nonFinite: return .nonFiniteLegacyValue
        case .malformedDecimal: return .malformedLegacyDecimal
        case .outOfRange: return .outOfRange
        }
    }
}

struct LegacyBudgetSettingsMigrationResult: Equatable, Sendable {
    let settings: BudgetSettings
    let anomalyReport: LegacyMoneyAnomalyReport

    var isExactMoneyCutoverAllowed: Bool {
        !anomalyReport.isBlocking
    }
}

enum LegacyBudgetSettingsMigrator {
    static func migrate(
        _ settings: BudgetSettings,
        currencySource: (any VerifiedCurrencySource)? = nil
    ) -> LegacyBudgetSettingsMigrationResult {
        let source = currencySource ?? StaticVerifiedCurrencySource(currencyCode: nil)
        var migrated = settings
        var report = LegacyMoneyAnomalyReport()
        let sourceMetadata = source.verifiedCurrencyCode.flatMap { try? CurrencyMetadata(code: $0) }
        let hasCurrencyMismatch: Bool
        if let sourceMetadata,
           sourceMetadata.code != CurrencyMetadata.normalize(settings.currencyCode) {
            report.append(
                entity: "budgetSettings",
                identifier: settings.currencyCode,
                field: "currencyCode",
                reason: .currencyMismatch
            )
            hasCurrencyMismatch = true
        } else {
            hasCurrencyMismatch = false
        }

        var allKeys = Set(settings.categoryBudgets.keys)
        allKeys.formUnion(settings.categoryBudgetsMinorUnits.keys)
        for key in allKeys.sorted() {
            if BudgetSettings.isHiddenMarkerKey(key) {
                let category = String(
                    key.dropFirst(TransactionCategory.hiddenCategoryPrefix.count)
                )
                guard !category.isEmpty else {
                    report.append(
                        entity: "budgetSettings",
                        identifier: key,
                        field: "categoryBudgets",
                        reason: .malformedSettingsKey
                    )
                    continue
                }
                migrated.categoryVisibility[category] = .hidden
                migrated.categoryBudgetsMinorUnits.removeValue(forKey: key)
                continue
            }

            guard settings.categoryBudgets[key] != nil else {
                report.append(
                    entity: "budgetSettings",
                    identifier: key,
                    field: "categoryBudgetsMinorUnits",
                    reason: .incompleteExactFields
                )
                continue
            }

            let category: String
            if BudgetSettings.isMonthBudgetKey(key) {
                guard let scoped = BudgetSettings.monthAndCategory(from: key) else {
                    report.append(
                        entity: "budgetSettings",
                        identifier: key,
                        field: "categoryBudgets",
                        reason: .malformedSettingsKey
                    )
                    continue
                }
                category = scoped.categoryRawValue
            } else {
                guard !key.isEmpty else {
                    report.append(
                        entity: "budgetSettings",
                        identifier: key,
                        field: "categoryBudgets",
                        reason: .malformedSettingsKey
                    )
                    continue
                }
                category = key
            }

            guard !hasCurrencyMismatch else { continue }

            guard let metadata = sourceMetadata else {
                if source.verifiedCurrencyCode != nil {
                    report.append(
                        entity: "budgetSettings",
                        identifier: key,
                        field: "categoryBudgets",
                        reason: .unsupportedCurrency
                    )
                } else {
                    report.append(
                        entity: "budgetSettings",
                        identifier: key,
                        field: "categoryBudgets",
                        reason: .currencyNotEstablished
                    )
                }
                continue
            }

            if let existingMinorUnits = migrated.categoryBudgetsMinorUnits[key] {
                switch LegacyDoubleMoneyConverter.convert(
                    settings.categoryBudgets[key] ?? 0,
                    metadata: metadata
                ) {
                case .success(let reproducibleMinorUnits) where reproducibleMinorUnits == existingMinorUnits:
                    if migrated.categoryVisibility[category] == nil {
                        migrated.categoryVisibility[category] = .visible
                    }
                case .success:
                    report.append(
                        entity: "budgetSettings",
                        identifier: key,
                        field: "categoryBudgets",
                        reason: .contradictoryExactFields
                    )
                case .failure(let error):
                    report.append(
                        entity: "budgetSettings",
                        identifier: key,
                        field: "categoryBudgets",
                        reason: reason(for: error)
                    )
                }
                continue
            }

            switch LegacyDoubleMoneyConverter.convert(
                settings.categoryBudgets[key] ?? 0,
                metadata: metadata
            ) {
            case .success(let minorUnits):
                migrated.categoryBudgetsMinorUnits[key] = minorUnits
                if migrated.categoryVisibility[category] == nil {
                    migrated.categoryVisibility[category] = .visible
                }
            case .failure(let error):
                report.append(
                    entity: "budgetSettings",
                    identifier: key,
                    field: "categoryBudgets",
                    reason: reason(for: error)
                )
            }
        }

        return LegacyBudgetSettingsMigrationResult(
            settings: migrated,
            anomalyReport: report
        )
    }

    private static func reason(
        for error: LegacyMoneyConversionError
    ) -> LegacyMoneyMigrationAnomalyReason {
        switch error {
        case .nonFinite: return .nonFiniteLegacyValue
        case .malformedDecimal: return .malformedLegacyDecimal
        case .outOfRange: return .outOfRange
        }
    }
}

enum LegacyMoneyAnomalyStore {
    static let fileName = "BudgetMate-money-migration-anomalies.json"

    static func storeURL(forStoreURL storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appendingPathComponent(fileName)
    }

    static func settingsURL(
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BudgetMate", isDirectory: true)
            .appendingPathComponent("BudgetSettings-" + fileName)
    }

    static func save(
        _ report: LegacyMoneyAnomalyReport,
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        if report.anomalies.isEmpty {
            try? fileManager.removeItem(at: url)
            return
        }
        let data = try JSONEncoder().encode(report)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    static func load(
        at url: URL,
        fileManager: FileManager = .default
    ) throws -> LegacyMoneyAnomalyReport? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(
            LegacyMoneyAnomalyReport.self,
            from: Data(contentsOf: url)
        )
    }
}

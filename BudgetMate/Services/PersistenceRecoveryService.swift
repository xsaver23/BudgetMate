import CryptoKit
import Foundation
import SQLite3
import SwiftData

struct PersistenceStoreSnapshot: Codable, Equatable, Sendable {
    let transactionCount: Int
    let splitCount: Int
    let settlementCount: Int
    let relationshipDigest: String
}

struct PersistenceArchiveFile: Codable, Equatable, Sendable {
    let relativePath: String
    let targetRelativePath: String
    let originalFilename: String
    let kind: String
    let byteSize: Int64
    let sha256: String
}

struct PersistenceArchiveManifest: Codable, Equatable, Sendable {
    let archiveFormatVersion: Int
    let schemaVersion: String
    let appVersion: String
    let appBuild: String
    let createdAt: Date
    let reason: String
    let sourceOpenStatus: String
    let sourceStoreFilename: String
    let sourceArtifactFingerprint: String
    let files: [PersistenceArchiveFile]
    let snapshot: PersistenceStoreSnapshot?
    let sanitizedDiagnostics: PersistenceSanitizedDiagnostics
    let legacyMetadataStatus: PersistenceLegacyMetadataStatus?
}

struct PersistenceLegacyMetadataStatus: Codable, Equatable, Sendable {
    let formatVersion: Int
    let sidecarTargetRelativePath: String
    let sourceArtifactFingerprint: String
    let sourceMetadataFingerprint: String?
    let transactionRowCount: Int
    let settlementRowCount: Int
    let pendingRowCount: Int
    let requiresManualReview: Bool
    let cloudRowVersionMapping: String
    let pendingMutationMapping: String
    let reviewedResolution: PersistenceLegacyMetadataResolution?
}

struct PersistenceLegacyMetadataResolution: Codable, Equatable, Sendable {
    static let retryWithFreshGateCMutationID = "retry-with-fresh-gate-c-mutation-id"

    let decision: String
    let sourceArtifactFingerprint: String
    let sourceMetadataFingerprint: String
}

struct PersistenceLegacyMetadataReviewToken: Codable, Equatable, Sendable {
    let sourceArtifactFingerprint: String
    let sourceMetadataFingerprint: String
    let transactionRowCount: Int
    let settlementRowCount: Int
    let pendingRowCount: Int
}

struct PersistenceLegacyMetadataRow: Codable, Equatable, Sendable {
    let stableID: String
    let cloudRowVersion: Int64?
    let pendingMutationBytesBase64: String?
    let needsSync: Bool
}

struct PersistenceLegacyMetadataSidecar: Codable, Equatable, Sendable {
    let formatVersion: Int
    let sourceArtifactFingerprint: String
    let sourceMetadataFingerprint: String?
    let transactionRows: [PersistenceLegacyMetadataRow]
    let settlementRows: [PersistenceLegacyMetadataRow]
    let pendingMutationSemantics: String
    let mappedCloudRowVersionSemantics: String
    let reviewedResolution: PersistenceLegacyMetadataResolution?
}

struct PersistenceSanitizedDiagnostics: Codable, Equatable, Sendable {
    let operation: String
    let failureCode: String
    let storeFilename: String
    let message: String
}

struct PersistenceArchiveResult: Sendable {
    let archiveURL: URL
    let manifest: PersistenceArchiveManifest
    let isRestorable: Bool
}

struct PersistenceArchiveVerification: Sendable {
    let archiveURL: URL
    let manifest: PersistenceArchiveManifest
    let snapshot: PersistenceStoreSnapshot
}

enum PersistenceRecoveryError: Error, LocalizedError {
    case notFileBacked
    case storeMissing
    case archiveNotVerified
    case invalidArchive
    case unsupportedArchive
    case checksumMismatch
    case incompleteArchive
    case archiveNotCurrent
    case storeValidationFailed
    case noVerifiedArchive
    case legacySurfaceNotFound
    case legacyMetadataReviewRequired
    case legacyMetadataMismatch
    case fileSystemFailure
    case interruptedReplacement

    var errorDescription: String? {
        switch self {
        case .notFileBacked:
            return "This recovery operation is only available for local file-backed data."
        case .storeMissing:
            return "The local store is not available to archive."
        case .archiveNotVerified:
            return "The archive could not be verified as restorable."
        case .archiveNotCurrent:
            return "The verified archive no longer matches the current local store."
        case .invalidArchive, .unsupportedArchive, .checksumMismatch, .incompleteArchive:
            return "The selected archive is invalid or incomplete."
        case .storeValidationFailed:
            return "The staged local store failed validation."
        case .noVerifiedArchive:
            return "A current verified archive is required before resetting local data."
        case .legacySurfaceNotFound:
            return "No supported legacy local-store surface was found."
        case .legacyMetadataReviewRequired:
            return "Recovery is blocked until legacy sync metadata is reviewed. The local store was left untouched."
        case .legacyMetadataMismatch:
            return "Legacy sync metadata could not be reconciled without risking local data."
        case .fileSystemFailure, .interruptedReplacement:
            return "Local-data recovery stopped safely without discarding the current store."
        }
    }
}

private struct PersistenceArchiveArtifact {
    let sourceURL: URL
    let targetRelativePath: String
    let kind: String
}

private struct LegacyRecoveryStaging {
    let rootURL: URL
    let artifacts: [PersistenceArchiveArtifact]
}

struct PersistenceReplacementJournal: Codable {
    var phase: String
    let storeFilename: String
    let stageDirectoryName: String
    let backupDirectoryName: String
    let oldTargets: [String]
    let newTargets: [String]
}

private enum LegacySQLiteValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

private struct LegacyMetadataCapture {
    let transactionRows: [PersistenceLegacyMetadataRow]
    let settlementRows: [PersistenceLegacyMetadataRow]
    let sourceMetadataFingerprint: String

    var pendingRowCount: Int {
        transactionRows.filter { $0.pendingMutationBytesBase64 != nil }.count
            + settlementRows.filter { $0.pendingMutationBytesBase64 != nil }.count
    }
}

private struct LegacyRecoverySplitRecord: Equatable {
    let id: String
    let memberID: String
    let amount: Double
    let amountMinorUnits: Int64?
    let currencyCode: String?
}

private struct LegacyRecoveryTransactionRecord: Equatable {
    let id: String
    let amount: Double
    let amountMinorUnits: Int64?
    let currencyCode: String?
    let type: String
    let category: String
    let paymentMethod: String?
    let createdByMemberID: String
    let needsSync: Bool
    let splits: [LegacyRecoverySplitRecord]
}

private struct LegacyRecoverySettlementRecord: Equatable {
    let id: String
    let fromMemberID: String
    let toMemberID: String
    let amount: Double
    let amountMinorUnits: Int64?
    let currencyCode: String?
    let needsSync: Bool
}

private struct LegacyRecoveryFinancialSnapshot: Equatable {
    let transactions: [LegacyRecoveryTransactionRecord]
    let settlements: [LegacyRecoverySettlementRecord]
}

private final class LegacySQLiteReader {
    private var database: OpaquePointer?

    init(url: URL) throws {
        var opened: OpaquePointer?
        let result = url.path.withCString { path in
            sqlite3_open_v2(
                path,
                &opened,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_URI,
                nil
            )
        }
        guard result == SQLITE_OK, let opened else {
            if let opened { sqlite3_close(opened) }
            throw PersistenceRecoveryError.legacyMetadataMismatch
        }
        database = opened
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func captureMetadata() throws -> LegacyMetadataCapture {
        let transactionRows = try captureRows(from: "ZTRANSACTION")
        let settlementRows = try captureRows(from: "ZSETTLEMENT")
        return LegacyMetadataCapture(
            transactionRows: transactionRows,
            settlementRows: settlementRows,
            sourceMetadataFingerprint: recoveryLegacyMetadataFingerprint(
                transactionRows: transactionRows,
                settlementRows: settlementRows
            )
        )
    }

    private func captureRows(from table: String) throws -> [PersistenceLegacyMetadataRow] {
        let columns = try columnNames(for: table)
        let lowercaseColumns = Dictionary(
            uniqueKeysWithValues: columns.map { ($0.lowercased(), $0) }
        )
        guard let idColumn = lowercaseColumns["zid"],
              let cloudColumn = lowercaseColumns["zcloudrowversion"],
              let pendingColumn = lowercaseColumns["zpendingmutationid"],
              let needsSyncColumn = lowercaseColumns["zneedssync"] else {
            throw PersistenceRecoveryError.legacySurfaceNotFound
        }

        let rows = try query(
            "SELECT \(quote(idColumn)) AS c0, \(quote(cloudColumn)) AS c1, \(quote(pendingColumn)) AS c2, \(quote(needsSyncColumn)) AS c3 FROM \(quote(table)) ORDER BY \(quote(idColumn))"
        )
        return try rows.map { row in
            guard let stableID = stableID(from: row["c0"]),
                  let needsSync = integer(from: row["c3"]) else {
                throw PersistenceRecoveryError.legacyMetadataMismatch
            }
            return PersistenceLegacyMetadataRow(
                stableID: stableID,
                cloudRowVersion: integer(from: row["c1"]),
                pendingMutationBytesBase64: opaqueBase64(from: row["c2"]),
                needsSync: needsSync != 0
            )
        }
    }

    private func columnNames(for table: String) throws -> [String] {
        try query("PRAGMA table_info(\(quote(table)))").compactMap { row in
            text(from: row["name"])
        }
    }

    private func query(_ sql: String) throws -> [[String: LegacySQLiteValue]] {
        guard let database else { throw PersistenceRecoveryError.legacyMetadataMismatch }
        var statement: OpaquePointer?
        let prepareResult = sql.withCString { sqlPointer in
            sqlite3_prepare_v2(database, sqlPointer, -1, &statement, nil)
        }
        guard prepareResult == SQLITE_OK, let statement else {
            throw PersistenceRecoveryError.legacyMetadataMismatch
        }
        defer { sqlite3_finalize(statement) }

        var result: [[String: LegacySQLiteValue]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else {
                throw PersistenceRecoveryError.legacyMetadataMismatch
            }
            var row: [String: LegacySQLiteValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                guard let namePointer = sqlite3_column_name(statement, index) else {
                    throw PersistenceRecoveryError.legacyMetadataMismatch
                }
                row[String(cString: namePointer)] = value(
                    from: statement,
                    index: index
                )
            }
            result.append(row)
        }
    }

    private func value(
        from statement: OpaquePointer,
        index: Int32
    ) -> LegacySQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let pointer = sqlite3_column_text(statement, index) else { return .text("") }
            return .text(String(cString: pointer))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, index))
            guard count > 0, let pointer = sqlite3_column_blob(statement, index) else {
                return .blob(Data())
            }
            return .blob(Data(bytes: pointer, count: count))
        default:
            return .null
        }
    }

    private func stableID(from value: LegacySQLiteValue?) -> String? {
        switch value {
        case .text(let value):
            return UUID(uuidString: value)?.uuidString
        case .blob(let data):
            guard data.count == 16 else { return nil }
            let bytes = Array(data)
            let uuid = UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            ))
            return uuid.uuidString
        default:
            return nil
        }
    }

    private func opaqueBase64(from value: LegacySQLiteValue?) -> String? {
        switch value {
        case .blob(let data) where !data.isEmpty:
            return data.base64EncodedString()
        case .text(let value) where !value.isEmpty:
            return Data(value.utf8).base64EncodedString()
        default:
            return nil
        }
    }

    private func integer(from value: LegacySQLiteValue?) -> Int64? {
        switch value {
        case .integer(let value): return value
        case .real(let value): return Int64(value)
        case .text(let value): return Int64(value)
        default: return nil
        }
    }

    private func text(from value: LegacySQLiteValue?) -> String? {
        if case .text(let value) = value { return value }
        return nil
    }

    private func quote(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// File-backed support archive and replacement boundary. It handles the
/// immutable PR01A V1 schema plus the explicit staged V1→V2→V3 bridge; it
/// does not touch UserDefaults, cloud state, or application-level recovery
/// settings.
@MainActor
final class PersistenceRecoveryService {
    static let archiveFormatVersion = 1
    private static let legacySchemaVersion = "1.0.0"
    private static let replacementJournalSuffix = ".budgetmate-replacement.json"

    private let fileManager: FileManager
    private let archiveDirectory: URL

    init(fileManager: FileManager = .default, archiveDirectory: URL? = nil) {
        self.fileManager = fileManager
        if let archiveDirectory {
            self.archiveDirectory = archiveDirectory
        } else {
            let base = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.archiveDirectory = base.appendingPathComponent(
                "BudgetMateRecoveryArchives",
                isDirectory: true
            )
        }
    }

    func createSupportArchive(
        for descriptor: PersistenceStoreDescriptor,
        reason: String,
        failureCode: String = "persistence-open-failed"
    ) throws -> PersistenceArchiveResult {
        guard !descriptor.isStoredInMemoryOnly else { throw PersistenceRecoveryError.notFileBacked }
        guard fileManager.fileExists(atPath: descriptor.storeURL.path) else {
            throw PersistenceRecoveryError.storeMissing
        }

        let artifacts = try collectArtifacts(for: descriptor)
        guard artifacts.contains(where: { $0.kind == "primary" }) else {
            throw PersistenceRecoveryError.storeMissing
        }
        // Bind reset eligibility to the exact active artifact set before a
        // staged SwiftData open can checkpoint or otherwise rewrite the copy.
        let sourceArtifactFingerprint = try artifactFingerprint(for: artifacts)

        try makeProtectedDirectory(archiveDirectory)
        let archiveName = "BudgetMate-" + String(Int(Date().timeIntervalSince1970)) + "-" + UUID().uuidString + ".budgetmatearchive"
        let temporaryArchive = archiveDirectory.appendingPathComponent(
            "." + archiveName + ".partial",
            isDirectory: true
        )
        let finalArchive = archiveDirectory.appendingPathComponent(archiveName, isDirectory: true)
        try? fileManager.removeItem(at: temporaryArchive)
        defer { try? fileManager.removeItem(at: temporaryArchive) }

        try makeProtectedDirectory(temporaryArchive)
        let payloadDirectory = temporaryArchive.appendingPathComponent("payload", isDirectory: true)
        try makeProtectedDirectory(payloadDirectory)

        for artifact in artifacts {
            let sourceIsSymbolicLink = try isSymbolicLink(artifact.sourceURL)
            guard !sourceIsSymbolicLink else {
                throw PersistenceRecoveryError.fileSystemFailure
            }
            let destination = payloadDirectory.appendingPathComponent(
                artifact.targetRelativePath,
                isDirectory: false
            )
            try makeProtectedDirectory(destination.deletingLastPathComponent())
            try fileManager.copyItem(at: artifact.sourceURL, to: destination)
            try protectTree(at: destination)
        }

        let primary = try requirePrimary(in: artifacts)
        let stagedPrimary = payloadDirectory.appendingPathComponent(primary.targetRelativePath)
        let stagedSnapshot = try? validateStore(
            at: stagedPrimary,
            schemaVersion: descriptor.schemaVersion
        )
        let isRestorable = stagedSnapshot != nil
        let manifestFiles = try artifacts.flatMap { artifact in
            try filesForManifest(
                at: payloadDirectory.appendingPathComponent(artifact.targetRelativePath),
                targetRelativePath: artifact.targetRelativePath,
                kind: artifact.kind
            )
        }
        let sortedManifestFiles = manifestFiles.sorted { lhs, rhs in
            if lhs.targetRelativePath == rhs.targetRelativePath {
                return lhs.relativePath < rhs.relativePath
            }
            return lhs.targetRelativePath < rhs.targetRelativePath
        }
        let manifest = PersistenceArchiveManifest(
            archiveFormatVersion: Self.archiveFormatVersion,
            schemaVersion: descriptor.schemaVersion,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            createdAt: .now,
            reason: sanitizedReason(reason),
            sourceOpenStatus: isRestorable ? "verified" : "unverified",
            sourceStoreFilename: descriptor.storeURL.lastPathComponent,
            sourceArtifactFingerprint: sourceArtifactFingerprint,
            files: sortedManifestFiles,
            snapshot: stagedSnapshot,
            sanitizedDiagnostics: PersistenceSanitizedDiagnostics(
                operation: "create-support-archive",
                failureCode: sanitizedReason(failureCode),
                storeFilename: descriptor.storeURL.lastPathComponent,
                message: isRestorable
                    ? "The local store was copied and validated before publication."
                    : "The local store was copied, but validation did not succeed."
            ),
            legacyMetadataStatus: nil
        )

        try writeJSON(manifest, to: temporaryArchive.appendingPathComponent("manifest.json"))
        try writeJSON(
            manifest.sanitizedDiagnostics,
            to: temporaryArchive.appendingPathComponent("diagnostics.json")
        )
        try protectTree(at: temporaryArchive)
        try fileManager.moveItem(at: temporaryArchive, to: finalArchive)

        return PersistenceArchiveResult(
            archiveURL: finalArchive,
            manifest: manifest,
            isRestorable: isRestorable
        )
    }

    private func makeVerifiedLegacyStaging(
        sourceArtifacts: [PersistenceArchiveArtifact],
        sourceFingerprint: String
    ) throws -> LegacyRecoveryStaging {
        let stagingRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "BudgetMateLegacyRecovery-" + UUID().uuidString,
            isDirectory: true
        )
        do {
            try makeProtectedDirectory(stagingRoot)
            for artifact in sourceArtifacts {
                let destination = stagingRoot.appendingPathComponent(
                    artifact.targetRelativePath,
                    isDirectory: false
                )
                try makeProtectedDirectory(destination.deletingLastPathComponent())
                guard try !isSymbolicLink(artifact.sourceURL) else {
                    throw PersistenceRecoveryError.fileSystemFailure
                }
                try fileManager.copyItem(at: artifact.sourceURL, to: destination)
                try protectTree(at: destination)
            }
            let stagedArtifacts = sourceArtifacts.map { artifact in
                PersistenceArchiveArtifact(
                    sourceURL: stagingRoot.appendingPathComponent(artifact.targetRelativePath),
                    targetRelativePath: artifact.targetRelativePath,
                    kind: artifact.kind
                )
            }
            guard try artifactFingerprint(for: stagedArtifacts) == sourceFingerprint,
                  try artifactFingerprint(for: sourceArtifacts) == sourceFingerprint else {
                throw PersistenceRecoveryError.checksumMismatch
            }
            return LegacyRecoveryStaging(rootURL: stagingRoot, artifacts: stagedArtifacts)
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        }
    }

    /// Converts a legacy physical store only on a fresh staging copy. The
    /// source is never opened by SwiftData and is never replaced. The old
    /// cloud row version has a documented server-version meaning in the
    /// release history, so it is restored to V3 `rowVersion`. The pending
    /// mutation column has no equivalent provenance in this repository; its
    /// bytes are preserved in an opaque sidecar and restore remains blocked
    /// unless an exact digest-bound review resolution is supplied.
    func legacyMetadataReviewToken(
        for descriptor: PersistenceStoreDescriptor
    ) throws -> PersistenceLegacyMetadataReviewToken {
        guard !descriptor.isStoredInMemoryOnly else { throw PersistenceRecoveryError.notFileBacked }
        guard fileManager.fileExists(atPath: descriptor.storeURL.path) else {
            throw PersistenceRecoveryError.storeMissing
        }
        let sourceArtifacts = try collectArtifacts(for: descriptor).filter {
            $0.kind == "primary" || $0.kind == "sidecar"
        }
        guard sourceArtifacts.contains(where: { $0.kind == "primary" }) else {
            throw PersistenceRecoveryError.storeMissing
        }
        let sourceFingerprintBefore = try artifactFingerprint(for: sourceArtifacts)
        let staging = try makeVerifiedLegacyStaging(
            sourceArtifacts: sourceArtifacts,
            sourceFingerprint: sourceFingerprintBefore
        )
        defer { try? fileManager.removeItem(at: staging.rootURL) }
        let metadata = try LegacySQLiteReader(
            url: try requirePrimary(in: staging.artifacts).sourceURL
        ).captureMetadata()
        guard try artifactFingerprint(for: sourceArtifacts) == sourceFingerprintBefore else {
            throw PersistenceRecoveryError.checksumMismatch
        }
        return PersistenceLegacyMetadataReviewToken(
            sourceArtifactFingerprint: sourceFingerprintBefore,
            sourceMetadataFingerprint: metadata.sourceMetadataFingerprint,
            transactionRowCount: metadata.transactionRows.count,
            settlementRowCount: metadata.settlementRows.count,
            pendingRowCount: metadata.pendingRowCount
        )
    }

    func createSchema3RecoveryArchive(
        for descriptor: PersistenceStoreDescriptor,
        reason: String = "legacy local-store recovery",
        failureCode: String = "legacy-store-recovery",
        reviewedResolution: PersistenceLegacyMetadataResolution? = nil
    ) throws -> PersistenceArchiveResult {
        guard !descriptor.isStoredInMemoryOnly else { throw PersistenceRecoveryError.notFileBacked }
        guard fileManager.fileExists(atPath: descriptor.storeURL.path) else {
            throw PersistenceRecoveryError.storeMissing
        }

        let sourceArtifacts = try collectArtifacts(for: descriptor).filter {
            $0.kind == "primary" || $0.kind == "sidecar"
        }
        guard sourceArtifacts.contains(where: { $0.kind == "primary" }) else {
            throw PersistenceRecoveryError.storeMissing
        }
        let sourceFingerprintBefore = try artifactFingerprint(for: sourceArtifacts)

        let staging = try makeVerifiedLegacyStaging(
            sourceArtifacts: sourceArtifacts,
            sourceFingerprint: sourceFingerprintBefore
        )
        defer { try? fileManager.removeItem(at: staging.rootURL) }
        let stagedArtifacts = staging.artifacts

        let primary = try requirePrimary(in: stagedArtifacts)
        // This is the only read of the legacy metadata, and it happens before
        // any SwiftData/Core Data open can normalize the physical columns.
        let legacyMetadata = try LegacySQLiteReader(url: primary.sourceURL).captureMetadata()
        try validateReviewedResolution(
            reviewedResolution,
            sourceArtifactFingerprint: sourceFingerprintBefore,
            sourceMetadataFingerprint: legacyMetadata.sourceMetadataFingerprint,
            metadata: legacyMetadata
        )
        let legacyFinancialSnapshot = try readLegacyFinancialSnapshot(at: primary.sourceURL)
        let currentFinancialSnapshot = try migrateLegacyStagedStore(
            at: primary.sourceURL,
            metadata: legacyMetadata,
            reviewedResolution: reviewedResolution
        )
        guard currentFinancialSnapshot == legacyFinancialSnapshot else {
            throw PersistenceRecoveryError.legacyMetadataMismatch
        }
        guard try artifactFingerprint(for: sourceArtifacts) == sourceFingerprintBefore else {
            throw PersistenceRecoveryError.checksumMismatch
        }

        let sidecar = PersistenceLegacyMetadataSidecar(
            formatVersion: 1,
            sourceArtifactFingerprint: sourceFingerprintBefore,
            sourceMetadataFingerprint: legacyMetadata.sourceMetadataFingerprint,
            transactionRows: legacyMetadata.transactionRows,
            settlementRows: legacyMetadata.settlementRows,
            pendingMutationSemantics: reviewedResolution == nil
                ? "unproven-opaque-preserved-no-v3-mapping"
                : "opaque-preserved-reviewed-\(PersistenceLegacyMetadataResolution.retryWithFreshGateCMutationID)-fresh-id-on-sync",
            mappedCloudRowVersionSemantics: "release-152fb5b-server-row-version-to-v3-rowVersion",
            reviewedResolution: reviewedResolution
        )
        let sidecarTarget = primary.sourceURL.lastPathComponent + "-legacy-metadata.json"
        let sidecarURL = staging.rootURL.appendingPathComponent(sidecarTarget)
        try writeJSON(sidecar, to: sidecarURL)
        try protectTree(at: sidecarURL)

        let stagedDescriptor = PersistenceStoreDescriptor(
            storeURL: primary.sourceURL,
            schemaVersion: BudgetMateSchema.currentVersionString
        )
        return try createMigratedArchive(
            for: stagedDescriptor,
            sourceArtifactFingerprint: sourceFingerprintBefore,
            sidecar: sidecar,
            sidecarURL: sidecarURL,
            sidecarTarget: sidecarTarget,
            snapshot: try validateCurrentStore(at: primary.sourceURL),
            reason: reason,
            failureCode: failureCode
        )
    }

    private func validateReviewedResolution(
        _ resolution: PersistenceLegacyMetadataResolution?,
        sourceArtifactFingerprint: String,
        sourceMetadataFingerprint: String,
        metadata: LegacyMetadataCapture
    ) throws {
        guard let resolution else { return }
        let pendingRows = metadata.transactionRows.filter { $0.pendingMutationBytesBase64 != nil }
            + metadata.settlementRows.filter { $0.pendingMutationBytesBase64 != nil }
        guard !pendingRows.isEmpty,
              resolution.decision == PersistenceLegacyMetadataResolution.retryWithFreshGateCMutationID,
              resolution.sourceArtifactFingerprint == sourceArtifactFingerprint,
              resolution.sourceMetadataFingerprint == sourceMetadataFingerprint,
              pendingRows.allSatisfy({ $0.needsSync && $0.cloudRowVersion == 0 }) else {
            throw PersistenceRecoveryError.legacyMetadataMismatch
        }
    }

    func verifyArchive(at archiveURL: URL) throws -> PersistenceArchiveVerification {
        let manifest = try validateArchivePackage(at: archiveURL)
        try validateLegacyMetadataSidecarIfPresent(
            manifest: manifest,
            archiveURL: archiveURL
        )
        guard manifest.sourceOpenStatus == "verified",
              let expectedSnapshot = manifest.snapshot else {
            throw PersistenceRecoveryError.archiveNotVerified
        }

        guard let primary = manifest.files.first(where: { $0.kind == "primary" }) else {
            throw PersistenceRecoveryError.incompleteArchive
        }
        let payloadPath = archiveURL.appendingPathComponent(primary.relativePath)
        guard let actualSnapshot = try? validateStore(
            at: payloadPath,
            schemaVersion: manifest.schemaVersion
        ),
              actualSnapshot == expectedSnapshot else {
            throw PersistenceRecoveryError.storeValidationFailed
        }
        try validateLegacyMetadataPayloadIfPresent(
            manifest: manifest,
            archiveURL: archiveURL,
            primaryURL: payloadPath
        )
        return PersistenceArchiveVerification(
            archiveURL: archiveURL,
            manifest: manifest,
            snapshot: actualSnapshot
        )
    }

    /// Test seam for asserting the same count/relationship summary used by
    /// archive verification without exposing a second production data path.
    func verifyStoreForTesting(
        at storeURL: URL,
        schemaVersion: String = BudgetMateSchema.currentVersionString
    ) throws -> PersistenceStoreSnapshot {
        try validateStore(at: storeURL, schemaVersion: schemaVersion)
    }

    private func readLegacyFinancialSnapshot(
        at storeURL: URL
    ) throws -> LegacyRecoveryFinancialSnapshot {
        let schema = Schema(versionedSchema: BudgetMateSchemaV1.self)
        let configuration = ModelConfiguration(
            "BudgetMateLegacyRecoveryV1",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = container.mainContext
        let transactions = try context.fetch(
            FetchDescriptor<BudgetMateSchemaV1.Transaction>()
        )
        let settlements = try context.fetch(
            FetchDescriptor<BudgetMateSchemaV1.Settlement>()
        )
        return LegacyRecoveryFinancialSnapshot(
            transactions: transactions.map { transaction in
                LegacyRecoveryTransactionRecord(
                    id: transaction.id.uuidString,
                    amount: transaction.amount,
                    amountMinorUnits: nil,
                    currencyCode: nil,
                    type: transaction.type.rawValue,
                    category: transaction.category.rawValue,
                    paymentMethod: transaction.paymentMethod?.rawValue,
                    createdByMemberID: transaction.createdByMemberId.uuidString,
                    needsSync: transaction.needsSync,
                    splits: transaction.splits.map { split in
                        LegacyRecoverySplitRecord(
                            id: split.id.uuidString,
                            memberID: split.memberId.uuidString,
                            amount: split.amount,
                            amountMinorUnits: nil,
                            currencyCode: nil
                        )
                    }.sorted { $0.id < $1.id }
                )
            }.sorted { $0.id < $1.id },
            settlements: settlements.map { settlement in
                LegacyRecoverySettlementRecord(
                    id: settlement.id.uuidString,
                    fromMemberID: settlement.fromMemberId.uuidString,
                    toMemberID: settlement.toMemberId.uuidString,
                    amount: settlement.amount,
                    amountMinorUnits: nil,
                    currencyCode: nil,
                    needsSync: settlement.needsSync
                )
            }.sorted { $0.id < $1.id }
        )
    }

    private func normalizedRowVersion(
        for row: PersistenceLegacyMetadataRow,
        reviewedResolution: PersistenceLegacyMetadataResolution?
    ) throws -> Int64? {
        guard reviewedResolution != nil, row.pendingMutationBytesBase64 != nil else {
            return row.cloudRowVersion
        }
        guard row.needsSync, row.cloudRowVersion == 0 else {
            throw PersistenceRecoveryError.legacyMetadataMismatch
        }
        return nil
    }

    private func normalizedNeedsSync(
        for row: PersistenceLegacyMetadataRow,
        reviewedResolution: PersistenceLegacyMetadataResolution?
    ) throws -> Bool {
        guard reviewedResolution != nil, row.pendingMutationBytesBase64 != nil else {
            return row.needsSync
        }
        guard row.needsSync, row.cloudRowVersion == 0 else {
            throw PersistenceRecoveryError.legacyMetadataMismatch
        }
        return true
    }

    private func migrateLegacyStagedStore(
        at storeURL: URL,
        metadata: LegacyMetadataCapture,
        reviewedResolution: PersistenceLegacyMetadataResolution?
    ) throws -> LegacyRecoveryFinancialSnapshot {
        let configuration = ModelConfiguration(
            "BudgetMateLegacyRecoveryV3",
            schema: BudgetMateSchema.current,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: BudgetMateSchema.current,
            migrationPlan: BudgetMateSchemaMigrationPlan.self,
            configurations: [configuration]
        )
        let context = container.mainContext
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let settlements = try context.fetch(FetchDescriptor<Settlement>())
        let transactionMetadata = Dictionary(
            uniqueKeysWithValues: metadata.transactionRows.map { ($0.stableID, $0) }
        )
        let settlementMetadata = Dictionary(
            uniqueKeysWithValues: metadata.settlementRows.map { ($0.stableID, $0) }
        )
        guard transactions.count == metadata.transactionRows.count,
              settlements.count == metadata.settlementRows.count else {
            throw PersistenceRecoveryError.legacyMetadataMismatch
        }

        for transaction in transactions {
            guard let row = transactionMetadata[transaction.id.uuidString] else {
                throw PersistenceRecoveryError.legacyMetadataMismatch
            }
            // This mapping is backed by the release sync contract. Do not
            // substitute the opaque pending value here.
            transaction.rowVersion = try normalizedRowVersion(
                for: row,
                reviewedResolution: reviewedResolution
            )
            transaction.lastMutationId = nil
            transaction.needsSync = try normalizedNeedsSync(
                for: row,
                reviewedResolution: reviewedResolution
            )
        }
        for settlement in settlements {
            guard let row = settlementMetadata[settlement.id.uuidString] else {
                throw PersistenceRecoveryError.legacyMetadataMismatch
            }
            settlement.rowVersion = try normalizedRowVersion(
                for: row,
                reviewedResolution: reviewedResolution
            )
            settlement.lastMutationId = nil
            settlement.needsSync = try normalizedNeedsSync(
                for: row,
                reviewedResolution: reviewedResolution
            )
        }
        try context.save()

        let persistedTransactions = try context.fetch(FetchDescriptor<Transaction>())
        let persistedSettlements = try context.fetch(FetchDescriptor<Settlement>())
        for transaction in persistedTransactions {
            guard let row = transactionMetadata[transaction.id.uuidString] else {
                throw PersistenceRecoveryError.legacyMetadataMismatch
            }
            let expectedRowVersion = try normalizedRowVersion(
                for: row,
                reviewedResolution: reviewedResolution
            )
            let expectedNeedsSync = try normalizedNeedsSync(
                for: row,
                reviewedResolution: reviewedResolution
            )
            guard transaction.rowVersion == expectedRowVersion,
                  transaction.lastMutationId == nil,
                  transaction.needsSync == expectedNeedsSync else {
                throw PersistenceRecoveryError.legacyMetadataMismatch
            }
        }
        for settlement in persistedSettlements {
            guard let row = settlementMetadata[settlement.id.uuidString] else {
                throw PersistenceRecoveryError.legacyMetadataMismatch
            }
            let expectedRowVersion = try normalizedRowVersion(
                for: row,
                reviewedResolution: reviewedResolution
            )
            let expectedNeedsSync = try normalizedNeedsSync(
                for: row,
                reviewedResolution: reviewedResolution
            )
            guard settlement.rowVersion == expectedRowVersion,
                  settlement.lastMutationId == nil,
                  settlement.needsSync == expectedNeedsSync else {
                throw PersistenceRecoveryError.legacyMetadataMismatch
            }
        }

        return LegacyRecoveryFinancialSnapshot(
            transactions: persistedTransactions.map { transaction in
                LegacyRecoveryTransactionRecord(
                    id: transaction.id.uuidString,
                    amount: transaction.amount,
                    amountMinorUnits: transaction.amountMinorUnits,
                    currencyCode: transaction.currencyCode,
                    type: transaction.type.rawValue,
                    category: transaction.category.rawValue,
                    paymentMethod: transaction.paymentMethod?.rawValue,
                    createdByMemberID: transaction.createdByMemberId.uuidString,
                    needsSync: transaction.needsSync,
                    splits: transaction.splits.map { split in
                        LegacyRecoverySplitRecord(
                            id: split.id.uuidString,
                            memberID: split.memberId.uuidString,
                            amount: split.amount,
                            amountMinorUnits: split.amountMinorUnits,
                            currencyCode: split.currencyCode
                        )
                    }.sorted { $0.id < $1.id }
                )
            }.sorted { $0.id < $1.id },
            settlements: persistedSettlements.map { settlement in
                LegacyRecoverySettlementRecord(
                    id: settlement.id.uuidString,
                    fromMemberID: settlement.fromMemberId.uuidString,
                    toMemberID: settlement.toMemberId.uuidString,
                    amount: settlement.amount,
                    amountMinorUnits: settlement.amountMinorUnits,
                    currencyCode: settlement.currencyCode,
                    needsSync: settlement.needsSync
                )
            }.sorted { $0.id < $1.id }
        )
    }

    private func createMigratedArchive(
        for descriptor: PersistenceStoreDescriptor,
        sourceArtifactFingerprint: String,
        sidecar: PersistenceLegacyMetadataSidecar,
        sidecarURL: URL,
        sidecarTarget: String,
        snapshot: PersistenceStoreSnapshot,
        reason: String,
        failureCode: String
    ) throws -> PersistenceArchiveResult {
        let storeArtifacts = try collectArtifacts(for: descriptor).filter {
            $0.targetRelativePath != sidecarTarget
        }
        let sidecarArtifact = PersistenceArchiveArtifact(
            sourceURL: sidecarURL,
            targetRelativePath: sidecarTarget,
            kind: "companion"
        )
        let artifacts = storeArtifacts + [sidecarArtifact]
        try makeProtectedDirectory(archiveDirectory)
        let archiveName = "BudgetMate-" + String(Int(Date().timeIntervalSince1970)) + "-" + UUID().uuidString + ".budgetmatearchive"
        let temporaryArchive = archiveDirectory.appendingPathComponent(
            "." + archiveName + ".partial",
            isDirectory: true
        )
        let finalArchive = archiveDirectory.appendingPathComponent(archiveName, isDirectory: true)
        try? fileManager.removeItem(at: temporaryArchive)
        defer { try? fileManager.removeItem(at: temporaryArchive) }
        try makeProtectedDirectory(temporaryArchive)
        let payloadDirectory = temporaryArchive.appendingPathComponent("payload", isDirectory: true)
        try makeProtectedDirectory(payloadDirectory)

        for artifact in artifacts {
            guard try !isSymbolicLink(artifact.sourceURL) else {
                throw PersistenceRecoveryError.fileSystemFailure
            }
            let destination = payloadDirectory.appendingPathComponent(
                artifact.targetRelativePath,
                isDirectory: false
            )
            try makeProtectedDirectory(destination.deletingLastPathComponent())
            try fileManager.copyItem(at: artifact.sourceURL, to: destination)
            try protectTree(at: destination)
        }

        let primary = try requirePrimary(in: storeArtifacts)
        let stagedSnapshot = try validateCurrentStore(at: primary.sourceURL)
        guard stagedSnapshot == snapshot else { throw PersistenceRecoveryError.storeValidationFailed }
        let manifestFiles = try artifacts.flatMap { artifact in
            try filesForManifest(
                at: payloadDirectory.appendingPathComponent(artifact.targetRelativePath),
                targetRelativePath: artifact.targetRelativePath,
                kind: artifact.kind
            )
        }.sorted { lhs, rhs in
            if lhs.targetRelativePath == rhs.targetRelativePath {
                return lhs.relativePath < rhs.relativePath
            }
            return lhs.targetRelativePath < rhs.targetRelativePath
        }
        let pendingRowCount = sidecar.transactionRows.filter { $0.pendingMutationBytesBase64 != nil }.count
            + sidecar.settlementRows.filter { $0.pendingMutationBytesBase64 != nil }.count
        let legacyStatus = PersistenceLegacyMetadataStatus(
            formatVersion: sidecar.formatVersion,
            sidecarTargetRelativePath: sidecarTarget,
            sourceArtifactFingerprint: sourceArtifactFingerprint,
            sourceMetadataFingerprint: sidecar.sourceMetadataFingerprint,
            transactionRowCount: sidecar.transactionRows.count,
            settlementRowCount: sidecar.settlementRows.count,
            pendingRowCount: pendingRowCount,
            requiresManualReview: pendingRowCount > 0 && sidecar.reviewedResolution == nil,
            cloudRowVersionMapping: sidecar.mappedCloudRowVersionSemantics,
            pendingMutationMapping: sidecar.pendingMutationSemantics,
            reviewedResolution: sidecar.reviewedResolution
        )
        let manifest = PersistenceArchiveManifest(
            archiveFormatVersion: Self.archiveFormatVersion,
            schemaVersion: BudgetMateSchema.currentVersionString,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            createdAt: .now,
            reason: sanitizedReason(reason),
            sourceOpenStatus: "verified",
            sourceStoreFilename: descriptor.storeURL.lastPathComponent,
            sourceArtifactFingerprint: sourceArtifactFingerprint,
            files: manifestFiles,
            snapshot: snapshot,
            sanitizedDiagnostics: PersistenceSanitizedDiagnostics(
                operation: "legacy-schema3-recovery",
                failureCode: sanitizedReason(failureCode),
                storeFilename: descriptor.storeURL.lastPathComponent,
                message: pendingRowCount == 0
                    ? "Legacy metadata was reconciled on an isolated staged copy."
                    : sidecar.reviewedResolution == nil
                        ? "Legacy pending metadata was preserved opaquely; restore is blocked pending review."
                        : "Legacy pending metadata was preserved opaquely; reviewed restore will assign a fresh Gate C mutation ID on sync."
            ),
            legacyMetadataStatus: legacyStatus
        )
        try writeJSON(manifest, to: temporaryArchive.appendingPathComponent("manifest.json"))
        try writeJSON(
            manifest.sanitizedDiagnostics,
            to: temporaryArchive.appendingPathComponent("diagnostics.json")
        )
        try protectTree(at: temporaryArchive)
        try fileManager.moveItem(at: temporaryArchive, to: finalArchive)
        return PersistenceArchiveResult(
            archiveURL: finalArchive,
            manifest: manifest,
            isRestorable: !legacyStatus.requiresManualReview
        )
    }

    func restoreArchive(
        at archiveURL: URL,
        to descriptor: PersistenceStoreDescriptor
    ) throws -> PersistenceArchiveVerification {
        guard !descriptor.isStoredInMemoryOnly else { throw PersistenceRecoveryError.notFileBacked }
        let verification = try verifyArchive(at: archiveURL)
        guard verification.manifest.legacyMetadataStatus?.requiresManualReview != true else {
            throw PersistenceRecoveryError.legacyMetadataReviewRequired
        }
        guard verification.manifest.sourceStoreFilename == descriptor.storeURL.lastPathComponent else {
            throw PersistenceRecoveryError.unsupportedArchive
        }

        let parent = descriptor.storeURL.deletingLastPathComponent()
        let stageDirectory = parent.appendingPathComponent(
            ".budgetmate-restore-" + UUID().uuidString,
            isDirectory: true
        )
        try makeProtectedDirectory(stageDirectory)
        defer { try? fileManager.removeItem(at: stageDirectory) }

        for file in verification.manifest.files {
            let source = archiveURL.appendingPathComponent(file.relativePath)
            let destination = stageDirectory.appendingPathComponent(file.targetRelativePath)
            try makeProtectedDirectory(destination.deletingLastPathComponent())
            try fileManager.copyItem(at: source, to: destination)
            try protectTree(at: destination)
        }

        let stagedPrimary = stageDirectory.appendingPathComponent(descriptor.storeURL.lastPathComponent)
        guard let stagedSnapshot = try? validateStore(
            at: stagedPrimary,
            schemaVersion: verification.manifest.schemaVersion
        ),
              stagedSnapshot == verification.snapshot else {
            throw PersistenceRecoveryError.storeValidationFailed
        }

        try replaceFiles(
            stagedDirectory: stageDirectory,
            targetDirectory: parent,
            descriptor: descriptor,
            newTargets: verification.manifest.files.map(\.targetRelativePath),
            expectedSnapshot: verification.snapshot,
            schemaVersion: verification.manifest.schemaVersion
        )
        return verification
    }

    func resetLocalCache(
        for descriptor: PersistenceStoreDescriptor,
        requiringVerifiedArchive archiveURL: URL
    ) throws {
        guard !descriptor.isStoredInMemoryOnly else { throw PersistenceRecoveryError.notFileBacked }
        let verification = try verifyArchive(at: archiveURL)
        guard verification.manifest.legacyMetadataStatus?.requiresManualReview != true else {
            throw PersistenceRecoveryError.legacyMetadataReviewRequired
        }
        let currentArtifacts = try collectArtifacts(for: descriptor)
        let currentFingerprint = try artifactFingerprint(for: currentArtifacts)
        guard currentFingerprint == verification.manifest.sourceArtifactFingerprint else {
            throw PersistenceRecoveryError.archiveNotCurrent
        }

        let parent = descriptor.storeURL.deletingLastPathComponent()
        let stageDirectory = parent.appendingPathComponent(
            ".budgetmate-reset-" + UUID().uuidString,
            isDirectory: true
        )
        try makeProtectedDirectory(stageDirectory)
        defer { try? fileManager.removeItem(at: stageDirectory) }
        let stagedStore = stageDirectory.appendingPathComponent(descriptor.storeURL.lastPathComponent)

        do {
            let configuration = ModelConfiguration(
                "BudgetMateReset",
                schema: BudgetMateSchema.current,
                url: stagedStore,
                cloudKitDatabase: .none
            )
            let emptyContainer = try ModelContainer(
                for: BudgetMateSchema.current,
                migrationPlan: BudgetMateSchemaMigrationPlan.self,
                configurations: [configuration]
            )
            try emptyContainer.mainContext.save()
        } catch {
            throw PersistenceRecoveryError.storeValidationFailed
        }

        guard let emptySnapshot = try? validateStore(at: stagedStore),
              emptySnapshot.transactionCount == 0,
              emptySnapshot.splitCount == 0,
              emptySnapshot.settlementCount == 0 else {
            throw PersistenceRecoveryError.storeValidationFailed
        }

        try replaceFiles(
            stagedDirectory: stageDirectory,
            targetDirectory: parent,
            descriptor: descriptor,
            newTargets: [descriptor.storeURL.lastPathComponent],
            expectedSnapshot: emptySnapshot,
            schemaVersion: BudgetMateSchema.currentVersionString
        )
    }

    /// Replays only an explicitly journaled replacement. A validated journal
    /// is finalized; every earlier phase rolls back. No path is inferred from
    /// a missing sidecar or a directory scan.
    static func recoverInterruptedReplacement(for descriptor: PersistenceStoreDescriptor) throws {
        guard !descriptor.isStoredInMemoryOnly else { return }
        let fileManager = FileManager.default
        let journalURL = replacementJournalURL(for: descriptor)
        guard fileManager.fileExists(atPath: journalURL.path) else { return }
        guard (try? journalURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              let data = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(PersistenceReplacementJournal.self, from: data),
              journal.storeFilename == descriptor.storeURL.lastPathComponent,
              ["prepared", "oldArtifactsMoved", "newArtifactsMoved", "validated"].contains(journal.phase),
              isApprovedStageDirectoryName(journal.stageDirectoryName),
              isApprovedBackupDirectoryName(journal.backupDirectoryName),
              journal.oldTargets.count == Set(journal.oldTargets).count,
              journal.newTargets.count == Set(journal.newTargets).count,
              journal.oldTargets.allSatisfy({ isArtifactTarget($0, storeFilename: descriptor.storeURL.lastPathComponent) }),
              journal.newTargets.allSatisfy({ isArtifactTarget($0, storeFilename: descriptor.storeURL.lastPathComponent) }) else {
            throw PersistenceOpenFailure(
                descriptor: descriptor,
                reason: .interruptedRecovery
            )
        }

        let parent = descriptor.storeURL.deletingLastPathComponent()
        let backupDirectory = parent.appendingPathComponent(journal.backupDirectoryName, isDirectory: true)
        let stageDirectory = parent.appendingPathComponent(journal.stageDirectoryName, isDirectory: true)
        do {
            try validateJournalFileSystem(
                journal: journal,
                descriptor: descriptor,
                journalURL: journalURL,
                stageDirectory: stageDirectory,
                backupDirectory: backupDirectory,
                fileManager: fileManager
            )
        } catch {
            throw PersistenceOpenFailure(
                descriptor: descriptor,
                reason: .interruptedRecovery
            )
        }

        if journal.phase == "validated" {
            try? fileManager.removeItem(at: backupDirectory)
            try? fileManager.removeItem(at: stageDirectory)
            try? fileManager.removeItem(at: journalURL)
            return
        }

        if journal.phase != "prepared" {
            for target in journal.newTargets {
                let active = parent.appendingPathComponent(target)
                try? fileManager.removeItem(at: active)
            }
        }
        for target in journal.oldTargets {
            let backup = backupDirectory.appendingPathComponent(target)
            let active = parent.appendingPathComponent(target)
            if fileManager.fileExists(atPath: backup.path) {
                try? fileManager.removeItem(at: active)
                try fileManager.createDirectory(
                    at: active.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: backup, to: active)
            }
        }
        try? fileManager.removeItem(at: backupDirectory)
        try? fileManager.removeItem(at: stageDirectory)
        try fileManager.removeItem(at: journalURL)
    }

    private func replaceFiles(
        stagedDirectory: URL,
        targetDirectory: URL,
        descriptor: PersistenceStoreDescriptor,
        newTargets: [String],
        expectedSnapshot: PersistenceStoreSnapshot,
        schemaVersion: String
    ) throws {
        let oldArtifacts: [PersistenceArchiveArtifact]
        if fileManager.fileExists(atPath: descriptor.storeURL.path) {
            oldArtifacts = try collectArtifacts(for: descriptor)
        } else {
            let siblings = try fileManager.contentsOfDirectory(
                at: targetDirectory,
                includingPropertiesForKeys: nil
            )
            guard !siblings.contains(where: {
                Self.isArtifactTarget(
                    $0.lastPathComponent,
                    storeFilename: descriptor.storeURL.lastPathComponent
                )
            }) else {
                throw PersistenceRecoveryError.interruptedReplacement
            }
            oldArtifacts = []
        }
        let oldTargets = Array(Set(oldArtifacts.map(\.targetRelativePath))).sorted()
        let uniqueNewTargets = Array(Set(newTargets)).sorted()
        guard oldTargets.allSatisfy({ Self.isArtifactTarget($0, storeFilename: descriptor.storeURL.lastPathComponent) }),
              uniqueNewTargets.allSatisfy({ Self.isArtifactTarget($0, storeFilename: descriptor.storeURL.lastPathComponent) }) else {
            throw PersistenceRecoveryError.unsupportedArchive
        }
        let backupName = ".budgetmate-rollback-" + UUID().uuidString
        let stageName = stagedDirectory.lastPathComponent
        let journalURL = Self.replacementJournalURL(for: descriptor)
        let backupDirectory = targetDirectory.appendingPathComponent(backupName, isDirectory: true)
        var journal = PersistenceReplacementJournal(
            phase: "prepared",
            storeFilename: descriptor.storeURL.lastPathComponent,
            stageDirectoryName: stageName,
            backupDirectoryName: backupName,
            oldTargets: oldTargets,
            newTargets: uniqueNewTargets
        )

        try writeJournal(journal, to: journalURL)
        do {
            try makeProtectedDirectory(backupDirectory)
            for target in oldTargets {
                let active = targetDirectory.appendingPathComponent(target)
                guard fileManager.fileExists(atPath: active.path) else { continue }
                let backup = backupDirectory.appendingPathComponent(target)
                try makeProtectedDirectory(backup.deletingLastPathComponent())
                try fileManager.moveItem(at: active, to: backup)
            }
            journal.phase = "oldArtifactsMoved"
            try writeJournal(journal, to: journalURL)

            for target in uniqueNewTargets {
                let staged = stagedDirectory.appendingPathComponent(target)
                guard fileManager.fileExists(atPath: staged.path) else {
                    throw PersistenceRecoveryError.incompleteArchive
                }
                let active = targetDirectory.appendingPathComponent(target)
                try makeProtectedDirectory(active.deletingLastPathComponent())
                try fileManager.moveItem(at: staged, to: active)
            }
            journal.phase = "newArtifactsMoved"
            try writeJournal(journal, to: journalURL)

            guard let actual = try? validateStore(
                at: descriptor.storeURL,
                schemaVersion: schemaVersion
            ), actual == expectedSnapshot else {
                throw PersistenceRecoveryError.storeValidationFailed
            }
            journal.phase = "validated"
            try writeJournal(journal, to: journalURL)
            try? fileManager.removeItem(at: backupDirectory)
            try? fileManager.removeItem(at: stagedDirectory)
            // The replacement is already validated. Cleanup is best effort;
            // a retained validated journal is finalized on the next launch
            // and must never trigger rollback of the new valid store.
            try? fileManager.removeItem(at: journalURL)
        } catch {
            try? rollback(journal: journal, targetDirectory: targetDirectory, journalURL: journalURL)
            try? fileManager.removeItem(at: stagedDirectory)
            if let recoveryError = error as? PersistenceRecoveryError {
                throw recoveryError
            }
            throw PersistenceRecoveryError.fileSystemFailure
        }
    }

    private func rollback(
        journal: PersistenceReplacementJournal,
        targetDirectory: URL,
        journalURL: URL
    ) throws {
        let backupDirectory = targetDirectory.appendingPathComponent(journal.backupDirectoryName, isDirectory: true)
        if journal.phase != "prepared" {
            guard journal.oldTargets.allSatisfy({
                fileManager.fileExists(
                    atPath: backupDirectory.appendingPathComponent($0).path
                )
            }) else {
                throw PersistenceRecoveryError.interruptedReplacement
            }
        }
        if journal.phase != "prepared" {
            for target in journal.newTargets {
                try? fileManager.removeItem(at: targetDirectory.appendingPathComponent(target))
            }
        }
        for target in journal.oldTargets {
            let backup = backupDirectory.appendingPathComponent(target)
            let active = targetDirectory.appendingPathComponent(target)
            if fileManager.fileExists(atPath: backup.path) {
                try? fileManager.removeItem(at: active)
                try fileManager.createDirectory(
                    at: active.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: backup, to: active)
            }
        }
        try? fileManager.removeItem(at: backupDirectory)
        try? fileManager.removeItem(at: journalURL)
    }

    private func collectArtifacts(for descriptor: PersistenceStoreDescriptor) throws -> [PersistenceArchiveArtifact] {
        let primary = descriptor.storeURL
        guard fileManager.fileExists(atPath: primary.path) else { throw PersistenceRecoveryError.storeMissing }
        guard !(try isSymbolicLink(primary)) else { throw PersistenceRecoveryError.fileSystemFailure }

        var artifacts = [PersistenceArchiveArtifact(
            sourceURL: primary,
            targetRelativePath: primary.lastPathComponent,
            kind: "primary"
        )]
        let parent = primary.deletingLastPathComponent()
        let sidecarNames = [
            primary.lastPathComponent + "-wal",
            primary.lastPathComponent + "-shm",
            primary.lastPathComponent + "-journal"
        ]
        for name in sidecarNames {
            let url = parent.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                guard !(try isSymbolicLink(url)) else { throw PersistenceRecoveryError.fileSystemFailure }
                artifacts.append(PersistenceArchiveArtifact(
                    sourceURL: url,
                    targetRelativePath: name,
                    kind: "sidecar"
                ))
            }
        }

        let stem = primary.deletingPathExtension().lastPathComponent
        let children = try fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        for child in children {
            let name = child.lastPathComponent
            let isRelatedCompanion = name.hasPrefix(primary.lastPathComponent + "-")
                || name.hasPrefix(primary.lastPathComponent + ".")
                || name.hasPrefix(stem + "-")
                || name.hasPrefix(stem + ".support")
            guard child != primary,
                  !sidecarNames.contains(name),
                  isRelatedCompanion else {
                continue
            }
            guard !(try isSymbolicLink(child)) else { throw PersistenceRecoveryError.fileSystemFailure }
            try appendArtifactFiles(
                at: child,
                targetRelativePath: name,
                kind: "companion",
                into: &artifacts
            )
        }
        return artifacts
    }

    private func appendArtifactFiles(
        at url: URL,
        targetRelativePath: String,
        kind: String,
        into artifacts: inout [PersistenceArchiveArtifact]
    ) throws {
        guard !(try isSymbolicLink(url)) else { throw PersistenceRecoveryError.fileSystemFailure }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            let children = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
            for child in children {
                try appendArtifactFiles(
                    at: child,
                    targetRelativePath: targetRelativePath + "/" + child.lastPathComponent,
                    kind: kind,
                    into: &artifacts
                )
            }
        } else {
            artifacts.append(PersistenceArchiveArtifact(
                sourceURL: url,
                targetRelativePath: targetRelativePath,
                kind: kind
            ))
        }
    }

    private func filesForManifest(
        at url: URL,
        targetRelativePath: String,
        kind: String
    ) throws -> [PersistenceArchiveFile] {
        guard fileManager.fileExists(atPath: url.path) else { throw PersistenceRecoveryError.incompleteArchive }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            let children = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            return try children.flatMap { child in
                try filesForManifest(
                    at: child,
                    targetRelativePath: targetRelativePath + "/" + child.lastPathComponent,
                    kind: kind
                )
            }
        }
        let relative = "payload/" + targetRelativePath
        let fileMetadata = try fileSizeAndSHA256(at: url)
        return [PersistenceArchiveFile(
            relativePath: relative,
            targetRelativePath: targetRelativePath,
            originalFilename: url.lastPathComponent,
            kind: kind,
            byteSize: fileMetadata.byteSize,
            sha256: fileMetadata.sha256
        )]
    }

    private func artifactFingerprint(
        for artifacts: [PersistenceArchiveArtifact]
    ) throws -> String {
        let files = try artifacts.flatMap { artifact in
            try filesForManifest(
                at: artifact.sourceURL,
                targetRelativePath: artifact.targetRelativePath,
                kind: artifact.kind
            )
        }
        return Self.artifactFingerprint(files)
    }

    private func validateArchivePackage(at archiveURL: URL) throws -> PersistenceArchiveManifest {
        guard fileManager.fileExists(atPath: archiveURL.path),
              archiveURL.pathExtension == "budgetmatearchive",
              !(try isSymbolicLink(archiveURL)) else {
            throw PersistenceRecoveryError.invalidArchive
        }
        let rootValues = try archiveURL.resourceValues(forKeys: [.isDirectoryKey])
        guard rootValues.isDirectory == true else { throw PersistenceRecoveryError.invalidArchive }

        let rootNames = try Set(fileManager.contentsOfDirectory(at: archiveURL, includingPropertiesForKeys: nil).map(\.lastPathComponent))
        guard rootNames == Set(["manifest.json", "diagnostics.json", "payload"]) else {
            throw PersistenceRecoveryError.unsupportedArchive
        }
        let manifestURL = archiveURL.appendingPathComponent("manifest.json")
        let diagnosticsURL = archiveURL.appendingPathComponent("diagnostics.json")
        let payloadURL = archiveURL.appendingPathComponent("payload", isDirectory: true)
        guard !(try isSymbolicLink(manifestURL)),
              !(try isSymbolicLink(diagnosticsURL)),
              !(try isSymbolicLink(payloadURL)) else {
            throw PersistenceRecoveryError.invalidArchive
        }
        let manifest = try JSONDecoder.budgetMateDecoder.decode(
            PersistenceArchiveManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.archiveFormatVersion == Self.archiveFormatVersion,
              ["1.0.0", BudgetMateSchema.currentVersionString].contains(manifest.schemaVersion),
              !manifest.files.isEmpty,
              manifest.files.filter({ $0.kind == "primary" }).count == 1 else {
            throw PersistenceRecoveryError.unsupportedArchive
        }
        let diagnostics = try JSONDecoder.budgetMateDecoder.decode(
            PersistenceSanitizedDiagnostics.self,
            from: Data(contentsOf: diagnosticsURL)
        )
        guard diagnostics == manifest.sanitizedDiagnostics,
              manifest.sourceOpenStatus == "verified" || manifest.sourceOpenStatus == "unverified" else {
            throw PersistenceRecoveryError.invalidArchive
        }

        var actualPayloadFiles = Set<String>()
        let enumerator = fileManager.enumerator(
            at: payloadURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        while let item = enumerator?.nextObject() as? URL {
            guard !(try isSymbolicLink(item)) else { throw PersistenceRecoveryError.invalidArchive }
            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory != true {
                actualPayloadFiles.insert(relativePath(of: item, from: archiveURL))
            }
        }

        var manifestPaths = Set<String>()
        for file in manifest.files {
            guard Self.safeRelativePath(file.relativePath),
                  Self.safeRelativePath(file.targetRelativePath),
                  file.relativePath.hasPrefix("payload/"),
                  Self.isArtifactTarget(
                      file.targetRelativePath,
                      storeFilename: manifest.sourceStoreFilename
                  ),
                  ["primary", "sidecar", "companion"].contains(file.kind),
                  !file.targetRelativePath.isEmpty,
                  file.byteSize >= 0,
                  manifestPaths.insert(file.relativePath).inserted else {
                throw PersistenceRecoveryError.invalidArchive
            }
            let actualURL = archiveURL.appendingPathComponent(file.relativePath)
            guard fileManager.fileExists(atPath: actualURL.path),
                  !(try isSymbolicLink(actualURL)),
                  actualURL.lastPathComponent == file.originalFilename else {
                throw PersistenceRecoveryError.incompleteArchive
            }
            let fileMetadata = try fileSizeAndSHA256(at: actualURL)
            guard fileMetadata.byteSize == file.byteSize,
                  fileMetadata.sha256 == file.sha256 else {
                throw PersistenceRecoveryError.checksumMismatch
            }
        }
        guard actualPayloadFiles == manifestPaths else {
            throw PersistenceRecoveryError.incompleteArchive
        }
        guard let primary = manifest.files.first(where: { $0.kind == "primary" }),
              primary.targetRelativePath == manifest.sourceStoreFilename,
              Self.isSHA256Hex(manifest.sourceArtifactFingerprint) else {
            throw PersistenceRecoveryError.unsupportedArchive
        }
        return manifest
    }

    private func validateLegacyMetadataSidecarIfPresent(
        manifest: PersistenceArchiveManifest,
        archiveURL: URL
    ) throws {
        guard let status = manifest.legacyMetadataStatus else { return }
        guard status.formatVersion == 1,
              Self.safeRelativePath(status.sidecarTargetRelativePath),
              Self.isSHA256Hex(status.sourceArtifactFingerprint),
              status.transactionRowCount >= 0,
              status.settlementRowCount >= 0,
              status.pendingRowCount >= 0 else {
            throw PersistenceRecoveryError.invalidArchive
        }
        guard let sidecarFile = manifest.files.first(where: {
            $0.targetRelativePath == status.sidecarTargetRelativePath
        }), sidecarFile.kind == "companion" else {
            throw PersistenceRecoveryError.incompleteArchive
        }
        let sidecarURL = archiveURL.appendingPathComponent(sidecarFile.relativePath)
        let sidecar = try JSONDecoder.budgetMateDecoder.decode(
            PersistenceLegacyMetadataSidecar.self,
            from: Data(contentsOf: sidecarURL)
        )
        let allRows = sidecar.transactionRows + sidecar.settlementRows
        let ids = allRows.map(\.stableID)
        let pendingRows = allRows.filter { $0.pendingMutationBytesBase64 != nil }
        guard sidecar.formatVersion == status.formatVersion,
              sidecar.sourceArtifactFingerprint == status.sourceArtifactFingerprint,
              status.sourceMetadataFingerprint == nil
                  || status.sourceMetadataFingerprint == sidecar.sourceMetadataFingerprint,
              sidecar.sourceMetadataFingerprint == nil
                  || recoveryLegacyMetadataFingerprint(
                      transactionRows: sidecar.transactionRows,
                      settlementRows: sidecar.settlementRows
                  ) == sidecar.sourceMetadataFingerprint,
              sidecar.transactionRows.count == status.transactionRowCount,
              sidecar.settlementRows.count == status.settlementRowCount,
              pendingRows.count == status.pendingRowCount,
              status.requiresManualReview == (
                  !pendingRows.isEmpty && sidecar.reviewedResolution == nil
              ),
              status.reviewedResolution == sidecar.reviewedResolution,
              ids.count == Set(ids).count,
              allRows.allSatisfy({ row in
                  guard let pending = row.pendingMutationBytesBase64 else { return true }
                  return Data(base64Encoded: pending) != nil
              }) else {
            throw PersistenceRecoveryError.legacyMetadataMismatch
        }
        if let resolution = sidecar.reviewedResolution {
            guard !pendingRows.isEmpty,
                  let sourceMetadataFingerprint = sidecar.sourceMetadataFingerprint,
                  resolution.decision == PersistenceLegacyMetadataResolution.retryWithFreshGateCMutationID,
                  resolution.sourceArtifactFingerprint == sidecar.sourceArtifactFingerprint,
                  resolution.sourceMetadataFingerprint == sourceMetadataFingerprint else {
                throw PersistenceRecoveryError.legacyMetadataMismatch
            }
        }
    }

    private func validateLegacyMetadataPayloadIfPresent(
        manifest: PersistenceArchiveManifest,
        archiveURL: URL,
        primaryURL: URL
    ) throws {
        guard let status = manifest.legacyMetadataStatus else { return }
        guard manifest.schemaVersion == BudgetMateSchema.currentVersionString,
              let sidecarFile = manifest.files.first(where: {
                  $0.targetRelativePath == status.sidecarTargetRelativePath
              }) else {
            throw PersistenceRecoveryError.legacyMetadataMismatch
        }
        let sidecar = try JSONDecoder.budgetMateDecoder.decode(
            PersistenceLegacyMetadataSidecar.self,
            from: Data(contentsOf: archiveURL.appendingPathComponent(sidecarFile.relativePath))
        )
        let configuration = ModelConfiguration(
            "BudgetMateLegacyArchiveValidation",
            schema: BudgetMateSchema.current,
            url: primaryURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: BudgetMateSchema.current,
            configurations: [configuration]
        )
        let context = container.mainContext
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let settlements = try context.fetch(FetchDescriptor<Settlement>())
        let transactionMetadata = Dictionary(
            uniqueKeysWithValues: sidecar.transactionRows.map { ($0.stableID, $0) }
        )
        let settlementMetadata = Dictionary(
            uniqueKeysWithValues: sidecar.settlementRows.map { ($0.stableID, $0) }
        )
        guard transactions.count == sidecar.transactionRows.count,
              settlements.count == sidecar.settlementRows.count else {
            throw PersistenceRecoveryError.legacyMetadataMismatch
        }
        for transaction in transactions {
            guard let row = transactionMetadata[transaction.id.uuidString] else {
                throw PersistenceRecoveryError.legacyMetadataMismatch
            }
            let expectedRowVersion = try normalizedRowVersion(
                for: row,
                reviewedResolution: sidecar.reviewedResolution
            )
            let expectedNeedsSync = try normalizedNeedsSync(
                for: row,
                reviewedResolution: sidecar.reviewedResolution
            )
            guard transaction.rowVersion == expectedRowVersion,
                  transaction.lastMutationId == nil,
                  transaction.needsSync == expectedNeedsSync else {
                throw PersistenceRecoveryError.legacyMetadataMismatch
            }
        }
        for settlement in settlements {
            guard let row = settlementMetadata[settlement.id.uuidString] else {
                throw PersistenceRecoveryError.legacyMetadataMismatch
            }
            let expectedRowVersion = try normalizedRowVersion(
                for: row,
                reviewedResolution: sidecar.reviewedResolution
            )
            let expectedNeedsSync = try normalizedNeedsSync(
                for: row,
                reviewedResolution: sidecar.reviewedResolution
            )
            guard settlement.rowVersion == expectedRowVersion,
                  settlement.lastMutationId == nil,
                  settlement.needsSync == expectedNeedsSync else {
                throw PersistenceRecoveryError.legacyMetadataMismatch
            }
        }
    }

    private func validateStore(
        at storeURL: URL,
        schemaVersion: String = BudgetMateSchema.currentVersionString
    ) throws -> PersistenceStoreSnapshot {
        if schemaVersion == Self.legacySchemaVersion {
            return try validateLegacyStoreOnIsolatedCopy(at: storeURL)
        }
        guard schemaVersion == BudgetMateSchema.currentVersionString else {
            throw PersistenceRecoveryError.unsupportedArchive
        }

        return try validateCurrentStore(at: storeURL)
    }

    private func validateCurrentStore(at storeURL: URL) throws -> PersistenceStoreSnapshot {
        let configuration = ModelConfiguration(
            "BudgetMateValidation",
            schema: BudgetMateSchema.current,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: BudgetMateSchema.current,
            migrationPlan: BudgetMateSchemaMigrationPlan.self,
            configurations: [configuration]
        )
        let context = container.mainContext
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let splits = try context.fetch(FetchDescriptor<TransactionSplit>())
        let settlements = try context.fetch(FetchDescriptor<Settlement>())
        let relationships = transactions
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { transaction in
                transaction.id.uuidString + ":" + transaction.splits.map(\.id.uuidString).sorted().joined(separator: ",")
            }
            + splits
                .filter { $0.transaction == nil }
                .map { "orphan:\($0.id.uuidString)" }
                .sorted()
        let digest = Self.sha256(Data(relationships.joined(separator: "|").utf8))
        return PersistenceStoreSnapshot(
            transactionCount: transactions.count,
            splitCount: splits.count,
            settlementCount: settlements.count,
            relationshipDigest: digest
        )
    }

    private func validateLegacyStoreOnIsolatedCopy(at storeURL: URL) throws -> PersistenceStoreSnapshot {
        let isolatedDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "BudgetMateV1Validation-" + UUID().uuidString,
            isDirectory: true
        )
        try fileManager.createDirectory(at: isolatedDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: isolatedDirectory) }

        let primaryName = storeURL.lastPathComponent
        let artifactNames = [
            primaryName,
            primaryName + "-wal",
            primaryName + "-shm",
            primaryName + "-journal"
        ]
        for artifactName in artifactNames {
            let source = storeURL.deletingLastPathComponent().appendingPathComponent(artifactName)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            guard try !isSymbolicLink(source) else {
                throw PersistenceRecoveryError.invalidArchive
            }
            try fileManager.copyItem(
                at: source,
                to: isolatedDirectory.appendingPathComponent(artifactName)
            )
        }

        return try validateLegacyStore(at: isolatedDirectory.appendingPathComponent(primaryName))
    }

    private func validateLegacyStore(at storeURL: URL) throws -> PersistenceStoreSnapshot {
        let schema = Schema(versionedSchema: BudgetMateSchemaV1.self)
        let configuration = ModelConfiguration(
            "BudgetMateLegacyValidation",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = container.mainContext
        let transactions = try context.fetch(
            FetchDescriptor<BudgetMateSchemaV1.Transaction>()
        )
        let splits = try context.fetch(
            FetchDescriptor<BudgetMateSchemaV1.TransactionSplit>()
        )
        let settlements = try context.fetch(
            FetchDescriptor<BudgetMateSchemaV1.Settlement>()
        )
        let relationships = transactions
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { transaction in
                transaction.id.uuidString + ":" + transaction.splits.map(\.id.uuidString).sorted().joined(separator: ",")
            }
            + splits
                .filter { $0.transaction == nil }
                .map { "orphan:\($0.id.uuidString)" }
                .sorted()
        let digest = Self.sha256(Data(relationships.joined(separator: "|").utf8))
        return PersistenceStoreSnapshot(
            transactionCount: transactions.count,
            splitCount: splits.count,
            settlementCount: settlements.count,
            relationshipDigest: digest
        )
    }

    private func requirePrimary(in artifacts: [PersistenceArchiveArtifact]) throws -> PersistenceArchiveArtifact {
        guard let primary = artifacts.first(where: { $0.kind == "primary" }) else {
            throw PersistenceRecoveryError.storeMissing
        }
        return primary
    }

    private func makeProtectedDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [
                .protectionKey: FileProtectionType.complete,
                .posixPermissions: NSNumber(value: 0o700)
            ],
            ofItemAtPath: url.path
        )
    }

    private func protectTree(at url: URL) throws {
        let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        try fileManager.setAttributes(
            [
                .protectionKey: FileProtectionType.complete,
                .posixPermissions: NSNumber(value: isDirectory ? 0o700 : 0o600)
            ],
            ofItemAtPath: url.path
        )
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        for case let child as URL in enumerator {
            let childIsDirectory = try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            try fileManager.setAttributes(
                [
                    .protectionKey: FileProtectionType.complete,
                    .posixPermissions: NSNumber(value: childIsDirectory ? 0o700 : 0o600)
                ],
                ofItemAtPath: child.path
            )
        }
    }

    private func isSymbolicLink(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
    }

    private func writeJournal(_ journal: PersistenceReplacementJournal, to url: URL) throws {
        let data = try JSONEncoder.budgetMateEncoder.encode(journal)
        try data.write(to: url, options: [.atomic])
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder.budgetMateEncoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private func fileSizeAndSHA256(at url: URL) throws -> (byteSize: Int64, sha256: String) {
        let handle = try FileHandle(forReadingFrom: url)
        var hasher = SHA256()
        var byteSize: Int64 = 0
        while true {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            byteSize += Int64(chunk.count)
        }
        try? handle.close()
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (byteSize, digest)
    }

    private func relativePath(of url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    private func sanitizedReason(_ value: String) -> String {
        let allowed = value.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "." }
        return String(allowed.prefix(160)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func artifactFingerprint(_ files: [PersistenceArchiveFile]) -> String {
        let canonical = files
            .sorted { lhs, rhs in
                if lhs.targetRelativePath == rhs.targetRelativePath {
                    return lhs.relativePath < rhs.relativePath
                }
                return lhs.targetRelativePath < rhs.targetRelativePath
            }
            .map { file in
                file.targetRelativePath + "|" + String(file.byteSize) + "|" + file.sha256
            }
            .joined(separator: "\n")
        return sha256(Data(canonical.utf8))
    }

    private static func isSHA256Hex(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private static func replacementJournalURL(for descriptor: PersistenceStoreDescriptor) -> URL {
        descriptor.storeURL.deletingLastPathComponent().appendingPathComponent(
            "." + descriptor.storeURL.lastPathComponent + replacementJournalSuffix
        )
    }

    static func journalURLForTesting(for descriptor: PersistenceStoreDescriptor) -> URL {
        replacementJournalURL(for: descriptor)
    }

    private static func isApprovedStageDirectoryName(_ value: String) -> Bool {
        hasUUIDSuffix(value, prefix: ".budgetmate-restore-")
            || hasUUIDSuffix(value, prefix: ".budgetmate-reset-")
    }

    private static func isApprovedBackupDirectoryName(_ value: String) -> Bool {
        hasUUIDSuffix(value, prefix: ".budgetmate-rollback-")
    }

    private static func hasUUIDSuffix(_ value: String, prefix: String) -> Bool {
        guard value.hasPrefix(prefix) else { return false }
        let suffix = String(value.dropFirst(prefix.count))
        guard suffix.count == 36, let uuid = UUID(uuidString: suffix) else { return false }
        return uuid.uuidString.caseInsensitiveCompare(suffix) == .orderedSame
    }

    private static func isArtifactTarget(_ target: String, storeFilename: String) -> Bool {
        guard safeRelativePath(target) else { return false }
        let components = target.split(separator: "/").map(String.init)
        guard let root = components.first else { return false }
        let sidecars = [
            storeFilename + "-wal",
            storeFilename + "-shm",
            storeFilename + "-journal"
        ]
        if components.count == 1, root == storeFilename || sidecars.contains(root) {
            return true
        }
        let stem = URL(fileURLWithPath: storeFilename).deletingPathExtension().lastPathComponent
        return root.hasPrefix(storeFilename + "-")
            || root.hasPrefix(storeFilename + ".")
            || root.hasPrefix(stem + "-")
            || root.hasPrefix(stem + ".support")
    }

    private static func validateJournalFileSystem(
        journal: PersistenceReplacementJournal,
        descriptor: PersistenceStoreDescriptor,
        journalURL: URL,
        stageDirectory: URL,
        backupDirectory: URL,
        fileManager: FileManager
    ) throws {
        guard !isSymbolicLink(journalURL) else { throw PersistenceRecoveryError.fileSystemFailure }
        for root in [stageDirectory, backupDirectory] {
            guard !isSymbolicLink(root) else { throw PersistenceRecoveryError.fileSystemFailure }
            guard fileManager.fileExists(atPath: root.path) else { continue }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: []
            ) else {
                throw PersistenceRecoveryError.fileSystemFailure
            }
            for case let child as URL in enumerator where isSymbolicLink(child) {
                throw PersistenceRecoveryError.fileSystemFailure
            }
        }

        let parent = descriptor.storeURL.deletingLastPathComponent()
        if journal.phase == "oldArtifactsMoved" || journal.phase == "newArtifactsMoved" {
            guard journal.oldTargets.allSatisfy({
                fileManager.fileExists(
                    atPath: backupDirectory.appendingPathComponent($0).path
                )
            }) else {
                throw PersistenceRecoveryError.interruptedReplacement
            }
        }
        let targets = Set(journal.oldTargets + journal.newTargets)
        for target in targets {
            let active = parent.appendingPathComponent(target)
            let backup = backupDirectory.appendingPathComponent(target)
            guard !isSymbolicLink(active), !isSymbolicLink(backup) else {
                throw PersistenceRecoveryError.fileSystemFailure
            }
        }
    }

    private static func safeRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.contains("\\") else { return false }
        let components = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}

private extension JSONEncoder {
    static var budgetMateEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var budgetMateDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private func recoveryLegacyMetadataFingerprint(
    transactionRows: [PersistenceLegacyMetadataRow],
    settlementRows: [PersistenceLegacyMetadataRow]
) -> String {
    let canonical = (transactionRows + settlementRows)
        .sorted { lhs, rhs in
            if lhs.stableID == rhs.stableID {
                return (lhs.pendingMutationBytesBase64 ?? "")
                    < (rhs.pendingMutationBytesBase64 ?? "")
            }
            return lhs.stableID < rhs.stableID
        }
        .map { row in
            [
                row.stableID,
                row.cloudRowVersion.map(String.init) ?? "null",
                row.pendingMutationBytesBase64 ?? "null",
                row.needsSync ? "1" : "0"
            ].joined(separator: "|")
        }
        .joined(separator: "\n")
    return recoverySHA256(Data(canonical.utf8))
}

private func recoverySHA256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

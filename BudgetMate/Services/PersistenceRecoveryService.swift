import CryptoKit
import Foundation
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

struct PersistenceReplacementJournal: Codable {
    var phase: String
    let storeFilename: String
    let stageDirectoryName: String
    let backupDirectoryName: String
    let oldTargets: [String]
    let newTargets: [String]
}

/// File-backed support archive and replacement boundary. It intentionally
/// knows only the immutable PR01A V1 schema; it does not touch UserDefaults,
/// cloud state, or application-level recovery settings.
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
            )
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

    func verifyArchive(at archiveURL: URL) throws -> PersistenceArchiveVerification {
        let manifest = try validateArchivePackage(at: archiveURL)
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

    func restoreArchive(
        at archiveURL: URL,
        to descriptor: PersistenceStoreDescriptor
    ) throws -> PersistenceArchiveVerification {
        guard !descriptor.isStoredInMemoryOnly else { throw PersistenceRecoveryError.notFileBacked }
        let verification = try verifyArchive(at: archiveURL)
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
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    private func protectTree(at url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        for case let child as URL in enumerator {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
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

import Foundation
import CryptoKit
import SwiftData
import XCTest
@testable import BudgetMate

@MainActor
final class PersistenceRecoveryTests: XCTestCase {
    private var testRoot: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("BudgetMatePR01BTests-" + UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: testRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let testRoot {
            try? fileManager.removeItem(at: testRoot)
        }
        try super.tearDownWithError()
    }

    func testVerifiedArchiveRoundTripsCountsRelationshipsAndChecksums() throws {
        let storeURL = try makeStore()
        let companionURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.lastPathComponent + "-support")
        try Data("support metadata".utf8).write(to: companionURL)
        let service = makeService()

        let result = try service.createSupportArchive(
            for: PersistenceController.descriptor(storeURL: storeURL),
            reason: "open failure / user requested support",
            failureCode: "test"
        )

        XCTAssertTrue(result.isRestorable)
        XCTAssertEqual(result.manifest.archiveFormatVersion, 1)
        XCTAssertEqual(result.manifest.schemaVersion, BudgetMateSchema.currentVersionString)
        XCTAssertEqual(result.manifest.sourceOpenStatus, "verified")
        XCTAssertTrue(result.manifest.files.contains { $0.kind == "primary" })
        XCTAssertTrue(result.manifest.files.contains { $0.kind == "companion" })
        let verification = try service.verifyArchive(at: result.archiveURL)
        XCTAssertEqual(verification.snapshot.transactionCount, 1)
        XCTAssertEqual(verification.snapshot.splitCount, 3)
        XCTAssertEqual(verification.snapshot.settlementCount, 1)
        XCTAssertFalse(verification.snapshot.relationshipDigest.isEmpty)

        try addTransaction(to: storeURL, title: "Temporary local edit")
        XCTAssertEqual(try snapshot(at: storeURL).transactionCount, 2)

        _ = try service.restoreArchive(
            at: result.archiveURL,
            to: PersistenceController.descriptor(storeURL: storeURL)
        )
        let restored = try snapshot(at: storeURL)
        XCTAssertEqual(restored, verification.snapshot)
    }

    func testV1ArchiveVerifyTwiceAndRestoreNeverMutatesArchiveChecksums() throws {
        let sourceDirectory = testRoot.appendingPathComponent("legacy-source", isDirectory: true)
        let targetDirectory = testRoot.appendingPathComponent("legacy-target", isDirectory: true)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let sourceStoreURL = sourceDirectory.appendingPathComponent("BudgetMate.store")
        try LegacyUnversionedStoreFixture.create(at: sourceStoreURL)

        let service = makeService()
        let legacyDescriptor = PersistenceStoreDescriptor(
            storeURL: sourceStoreURL,
            schemaVersion: "1.0.0"
        )
        let archive = try service.createSupportArchive(
            for: legacyDescriptor,
            reason: "legacy verification test",
            failureCode: "test"
        )
        XCTAssertTrue(archive.isRestorable)
        XCTAssertEqual(archive.manifest.schemaVersion, "1.0.0")

        let checksumsBefore = try archiveChecksums(
            at: archive.archiveURL,
            manifest: archive.manifest
        )
        let firstVerification = try service.verifyArchive(at: archive.archiveURL)
        XCTAssertEqual(firstVerification.snapshot.transactionCount, 2)
        XCTAssertEqual(firstVerification.snapshot.splitCount, 3)
        XCTAssertEqual(firstVerification.snapshot.settlementCount, 1)
        XCTAssertEqual(
            try archiveChecksums(at: archive.archiveURL, manifest: archive.manifest),
            checksumsBefore
        )

        let secondVerification = try service.verifyArchive(at: archive.archiveURL)
        XCTAssertEqual(secondVerification.manifest, firstVerification.manifest)
        XCTAssertEqual(secondVerification.snapshot, firstVerification.snapshot)
        XCTAssertEqual(
            try archiveChecksums(at: archive.archiveURL, manifest: archive.manifest),
            checksumsBefore
        )

        let restoredStoreURL = targetDirectory.appendingPathComponent("BudgetMate.store")
        let restored = try service.restoreArchive(
            at: archive.archiveURL,
            to: PersistenceStoreDescriptor(
                storeURL: restoredStoreURL,
                schemaVersion: "1.0.0"
            )
        )
        XCTAssertEqual(restored.manifest, firstVerification.manifest)
        XCTAssertEqual(restored.snapshot, firstVerification.snapshot)
        XCTAssertEqual(
            try service.verifyStoreForTesting(
                at: restoredStoreURL,
                schemaVersion: "1.0.0"
            ),
            firstVerification.snapshot
        )
        let primary = try XCTUnwrap(archive.manifest.files.first { $0.kind == "primary" })
        XCTAssertEqual(try sha256(at: restoredStoreURL), primary.sha256)
        XCTAssertEqual(
            try archiveChecksums(at: archive.archiveURL, manifest: archive.manifest),
            checksumsBefore
        )
    }

    func testCorruptArchiveIsRejectedBeforeActiveStoreChanges() throws {
        let storeURL = try makeStore()
        let descriptor = PersistenceController.descriptor(storeURL: storeURL)
        let service = makeService()
        let result = try service.createSupportArchive(
            for: descriptor,
            reason: "test",
            failureCode: "test"
        )
        let before = try Data(contentsOf: storeURL)
        let primary = try XCTUnwrap(result.manifest.files.first { $0.kind == "primary" })
        let payload = result.archiveURL.appendingPathComponent(primary.relativePath)
        var corrupted = try Data(contentsOf: payload)
        corrupted.append(0xFF)
        try corrupted.write(to: payload)

        XCTAssertThrowsError(try service.restoreArchive(at: result.archiveURL, to: descriptor))
        XCTAssertEqual(try Data(contentsOf: storeURL), before)
    }

    func testTraversalAndUnexpectedArchiveEntriesAreRejected() throws {
        let storeURL = try makeStore()
        let service = makeService()
        let result = try service.createSupportArchive(
            for: PersistenceController.descriptor(storeURL: storeURL),
            reason: "test",
            failureCode: "test"
        )

        let traversal = try copyArchive(result.archiveURL, named: "traversal")
        var traversalManifest = result.manifest
        let original = try XCTUnwrap(traversalManifest.files.first)
        let replacement = PersistenceArchiveFile(
            relativePath: "payload/../escape",
            targetRelativePath: original.targetRelativePath,
            originalFilename: original.originalFilename,
            kind: original.kind,
            byteSize: original.byteSize,
            sha256: original.sha256
        )
        var files = traversalManifest.files
        files[0] = replacement
        traversalManifest = PersistenceArchiveManifest(
            archiveFormatVersion: traversalManifest.archiveFormatVersion,
            schemaVersion: traversalManifest.schemaVersion,
            appVersion: traversalManifest.appVersion,
            appBuild: traversalManifest.appBuild,
            createdAt: traversalManifest.createdAt,
            reason: traversalManifest.reason,
            sourceOpenStatus: traversalManifest.sourceOpenStatus,
            sourceStoreFilename: traversalManifest.sourceStoreFilename,
            sourceArtifactFingerprint: traversalManifest.sourceArtifactFingerprint,
            files: files,
            snapshot: traversalManifest.snapshot,
            sanitizedDiagnostics: traversalManifest.sanitizedDiagnostics
        )
        try writeJSON(traversalManifest, to: traversal.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try service.verifyArchive(at: traversal))

        let unexpected = try copyArchive(result.archiveURL, named: "unexpected")
        try Data("unexpected".utf8).write(to: unexpected.appendingPathComponent("unexpected.txt"))
        XCTAssertThrowsError(try service.verifyArchive(at: unexpected))
    }

    func testSymlinkInsideArchiveIsRejected() throws {
        let storeURL = try makeStore()
        let service = makeService()
        let result = try service.createSupportArchive(
            for: PersistenceController.descriptor(storeURL: storeURL),
            reason: "test",
            failureCode: "test"
        )
        let symlinkArchive = try copyArchive(result.archiveURL, named: "symlink")
        let primary = try XCTUnwrap(result.manifest.files.first { $0.kind == "primary" })
        let target = symlinkArchive.appendingPathComponent(primary.relativePath)
        try fileManager.removeItem(at: target)
        try fileManager.createSymbolicLink(
            at: target,
            withDestinationURL: storeURL
        )
        XCTAssertThrowsError(try service.verifyArchive(at: symlinkArchive))
    }

    func testResetRequiresCurrentVerifiedArchive() throws {
        let storeURL = try makeStore()
        let descriptor = PersistenceController.descriptor(storeURL: storeURL)
        let service = makeService()
        let before = try snapshot(at: storeURL)
        let missingArchive = testRoot.appendingPathComponent("missing.budgetmatearchive")

        XCTAssertThrowsError(
            try service.resetLocalCache(
                for: descriptor,
                requiringVerifiedArchive: missingArchive
            )
        )
        XCTAssertEqual(try snapshot(at: storeURL), before)
    }

    func testVerifiedResetProducesEmptyStoreAndPreservesArchive() throws {
        let storeURL = try makeStore()
        let descriptor = PersistenceController.descriptor(storeURL: storeURL)
        let service = makeService()
        let archive = try service.createSupportArchive(
            for: descriptor,
            reason: "test",
            failureCode: "test"
        )

        try service.resetLocalCache(
            for: descriptor,
            requiringVerifiedArchive: archive.archiveURL
        )

        let empty = try snapshot(at: storeURL)
        XCTAssertEqual(empty.transactionCount, 0)
        XCTAssertEqual(empty.splitCount, 0)
        XCTAssertEqual(empty.settlementCount, 0)
        XCTAssertTrue(fileManager.fileExists(atPath: archive.archiveURL.path))
        XCTAssertEqual(try service.verifyArchive(at: archive.archiveURL).snapshot.transactionCount, 1)
    }

    func testResetRejectsStaleArchiveAfterCurrentStoreMutation() throws {
        let storeURL = try makeStore()
        let descriptor = PersistenceController.descriptor(storeURL: storeURL)
        let service = makeService()
        let archive = try service.createSupportArchive(
            for: descriptor,
            reason: "test",
            failureCode: "test"
        )

        try addTransaction(to: storeURL, title: "Changed after archive")
        let currentBytes = try Data(contentsOf: storeURL)
        let currentSnapshot = try snapshot(at: storeURL)

        XCTAssertThrowsError(
            try service.resetLocalCache(
                for: descriptor,
                requiringVerifiedArchive: archive.archiveURL
            )
        )
        XCTAssertEqual(try Data(contentsOf: storeURL), currentBytes)
        XCTAssertEqual(try snapshot(at: storeURL), currentSnapshot)
    }

    func testResetRejectsDifferentStoreWithSameFilename() throws {
        let firstDirectory = testRoot.appendingPathComponent("first", isDirectory: true)
        let secondDirectory = testRoot.appendingPathComponent("second", isDirectory: true)
        try fileManager.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let currentStoreURL = try makeStore(in: firstDirectory)
        let otherStoreURL = try makeStore(in: secondDirectory)
        try addTransaction(to: otherStoreURL, title: "Different store")

        let service = makeService()
        let archive = try service.createSupportArchive(
            for: PersistenceController.descriptor(storeURL: otherStoreURL),
            reason: "test",
            failureCode: "test"
        )
        let descriptor = PersistenceController.descriptor(storeURL: currentStoreURL)
        let currentBytes = try Data(contentsOf: currentStoreURL)

        XCTAssertThrowsError(
            try service.resetLocalCache(
                for: descriptor,
                requiringVerifiedArchive: archive.archiveURL
            )
        )
        XCTAssertEqual(try Data(contentsOf: currentStoreURL), currentBytes)
        XCTAssertEqual(try snapshot(at: currentStoreURL).transactionCount, 1)
    }

    func testJournalPhasesRecoverWithoutTouchingUnrelatedFiles() throws {
        let phases = ["prepared", "oldArtifactsMoved", "newArtifactsMoved", "validated"]
        for phase in phases {
            let phaseDirectory = testRoot.appendingPathComponent(phase, isDirectory: true)
            try fileManager.createDirectory(at: phaseDirectory, withIntermediateDirectories: true)
            let storeURL = try makeStore(in: phaseDirectory)
            let descriptor = PersistenceController.descriptor(storeURL: storeURL)
            let originalBytes = try Data(contentsOf: storeURL)
            let unrelatedURL = phaseDirectory.appendingPathComponent("unrelated.txt")
            let unrelatedBytes = Data("must remain untouched".utf8)
            try unrelatedBytes.write(to: unrelatedURL)

            let stageName = ".budgetmate-restore-" + UUID().uuidString
            let backupName = ".budgetmate-rollback-" + UUID().uuidString
            let stageDirectory = phaseDirectory.appendingPathComponent(stageName, isDirectory: true)
            let backupDirectory = phaseDirectory.appendingPathComponent(backupName, isDirectory: true)
            if phase != "prepared" {
                try fileManager.createDirectory(at: stageDirectory, withIntermediateDirectories: true)
                try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
                try fileManager.moveItem(
                    at: storeURL,
                    to: backupDirectory.appendingPathComponent(storeURL.lastPathComponent)
                )
                if phase == "newArtifactsMoved" || phase == "validated" {
                    try Data("new active bytes".utf8).write(to: storeURL)
                }
            }

            try writeJournal(
                PersistenceReplacementJournal(
                    phase: phase,
                    storeFilename: storeURL.lastPathComponent,
                    stageDirectoryName: stageName,
                    backupDirectoryName: backupName,
                    oldTargets: [storeURL.lastPathComponent],
                    newTargets: [storeURL.lastPathComponent]
                ),
                for: descriptor
            )

            try PersistenceRecoveryService.recoverInterruptedReplacement(for: descriptor)
            if phase == "validated" {
                XCTAssertEqual(try Data(contentsOf: storeURL), Data("new active bytes".utf8))
            } else {
                XCTAssertEqual(try Data(contentsOf: storeURL), originalBytes)
            }
            XCTAssertEqual(try Data(contentsOf: unrelatedURL), unrelatedBytes)
            XCTAssertFalse(fileManager.fileExists(atPath: PersistenceRecoveryService.journalURLForTesting(for: descriptor).path))
        }
    }

    func testTamperedJournalRejectsMalformedNamesAndTargetsBeforeMutation() throws {
        let cases = [
            (
                stage: ".budgetmate-evil-" + UUID().uuidString,
                backup: ".budgetmate-rollback-" + UUID().uuidString,
                target: "BudgetMate.store"
            ),
            (
                stage: ".budgetmate-restore-" + UUID().uuidString,
                backup: ".budgetmate-evil-" + UUID().uuidString,
                target: "BudgetMate.store"
            ),
            (
                stage: ".budgetmate-restore-" + UUID().uuidString,
                backup: ".budgetmate-rollback-" + UUID().uuidString,
                target: "unrelated.txt"
            ),
            (
                stage: ".budgetmate-restore-" + UUID().uuidString,
                backup: ".budgetmate-rollback-" + UUID().uuidString,
                target: "../unrelated.txt"
            )
        ]
        for (index, item) in cases.enumerated() {
            let caseDirectory = testRoot.appendingPathComponent("tampered-\(index)", isDirectory: true)
            try fileManager.createDirectory(at: caseDirectory, withIntermediateDirectories: true)
            let storeURL = try makeStore(in: caseDirectory)
            let descriptor = PersistenceController.descriptor(storeURL: storeURL)
            let originalBytes = try Data(contentsOf: storeURL)
            let unrelatedURL = caseDirectory.appendingPathComponent("unrelated.txt")
            let unrelatedBytes = Data("unrelated".utf8)
            try unrelatedBytes.write(to: unrelatedURL)

            try writeJournal(
                PersistenceReplacementJournal(
                    phase: "prepared",
                    storeFilename: storeURL.lastPathComponent,
                    stageDirectoryName: item.stage,
                    backupDirectoryName: item.backup,
                    oldTargets: [item.target],
                    newTargets: [item.target]
                ),
                for: descriptor
            )

            XCTAssertThrowsError(try PersistenceRecoveryService.recoverInterruptedReplacement(for: descriptor))
            XCTAssertEqual(try Data(contentsOf: storeURL), originalBytes)
            XCTAssertEqual(try Data(contentsOf: unrelatedURL), unrelatedBytes)
            XCTAssertTrue(fileManager.fileExists(atPath: PersistenceRecoveryService.journalURLForTesting(for: descriptor).path))
        }
    }

    func testJournalRecoveryRejectsMissingBackupsBeforeMutation() throws {
        for phase in ["oldArtifactsMoved", "newArtifactsMoved"] {
            let directory = testRoot.appendingPathComponent("missing-backup-" + phase, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let storeURL = directory.appendingPathComponent("BudgetMate.store")
            let activeBytes = Data(("active-" + phase).utf8)
            try activeBytes.write(to: storeURL)
            let unrelatedURL = directory.appendingPathComponent("unrelated.txt")
            let unrelatedBytes = Data("leave me alone".utf8)
            try unrelatedBytes.write(to: unrelatedURL)
            let descriptor = PersistenceController.descriptor(storeURL: storeURL)
            let stageName = ".budgetmate-restore-" + UUID().uuidString
            let backupName = ".budgetmate-rollback-" + UUID().uuidString
            try fileManager.createDirectory(
                at: directory.appendingPathComponent(stageName),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: directory.appendingPathComponent(backupName),
                withIntermediateDirectories: true
            )
            try writeJournal(
                PersistenceReplacementJournal(
                    phase: phase,
                    storeFilename: storeURL.lastPathComponent,
                    stageDirectoryName: stageName,
                    backupDirectoryName: backupName,
                    oldTargets: [storeURL.lastPathComponent],
                    newTargets: [storeURL.lastPathComponent]
                ),
                for: descriptor
            )
            let journalURL = PersistenceRecoveryService.journalURLForTesting(for: descriptor)

            XCTAssertThrowsError(
                try PersistenceRecoveryService.recoverInterruptedReplacement(for: descriptor)
            )
            XCTAssertEqual(try Data(contentsOf: storeURL), activeBytes)
            XCTAssertEqual(try Data(contentsOf: unrelatedURL), unrelatedBytes)
            XCTAssertTrue(fileManager.fileExists(atPath: journalURL.path))
        }
    }

    func testRestoreRejectsOrphanedSidecarWhenPrimaryIsMissing() throws {
        let sourceDirectory = testRoot.appendingPathComponent("source", isDirectory: true)
        let targetDirectory = testRoot.appendingPathComponent("target", isDirectory: true)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let sourceStoreURL = try makeStore(in: sourceDirectory)
        let service = makeService()
        let archive = try service.createSupportArchive(
            for: PersistenceController.descriptor(storeURL: sourceStoreURL),
            reason: "test",
            failureCode: "test"
        )
        let targetStoreURL = targetDirectory.appendingPathComponent(sourceStoreURL.lastPathComponent)
        let sidecarURL = targetDirectory.appendingPathComponent(targetStoreURL.lastPathComponent + "-wal")
        let sidecarBytes = Data("orphaned sidecar".utf8)
        try sidecarBytes.write(to: sidecarURL)

        XCTAssertThrowsError(
            try service.restoreArchive(
                at: archive.archiveURL,
                to: PersistenceController.descriptor(storeURL: targetStoreURL)
            )
        )
        XCTAssertFalse(fileManager.fileExists(atPath: targetStoreURL.path))
        XCTAssertEqual(try Data(contentsOf: sidecarURL), sidecarBytes)
    }

    func testInjectedOpenFailureProducesFailedStateWithoutFatalError() throws {
        let storeURL = testRoot.appendingPathComponent("BudgetMate.store")
        let descriptor = PersistenceController.descriptor(storeURL: storeURL)
        let factory = ClosurePersistenceContainerFactory {
            throw PersistenceOpenFailure(
                descriptor: descriptor,
                reason: .injectedForTesting
            )
        }
        let coordinator = PersistenceStartupCoordinator(
            factory: factory,
            recoveryService: makeService()
        )

        guard case .failed(let context) = coordinator.state else {
            return XCTFail("Injected opening failure should be represented as failed state")
        }
        XCTAssertEqual(context.reason, .injectedForTesting)
        XCTAssertEqual(context.diagnostics.storeFilename, "BudgetMate.store")
        XCTAssertFalse(coordinator.isWorking)
    }

    private func makeService() -> PersistenceRecoveryService {
        PersistenceRecoveryService(
            fileManager: fileManager,
            archiveDirectory: testRoot.appendingPathComponent("archives", isDirectory: true)
        )
    }

    private func makeStore(in directory: URL? = nil) throws -> URL {
        let storeDirectory = directory ?? testRoot!
        try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let storeURL = storeDirectory.appendingPathComponent("BudgetMate.store")
        let persistence = try PersistenceController(storeURL: storeURL)
        let firstMember = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
        let secondMember = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
        let transaction = Transaction(
            id: UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!,
            title: "Groceries",
            amount: 42,
            type: .expense,
            category: .groceries,
            createdByMemberId: firstMember,
            ownerUserId: "local"
        )
        let firstSplit = TransactionSplit(
            id: UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!,
            memberId: firstMember,
            amount: 21,
            transaction: transaction
        )
        let secondSplit = TransactionSplit(
            id: UUID(uuidString: "C0000000-0000-0000-0000-000000000002")!,
            memberId: secondMember,
            amount: 21,
            transaction: transaction
        )
        transaction.splits = [firstSplit, secondSplit]
        let orphan = TransactionSplit(
            id: UUID(uuidString: "C0000000-0000-0000-0000-000000000003")!,
            memberId: firstMember,
            amount: 5,
            transaction: nil
        )
        let settlement = Settlement(
            id: UUID(uuidString: "D0000000-0000-0000-0000-000000000001")!,
            fromMemberId: secondMember,
            toMemberId: firstMember,
            amount: 10,
            ownerUserId: "local"
        )
        persistence.container.mainContext.insert(transaction)
        persistence.container.mainContext.insert(orphan)
        persistence.container.mainContext.insert(settlement)
        try persistence.container.mainContext.save()
        return storeURL
    }

    private func addTransaction(to storeURL: URL, title: String) throws {
        let persistence = try PersistenceController(storeURL: storeURL)
        persistence.container.mainContext.insert(Transaction(
            title: title,
            amount: 3,
            type: .expense,
            category: .food,
            createdByMemberId: UUID(),
            ownerUserId: "local"
        ))
        try persistence.container.mainContext.save()
    }

    private func snapshot(at storeURL: URL) throws -> PersistenceStoreSnapshot {
        let service = makeService()
        return try service.verifyStoreForTesting(at: storeURL)
    }

    private func copyArchive(_ source: URL, named name: String) throws -> URL {
        let destination = testRoot.appendingPathComponent(name + ".budgetmatearchive", isDirectory: true)
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: [.atomic])
    }

    private func writeJournal(
        _ journal: PersistenceReplacementJournal,
        for descriptor: PersistenceStoreDescriptor
    ) throws {
        try JSONEncoder().encode(journal).write(
            to: PersistenceRecoveryService.journalURLForTesting(for: descriptor),
            options: [.atomic]
        )
    }

    private func archiveChecksums(
        at archiveURL: URL,
        manifest: PersistenceArchiveManifest
    ) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: manifest.files.map { file in
            (
                file.relativePath,
                try sha256(at: archiveURL.appendingPathComponent(file.relativePath))
            )
        })
    }

    private func sha256(at url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

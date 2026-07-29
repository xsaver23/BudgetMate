import Combine
import Foundation

struct PersistenceFailureContext: Sendable {
    let descriptor: PersistenceStoreDescriptor
    let reason: PersistenceOpenFailureReason
    let diagnostics: PersistenceSanitizedDiagnostics

    init(failure: PersistenceOpenFailure) {
        descriptor = failure.descriptor
        reason = failure.reason
        diagnostics = PersistenceSanitizedDiagnostics(
            operation: "persistence-startup",
            failureCode: failure.reason.rawValue,
            storeFilename: failure.descriptor.storeURL.lastPathComponent,
            message: failure.localizedDescription
        )
    }
}

enum PersistenceStartupState {
    case opening
    case ready(PersistenceSession)
    case failed(PersistenceFailureContext)
}

@MainActor
final class PersistenceStartupCoordinator: ObservableObject {
    @Published private(set) var state: PersistenceStartupState = .opening
    @Published private(set) var isWorking = false
    @Published private(set) var feedbackMessage: String?
    @Published private(set) var latestArchiveURL: URL?
    @Published private(set) var verifiedArchiveURL: URL?

    private let factory: any PersistenceContainerFactory
    private let recoveryService: PersistenceRecoveryService

    init(
        factory: any PersistenceContainerFactory,
        recoveryService: PersistenceRecoveryService? = nil,
        startImmediately: Bool = true
    ) {
        self.factory = factory
        self.recoveryService = recoveryService ?? PersistenceRecoveryService()
        if startImmediately {
            open()
        }
    }

    var failureContext: PersistenceFailureContext? {
        guard case .failed(let context) = state else { return nil }
        return context
    }

    var readySession: PersistenceSession? {
        guard case .ready(let session) = state else { return nil }
        return session
    }

    func open() {
        guard !isWorking else { return }
        isWorking = true
        feedbackMessage = nil
        state = .opening
        do {
            let session = try factory.makeSession()
            state = .ready(session)
            verifiedArchiveURL = nil
        } catch let failure as PersistenceOpenFailure {
            state = .failed(PersistenceFailureContext(failure: failure))
        } catch {
            let descriptor = PersistenceController.descriptor()
            let failure = PersistenceOpenFailure(
                descriptor: descriptor,
                reason: .unknown
            )
            state = .failed(PersistenceFailureContext(failure: failure))
        }
        isWorking = false
    }

    func retry() {
        open()
    }

    func createSupportArchive() {
        guard let context = failureContext, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try recoveryService.createSupportArchive(
                for: context.descriptor,
                reason: "persistence startup failure",
                failureCode: context.reason.rawValue
            )
            latestArchiveURL = result.archiveURL
            verifiedArchiveURL = result.isRestorable ? result.archiveURL : nil
            feedbackMessage = result.isRestorable
                ? "Support archive created and verified."
                : "Support archive created, but it could not be verified for restore."
        } catch {
            feedbackMessage = sanitizedFeedback(for: error)
        }
    }

    func restoreArchive(at archiveURL: URL) {
        guard let context = failureContext, !isWorking else { return }
        isWorking = true
        feedbackMessage = nil
        do {
            _ = try recoveryService.restoreArchive(at: archiveURL, to: context.descriptor)
            isWorking = false
            open()
            if case .ready = state {
                feedbackMessage = "Local data restored successfully."
            }
        } catch {
            isWorking = false
            feedbackMessage = sanitizedFeedback(for: error)
        }
    }

    func resetLocalCache() {
        guard let context = failureContext,
              let verifiedArchiveURL,
              !isWorking else { return }
        isWorking = true
        feedbackMessage = nil
        do {
            try recoveryService.resetLocalCache(
                for: context.descriptor,
                requiringVerifiedArchive: verifiedArchiveURL
            )
            isWorking = false
            open()
            if case .ready = state {
                feedbackMessage = "Local cache reset. Your support archive and cloud data were preserved."
            }
        } catch {
            isWorking = false
            feedbackMessage = sanitizedFeedback(for: error)
        }
    }

    private func sanitizedFeedback(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "Recovery stopped safely. The current local data was left untouched."
    }
}

import Foundation
import OSLog
import Supabase

@MainActor
final class AuthSessionStore: ObservableObject {
    static let passwordResetConfirmation = "If an account matches that email, check your inbox for a password reset link."
    private static let passwordResetFailure = "We couldn't send a reset email right now. Please try again."

    @Published private(set) var isLoading = true
    @Published private(set) var isAuthenticated = false
    @Published private(set) var userId: String?
    @Published private(set) var userEmail: String?
    @Published private(set) var activeBudgetScopeId: String?
    @Published var errorMessage: String?

    private let client: SupabaseClient
    let configurationIssue: String?
    private let activeBudgetScopeKey = "budgetmate.activeBudgetScopeId"
    private var authStateRevision = 0
    private static let launchLogger = Logger(subsystem: "BudgetMate", category: "Launch")
    private static let launchSignposter = OSSignposter(subsystem: "BudgetMate", category: "Launch")

    init(
        client: SupabaseClient = SupabaseClientProvider.shared,
        isCloudConfigured: Bool = SupabaseConfig.isConfigured
    ) {
        self.client = client
        configurationIssue = isCloudConfigured ? nil : SupabaseConfig.userFacingConfigurationMessage

#if DEBUG
        // Synthetic UI tests own their in-memory session and must not restore
        // a developer's cached Supabase session or start a network request.
        if SyntheticUITestScenario.fromProcessArguments != nil {
            isLoading = false
            return
        }
#endif

        guard configurationIssue == nil else {
            isLoading = false
            return
        }

        Task {
            await restoreSession()
        }
    }

#if DEBUG
    init(syntheticUserId: String, email: String, budgetScopeId: String) {
        client = SupabaseClientProvider.shared
        configurationIssue = nil
        isLoading = false
        isAuthenticated = true
        userId = syntheticUserId
        userEmail = email
        activeBudgetScopeId = budgetScopeId
        errorMessage = nil
    }
#endif

    var currentUserScopeId: String {
        userId ?? "local"
    }

    var currentBudgetScopeId: String {
        activeBudgetScopeId ?? currentUserScopeId
    }

    var hasSelectedBudgetScope: Bool {
        activeBudgetScopeId != nil
    }

    func switchBudgetScope(to budgetScopeId: String) {
        activeBudgetScopeId = budgetScopeId
        if let userId {
            UserDefaults.standard.set(budgetScopeId, forKey: activeBudgetScopeKey(for: userId))
        }
    }

    func restoreSession() async {
        guard configurationIssue == nil else {
            isLoading = false
            return
        }
        if !isLoading {
            isLoading = true
        }
        let restoreRevision = authStateRevision
        // Apply any locally-persisted session immediately so the UI can render
        // from on-device data without waiting for a network token refresh.
        // Supabase's synchronous getter runs storage migrations, repeated
        // Keychain reads, and JSON decoding. Keep that cold-start work away
        // from UIKit's first-frame and keyboard initialization on the main
        // actor, then publish the result here.
        let cachedSessionReadStartedAt = ProcessInfo.processInfo.systemUptime
        let client = self.client
        let cachedSession = await Task.detached(priority: .userInitiated) {
            client.auth.currentSession
        }.value
        let cachedSessionReadDuration = ProcessInfo.processInfo.systemUptime - cachedSessionReadStartedAt
        Self.launchLogger.notice(
            "Cached auth session read finished after \(cachedSessionReadDuration, privacy: .public) seconds"
        )
        Self.launchSignposter.emitEvent("Cached Auth Session Read Finished")

        guard authStateRevision == restoreRevision else { return }
        if let cachedSession {
            apply(session: cachedSession)
        }
        isLoading = false

        do {
            let session = try await client.auth.session
            guard authStateRevision == restoreRevision else { return }
            apply(session: session)
        } catch {
            guard authStateRevision == restoreRevision else { return }
            // Only drop back to sign-in when there was no usable cached session.
            // With a cached session we keep the user on their local data (e.g.
            // an offline launch) and let background sync recover later.
            if cachedSession == nil {
                isAuthenticated = false
                userId = nil
                userEmail = nil
                activeBudgetScopeId = nil
            }
        }
    }

    func signIn(email: String, password: String) async {
        await runAuthAction {
            let session = try await client.auth.signIn(email: normalized(email), password: password)
            apply(session: session)
        }
    }

    func signUp(email: String, password: String) async {
        await runAuthAction {
            let response = try await client.auth.signUp(email: normalized(email), password: password)
            if let session = response.session {
                apply(session: session)
            } else {
                isAuthenticated = false
                userId = nil
                userEmail = normalized(email)
                errorMessage = "Check your email to finish creating your account."
            }
        }
    }

    func requestPasswordReset(email: String) async {
        await runAuthAction(failureMessage: Self.passwordResetFailure) {
            try await client.auth.resetPasswordForEmail(normalized(email))
            errorMessage = Self.passwordResetConfirmation
        }
    }

    func signOut() async {
        guard configurationIssue == nil else {
            errorMessage = configurationIssue
            return
        }
        guard !isLoading else { return }

        authStateRevision += 1
        let signedOutUserId = userId
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await client.auth.signOut()
            if client.auth.currentSession == nil {
                clearAuthenticatedState(for: signedOutUserId)
            } else {
                errorMessage = "Please try again."
            }
        } catch {
            // Supabase removes the local session before remote revocation. If
            // revocation fails, keep the local sign-out and explain what could
            // not be confirmed instead of leaving app state inconsistent.
            if client.auth.currentSession == nil {
                clearAuthenticatedState(for: signedOutUserId)
                errorMessage = "Signed out on this device, but remote sign-out could not be confirmed. \(friendlyMessage(for: error))"
            } else {
                errorMessage = friendlyMessage(for: error)
            }
        }
    }

    private func runAuthAction(
        failureMessage: String? = nil,
        _ action: () async throws -> Void
    ) async {
        guard configurationIssue == nil else {
            errorMessage = configurationIssue
            return
        }
        authStateRevision += 1
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await action()
        } catch {
            errorMessage = failureMessage ?? friendlyMessage(for: error)
        }
    }

    private func apply(session: Session) {
        let nextUserId = session.user.id.uuidString
        let nextUserEmail = session.user.email
        let nextBudgetScopeId = UserDefaults.standard.string(forKey: activeBudgetScopeKey(for: nextUserId))

        // Cached-session apply is followed by refreshed-session apply. Guard
        // identical assignments so the root Dashboard is not invalidated five
        // more times while the first interaction is beginning.
        if !isAuthenticated { isAuthenticated = true }
        if userId != nextUserId { userId = nextUserId }
        if userEmail != nextUserEmail { userEmail = nextUserEmail }
        if activeBudgetScopeId != nextBudgetScopeId { activeBudgetScopeId = nextBudgetScopeId }
        if errorMessage != nil { errorMessage = nil }
    }

    private func clearAuthenticatedState(for signedOutUserId: String?) {
        isAuthenticated = false
        userId = nil
        userEmail = nil
        activeBudgetScopeId = nil
        errorMessage = nil
        if let signedOutUserId {
            UserDefaults.standard.removeObject(forKey: activeBudgetScopeKey(for: signedOutUserId))
        }
    }

    private func activeBudgetScopeKey(for userId: String) -> String {
        "\(activeBudgetScopeKey).\(userId)"
    }

    private func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func friendlyMessage(for error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("invalid login") {
            return "That email and password do not match."
        }
        if message.localizedCaseInsensitiveContains("password") {
            return "Please check your password and try again."
        }
        if message.localizedCaseInsensitiveContains("network") {
            return "Network problem. Please try again."
        }
        return message
    }
}

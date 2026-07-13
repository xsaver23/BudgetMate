import Foundation
import OSLog
import Supabase

@MainActor
final class AuthSessionStore: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var isAuthenticated = false
    @Published private(set) var userId: String?
    @Published private(set) var userEmail: String?
    @Published private(set) var activeBudgetScopeId: String?
    @Published var errorMessage: String?

    private let client: SupabaseClient
    let configurationIssue: String?
    private let activeBudgetScopeKey = "budgetmate.activeBudgetScopeId"
    private static let launchLogger = Logger(subsystem: "BudgetMate", category: "Launch")
    private static let launchSignposter = OSSignposter(subsystem: "BudgetMate", category: "Launch")

    init(
        client: SupabaseClient = SupabaseClientProvider.shared,
        isCloudConfigured: Bool = SupabaseConfig.isConfigured
    ) {
        self.client = client
        configurationIssue = isCloudConfigured ? nil : SupabaseConfig.userFacingConfigurationMessage

        guard configurationIssue == nil else {
            isLoading = false
            return
        }

        Task {
            await restoreSession()
        }
    }

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
        defer {
            if isLoading {
                isLoading = false
            }
        }

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

        if let cachedSession {
            apply(session: cachedSession)
            if isLoading {
                isLoading = false
            }
        }

        do {
            let session = try await client.auth.session
            apply(session: session)
        } catch {
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

    func signOut() async {
        await runAuthAction {
            let signedOutUserId = userId
            try await client.auth.signOut()
            isAuthenticated = false
            userId = nil
            userEmail = nil
            activeBudgetScopeId = nil
            if let signedOutUserId {
                UserDefaults.standard.removeObject(forKey: activeBudgetScopeKey(for: signedOutUserId))
            }
        }
    }

    private func runAuthAction(_ action: () async throws -> Void) async {
        guard configurationIssue == nil else {
            errorMessage = configurationIssue
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await action()
        } catch {
            errorMessage = friendlyMessage(for: error)
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

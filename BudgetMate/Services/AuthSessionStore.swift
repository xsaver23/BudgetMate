import Foundation
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
    private let activeBudgetScopeKey = "budgetmate.activeBudgetScopeId"

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
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
        isLoading = true
        defer { isLoading = false }

        // Apply any locally-persisted session immediately so the UI can render
        // from on-device data without waiting for a network token refresh.
        let cachedSession = client.auth.currentSession
        if let cachedSession {
            apply(session: cachedSession)
            isLoading = false
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
        isAuthenticated = true
        userId = session.user.id.uuidString
        userEmail = session.user.email
        activeBudgetScopeId = UserDefaults.standard.string(forKey: activeBudgetScopeKey(for: session.user.id.uuidString))
        errorMessage = nil
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

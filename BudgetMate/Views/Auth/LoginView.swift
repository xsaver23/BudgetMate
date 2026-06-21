import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var validationMessage: String?
    @State private var isCreatingAccount = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
        case confirmPassword
    }

    private var canSubmit: Bool {
        guard email.contains("@"), password.count >= 6, !authStore.isLoading else { return false }
        return !isCreatingAccount || !confirmPassword.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    formCard
                    modeSwitch
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
            .background(AppTheme.background)
            .preferredColorScheme(settingsStore.settings.appearance.colorScheme)
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 74, height: 74)
                .background(AppTheme.brand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(spacing: 6) {
                Text(isCreatingAccount ? "Create your account" : "Welcome back")
                    .font(.roundedBold(28))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(isCreatingAccount ? "Start with a private account. Shared budgets come next." : "Sign in to continue to BudgetMate.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
    }

    private var formCard: some View {
        CardContainer {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .focused($focusedField, equals: .email)
                        .padding(12)
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    SecureField("", text: $password)
                        .textContentType(isCreatingAccount ? .newPassword : .password)
                        .focused($focusedField, equals: .password)
                        .padding(12)
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onChange(of: password) { _, _ in
                            updatePasswordMismatchMessage()
                        }
                }

                if isCreatingAccount {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                        SecureField("", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .confirmPassword)
                            .padding(12)
                            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .onChange(of: confirmPassword) { _, _ in
                                updatePasswordMismatchMessage()
                            }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.expense)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let message = authStore.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.localizedCaseInsensitiveContains("check your email") ? AppTheme.income : AppTheme.expense)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    submit()
                } label: {
                    HStack {
                        if authStore.isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isCreatingAccount ? "Create Account" : "Sign In")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.45)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modeSwitch: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCreatingAccount.toggle()
                authStore.errorMessage = nil
                validationMessage = nil
                confirmPassword = ""
            }
        } label: {
            Text(isCreatingAccount ? "Already have an account? Sign in" : "New here? Create an account")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.brand)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98, pressedOpacity: 0.82))
    }

    private func submit() {
        focusedField = nil
        validationMessage = nil
        guard validateForm() else { return }

        Task {
            if isCreatingAccount {
                await authStore.signUp(email: email, password: password)
            } else {
                await authStore.signIn(email: email, password: password)
            }
        }
    }

    private func validateForm() -> Bool {
        if !email.contains("@") {
            validationMessage = "Enter a valid email address."
            return false
        }

        if password.count < 6 {
            validationMessage = "Password must be at least 6 characters."
            return false
        }

        if isCreatingAccount && password != confirmPassword {
            validationMessage = "Passwords do not match."
            return false
        }

        return true
    }

    private func updatePasswordMismatchMessage() {
        guard isCreatingAccount else { return }

        if !password.isEmpty,
           !confirmPassword.isEmpty,
           password != confirmPassword {
            validationMessage = "Passwords do not match."
        } else if validationMessage == "Passwords do not match." {
            validationMessage = nil
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthSessionStore())
        .environmentObject(SettingsStore())
}

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
        guard authStore.configurationIssue == nil,
              Self.isValidEmail(email),
              !authStore.isLoading else { return false }
        if isCreatingAccount {
            return Self.isValidNewPassword(password) && password == confirmPassword
        }
        return password.count >= 6
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
                .background(AppTheme.brand, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(spacing: 6) {
                Text(isCreatingAccount ? "Create your account" : "Welcome back")
                    .font(.roundedBold(28))
                    .foregroundStyle(BudgetBeaverPalette.ink)

                Text(isCreatingAccount ? "Start with a private account. Shared budgets come next." : "Sign in to continue to BudgetMate.")
                    .font(.subheadline)
                    .foregroundStyle(BudgetBeaverPalette.wood)
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
                        .foregroundStyle(BudgetBeaverPalette.wood)
                    TextField("", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .email)
                        .onSubmit { focusedField = .password }
                        .padding(12)
                        .foregroundStyle(BudgetBeaverPalette.ink)
                        .tint(AppTheme.incomeText)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    focusedField == .email ? AppTheme.incomeText : AppTheme.surfaceStroke,
                                    lineWidth: focusedField == .email ? 2 : 1
                                )
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BudgetBeaverPalette.wood)
                    SecureField("", text: $password)
                        .textContentType(isCreatingAccount ? .newPassword : .password)
                        .submitLabel(isCreatingAccount ? .next : .done)
                        .focused($focusedField, equals: .password)
                        .onSubmit {
                            if isCreatingAccount {
                                focusedField = .confirmPassword
                            } else {
                                submit()
                            }
                        }
                        .padding(12)
                        .foregroundStyle(BudgetBeaverPalette.ink)
                        .tint(AppTheme.incomeText)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    focusedField == .password ? AppTheme.incomeText : AppTheme.surfaceStroke,
                                    lineWidth: focusedField == .password ? 2 : 1
                                )
                        }
                        .onChange(of: password) { _, _ in
                            updatePasswordMismatchMessage()
                        }
                }

                if !isCreatingAccount {
                    Button("Forgot password?") {
                        requestPasswordReset()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.incomeText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .buttonStyle(PressableButtonStyle(scale: 0.98, pressedOpacity: 0.82))
                    .disabled(authStore.isLoading)
                }

                if isCreatingAccount {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BudgetBeaverPalette.wood)
                        SecureField("", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .submitLabel(.done)
                            .focused($focusedField, equals: .confirmPassword)
                            .onSubmit { submit() }
                            .padding(12)
                            .foregroundStyle(BudgetBeaverPalette.ink)
                            .tint(AppTheme.incomeText)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(
                                        focusedField == .confirmPassword ? AppTheme.incomeText : AppTheme.surfaceStroke,
                                        lineWidth: focusedField == .confirmPassword ? 2 : 1
                                    )
                            }
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

                if let message = authStore.configurationIssue ?? authStore.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(
                            message == AuthSessionStore.passwordResetConfirmation ||
                                message.localizedCaseInsensitiveContains("check your email")
                                ? AppTheme.incomeText
                                : AppTheme.expenseText
                        )
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
                    .background(AppTheme.brand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                .foregroundStyle(AppTheme.incomeText)
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

    private func requestPasswordReset() {
        focusedField = nil
        validationMessage = nil
        guard Self.isValidEmail(email) else {
            validationMessage = "Enter a valid email address."
            focusedField = .email
            return
        }

        Task {
            await authStore.requestPasswordReset(email: email)
        }
    }

    private func validateForm() -> Bool {
        if !Self.isValidEmail(email) {
            validationMessage = "Enter a valid email address."
            return false
        }

        if isCreatingAccount && !Self.isValidNewPassword(password) {
            validationMessage = "Use at least 8 characters with a letter and a number."
            return false
        }

        if !isCreatingAccount && password.count < 6 {
            validationMessage = "Enter your password."
            return false
        }

        if isCreatingAccount && password != confirmPassword {
            validationMessage = "Passwords do not match."
            return false
        }

        return true
    }

    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isValidNewPassword(_ password: String) -> Bool {
        guard password.count >= 8 else { return false }
        let hasLetter = password.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
        let hasNumber = password.range(of: #"[0-9]"#, options: .regularExpression) != nil
        return hasLetter && hasNumber
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

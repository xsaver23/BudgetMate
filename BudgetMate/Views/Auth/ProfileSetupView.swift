import SwiftUI

struct ProfileSetupView: View {
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore
    @EnvironmentObject private var memberViewModel: MemberViewModel
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var displayName = ""
    @State private var validationMessage: String?
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        !trimmedName.isEmpty && !displayName.containsEmoji
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    formCard
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
            .background(AppTheme.background)
            .preferredColorScheme(settingsStore.settings.appearance.colorScheme)
            .task(id: memberViewModel.activeMember.id) {
                seedDisplayName()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 74, height: 74)
                .background(AppTheme.brand, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(spacing: 6) {
                Text("Create your profile")
                    .font(.roundedBold(28))
                    .foregroundStyle(BudgetBeaverPalette.ink)

                Text("This is how your name will appear in your budget.")
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
                if let email = authStore.userEmail {
                    HStack {
                        Text("Signed in as")
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Text(email)
                            .foregroundStyle(AppTheme.textPrimary)
                            .fontWeight(.bold)
                            .lineLimit(1)
                    }
                    .font(.subheadline)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BudgetBeaverPalette.wood)
                    TextField("", text: $displayName)
                        .textContentType(.name)
                        .focused($isNameFocused)
                        .padding(12)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .onChange(of: displayName) { _, value in
                            validationMessage = value.containsEmoji ? "Names can use letters, spaces, hyphens, and apostrophes, but not emoji." : nil
                        }
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.expense)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    continueToApp()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.brand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .buttonStyle(PressableButtonStyle(scale: 0.98, pressedOpacity: canContinue ? 0.92 : 1))
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.45)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func seedDisplayName() {
        guard displayName.isEmpty else { return }
        displayName = memberViewModel.activeMember.displayName
    }

    private func continueToApp() {
        guard canContinue else {
            validationMessage = displayName.containsEmoji
                ? "Names can use letters, spaces, hyphens, and apostrophes, but not emoji."
                : "Enter your name to continue."
            return
        }

        isNameFocused = false
        validationMessage = nil
        memberViewModel.completeProfile(displayName: trimmedName)
        let syncToken = memberViewModel.pendingCloudSyncToken
        cloudSyncStore.saveMembers(
            memberViewModel.members,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId,
            onSuccess: {
                if let syncToken {
                    memberViewModel.markCloudSyncSucceeded(syncToken)
                }
            }
        )
    }
}

#Preview {
    ProfileSetupView()
        .environmentObject(AuthSessionStore())
        .environmentObject(CloudSyncStore())
        .environmentObject(MemberViewModel())
        .environmentObject(SettingsStore())
}

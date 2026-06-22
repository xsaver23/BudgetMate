import SwiftUI

struct InviteMemberView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var validationMessage: String?

    let onSave: (_ displayName: String, _ email: String?) -> Void

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !displayName.containsEmoji
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Member Details") {
                    TextField("Name", text: $displayName)
                        .onChange(of: displayName) { _, value in
                            validationMessage = value.containsEmoji ? "Names cannot include emoji." : nil
                        }
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.expense)
                    }
                }

                Section {
                    Text("This creates a pending invite in BudgetMate. We will add automatic email delivery when the shared-budget backend is finished.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Invite Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                            email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? nil
                                : email.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

#Preview {
    InviteMemberView { _, _ in }
}

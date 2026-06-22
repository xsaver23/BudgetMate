import SwiftUI

struct EditProfileNameView: View {
    let currentName: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var name: String
    @State private var validationMessage: String?
    @FocusState private var isFocused: Bool

    init(currentName: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.currentName = currentName
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: currentName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Profile name", text: $name)
                        .textContentType(.name)
                        .focused($isFocused)
                        .onChange(of: name) { _, value in
                            validationMessage = value.containsEmoji ? "Names cannot include emoji." : nil
                        }

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.expense)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Profile Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else {
            validationMessage = "Enter a profile name."
            return
        }
        guard !name.containsEmoji else {
            validationMessage = "Names cannot include emoji."
            return
        }

        onSave(trimmedName)
    }
}

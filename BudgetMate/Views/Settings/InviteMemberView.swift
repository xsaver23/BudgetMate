import SwiftUI

enum InviteHouseholdTarget: Equatable {
    case createNew(name: String)
    case existing(BudgetSummary)
}

private enum InviteHouseholdMode: String, CaseIterable, Identifiable {
    case createNew
    case existing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createNew:
            return "Create New"
        case .existing:
            return "Existing"
        }
    }
}

struct InviteMemberView: View {
    @Environment(\.dismiss) private var dismiss

    let ownedBudgets: [BudgetSummary]
    let onSave: (_ displayName: String, _ email: String, _ target: InviteHouseholdTarget) -> Void

    @State private var householdMode: InviteHouseholdMode = .createNew
    @State private var householdName: String = "Shared Budget"
    @State private var selectedBudgetId: UUID?
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var validationMessage: String?

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !displayName.containsEmoji &&
            selectedTarget != nil
    }

    private var selectedTarget: InviteHouseholdTarget? {
        switch householdMode {
        case .createNew:
            let trimmedName = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return nil }
            return .createNew(name: trimmedName)
        case .existing:
            guard let selectedBudget = ownedBudgets.first(where: { $0.id == selectedBudgetId }) else {
                return nil
            }
            return .existing(selectedBudget)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    inviteSection("Household") {
                        if !ownedBudgets.isEmpty {
                            Picker("Invite to", selection: $householdMode) {
                                ForEach(InviteHouseholdMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(AppTheme.brand)
                        }

                        switch householdMode {
                        case .createNew:
                            styledTextField(
                                placeholder: "Household name",
                                text: $householdName,
                                capitalization: .words
                            )
                        case .existing:
                            Menu {
                                ForEach(ownedBudgets) { budget in
                                    Button {
                                        selectedBudgetId = budget.id
                                    } label: {
                                        if selectedBudgetId == budget.id {
                                            Label(budget.name, systemImage: "checkmark")
                                        } else {
                                            Text(budget.name)
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(selectedBudgetName)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 12, weight: .black, design: .rounded))
                                }
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(BudgetBeaverPalette.ink)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .padding(.horizontal, 16)
                                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                        }
                    }

                    inviteSection("Member Details") {
                        VStack(spacing: 0) {
                            styledTextField(
                                placeholder: "Name",
                                text: $displayName,
                                capitalization: .words
                            )
                            .onChange(of: displayName) { _, value in
                                validationMessage = value.containsEmoji ? "Names cannot include emoji." : nil
                            }

                            Divider()

                            styledTextField(
                                placeholder: "Email",
                                text: $email,
                                keyboard: .emailAddress,
                                capitalization: .never,
                                autocorrection: true
                            )
                        }
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                                .stroke(AppTheme.surfaceStroke, lineWidth: 1)
                        )

                        if let validationMessage {
                            Text(validationMessage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.danger)
                        }
                    }

                    Text("Invite is saved in BudgetMate. Email delivery is coming next.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(BudgetBeaverPalette.wood)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                                .stroke(AppTheme.surfaceStroke, lineWidth: 1)
                        )

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(AppTheme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            if selectedBudgetId == nil {
                selectedBudgetId = ownedBudgets.first?.id
            }
        }
        .onChange(of: ownedBudgets) { _, budgets in
            if selectedBudgetId == nil || !budgets.contains(where: { $0.id == selectedBudgetId }) {
                selectedBudgetId = budgets.first?.id
            }
        }
    }

    private var selectedBudgetBinding: Binding<UUID?> {
        Binding(
            get: { selectedBudgetId ?? ownedBudgets.first?.id },
            set: { selectedBudgetId = $0 }
        )
    }

    private var selectedBudgetName: String {
        ownedBudgets.first(where: { $0.id == selectedBudgetBinding.wrappedValue })?.name ?? "Choose Household"
    }

    private var header: some View {
        ZStack {
            Text("Invite Member")
                .font(.roundedBold(22))
                .foregroundStyle(BudgetBeaverPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.88)

            HStack {
                cancelButton

                Spacer()

                saveButton
            }
        }
    }

    private var cancelButton: some View {
        Button("Cancel") {
            dismiss()
        }
        .font(.system(size: 18, weight: .bold, design: .rounded))
        .foregroundStyle(BudgetBeaverPalette.wood)
        .frame(width: 92, height: 52)
        .background(AppTheme.surface, in: Capsule())
        .buttonStyle(PressableButtonStyle(scale: 0.96))
    }

    private var saveButton: some View {
        Button("Save") {
            saveInvite()
        }
        .font(.system(size: 18, weight: .bold, design: .rounded))
        .foregroundStyle(canSave ? AppTheme.brand : BudgetBeaverPalette.wood.opacity(0.45))
        .frame(width: 92, height: 52)
        .background(AppTheme.surface, in: Capsule())
        .buttonStyle(PressableButtonStyle(scale: 0.96))
        .disabled(!canSave)
    }

    private func inviteSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.roundedBold(26))
                .foregroundStyle(BudgetBeaverPalette.wood)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
    }

    private func styledTextField(
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        capitalization: TextInputAutocapitalization = .sentences,
        autocorrection: Bool = false
    ) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(BudgetBeaverPalette.ink)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(autocorrection)
            .frame(minHeight: 56)
            .padding(.horizontal, 16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func saveInvite() {
        guard let selectedTarget else { return }
        onSave(
            displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            email.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedTarget
        )
        dismiss()
    }
}

#Preview {
    InviteMemberView(
        ownedBudgets: [BudgetSummary(id: UUID(), name: "Home")]
    ) { _, _, _ in }
}

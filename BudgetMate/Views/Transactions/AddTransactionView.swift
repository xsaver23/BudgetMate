import Combine
import OSLog
import SwiftData
import SwiftUI
import UIKit

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var memberViewModel: MemberViewModel
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var transactionFlow: TransactionFlowCoordinator
    @StateObject private var viewModel: AddTransactionViewModel
    private let transactionToEdit: Transaction?
    private let hasInitialSettings: Bool
    @State private var selectedMemberId: UUID?
    @State private var saveErrorMessage: String?
    @State private var editorAppearedAtUptime: TimeInterval?
    @State private var hasLoggedFirstKeyboard = false
    @FocusState private var focusedInput: FocusedInput?
    private static let interactionLogger = Logger(subsystem: "BudgetMate", category: "Interaction")
    private static let interactionSignposter = OSSignposter(subsystem: "BudgetMate", category: "Interaction")

    private enum FocusedInput: Hashable {
        case amount
        case title
        case customSplit(UUID)
    }

    init(
        transactionToEdit: Transaction? = nil,
        initialSettings: BudgetSettings? = nil,
        initialSelectedMemberId: UUID? = nil
    ) {
        self.transactionToEdit = transactionToEdit
        hasInitialSettings = initialSettings != nil
        _selectedMemberId = State(initialValue: initialSelectedMemberId)

        let model = AddTransactionViewModel(transaction: transactionToEdit)
        if let initialSettings {
            // Configure categories before SwiftUI subscribes to the model. On
            // the global add path this removes several on-appear publications
            // that previously landed just as the first keyboard was requested.
            model.updateAvailableExpenseCategories(from: initialSettings)
        }
        _viewModel = StateObject(wrappedValue: model)
    }

    private var payerId: UUID {
        selectedMemberId ?? defaultTransactionMember.id
    }

    private var defaultTransactionMember: BudgetMember {
        memberViewModel.profileMember(
            userScopeId: authStore.currentUserScopeId,
            email: authStore.userEmail
        ) ?? memberViewModel.activeMember
    }

    private var currencySymbol: String {
        settingsStore.settings.currencySymbol
    }

    private var amountBinding: Binding<String> {
        Binding(
            get: { viewModel.amountText },
            set: { viewModel.updateAmountText($0) }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                amountHero

                if let saveErrorMessage {
                    Label(saveErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.expenseText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AppTheme.expenseTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 16)
                }

                Form {
                    Section("Details") {
                        TextField("Title", text: $viewModel.title)
                            .focused($focusedInput, equals: .title)
                            .submitLabel(.done)
                            .onSubmit { focusedInput = nil }

                        Picker("Category", selection: $viewModel.category) {
                            ForEach(viewModel.availableCategories) { category in
                                Text(category.displayName).tag(category)
                            }
                        }

                        DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                    }

                    Section("Payment Method") {
                        Picker(
                            viewModel.type == .expense ? "Paid With" : "Received Via",
                            selection: $viewModel.paymentMethod
                        ) {
                            ForEach(PaymentMethod.allCases) { method in
                                Text(method.displayName).tag(method)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section(viewModel.type == .expense ? "Paid By" : "Income For") {
                        Picker(viewModel.type == .expense ? "Paid By" : "Income For", selection: $selectedMemberId) {
                            ForEach(memberViewModel.members) { member in
                                Text(member.displayName).tag(Optional(member.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if viewModel.isSplittable {
                        splitSection
                    }

                    recurringSection
                }
                .scrollContentBackground(.hidden)
                // Avoid continuously resizing the text editor and its host
                // while a drag tracks the keyboard. Immediate dismissal is a
                // single layout transition and the toolbar still provides
                // deterministic Next/Done controls.
                .scrollDismissesKeyboard(.immediately)
                .background(AppTheme.background)
                .tint(AppTheme.brand)
            }
            .background(AppTheme.background)
            .navigationTitle(transactionToEdit == nil ? "Add Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                editorAppearedAtUptime = ProcessInfo.processInfo.systemUptime
                Self.interactionSignposter.emitEvent("Transaction Editor Appeared")
                if !hasInitialSettings {
                    viewModel.updateAvailableExpenseCategories(from: settingsStore.settings)
                }
                ensureSelectedMemberIsValid()
            }
            .onDisappear {
                focusedInput = nil
            }
            .onChange(of: settingsStore.settings) { _, settings in
                viewModel.updateAvailableExpenseCategories(from: settings)
            }
            .onChange(of: memberViewModel.members) { _, _ in
                ensureSelectedMemberIsValid()
            }
            .onChange(of: viewModel.type) { _, newType in
                if newType != .expense { viewModel.isSplit = false }
            }
            .onChange(of: viewModel.isSplit) { _, splitOn in
                if splitOn, viewModel.participants.isEmpty {
                    viewModel.participants = Set(memberViewModel.members.map(\.id))
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // A suspended scene can otherwise restore with UIKit and
                // SwiftUI disagreeing about which text field owns focus.
                // Keep the draft, but always release the keyboard/responder.
                if newPhase != .active {
                    focusedInput = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                guard !hasLoggedFirstKeyboard else { return }
                hasLoggedFirstKeyboard = true
                Self.interactionSignposter.emitEvent("First Keyboard Will Show")
                if let editorAppearedAtUptime {
                    let duration = ProcessInfo.processInfo.systemUptime - editorAppearedAtUptime
                    Self.interactionLogger.notice(
                        "First keyboard requested \(duration, privacy: .public) seconds after editor appeared"
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focusedInput = nil
                        dismiss()
                    }
                    .foregroundStyle(BudgetBeaverPalette.wood)
                }

                ToolbarItem(placement: .confirmationAction) {
                    TransactionSaveToolbarButton(
                        title: transactionToEdit == nil ? "Save" : "Update",
                        isEnabled: viewModel.canSave
                    ) { cloudSyncStore in
                        saveTransaction(using: cloudSyncStore)
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(focusedInput == .amount ? "Next" : "Done") {
                        if focusedInput == .amount {
                            focusedInput = .title
                        } else {
                            focusedInput = nil
                        }
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(AppTheme.brand)
                }
            }
            .background(TransactionEditorActivityReporter())
            .task {
                // New transactions start with the amount. Requesting focus
                // after the sheet has mounted lets iOS prepare the keyboard
                // before a user's first tap, while never stealing focus from
                // a field they have already selected.
                guard transactionToEdit == nil else { return }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled,
                      scenePhase == .active,
                      focusedInput == nil else { return }
                focusedInput = .amount
            }
        }
    }

    private var amountHero: some View {
        VStack(spacing: 18) {
            Picker("Transaction Type", selection: $viewModel.type) {
                ForEach(TransactionType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .tint(viewModel.type == .income ? AppTheme.brand : AppTheme.danger)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(currencySymbol)
                    .font(.roundedBold(34))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                TextField("0", text: amountBinding)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.leading)
                    // UITextField autosizing was present in repeated physical
                    // iPhone watchdog reports. Keep both font and geometry
                    // fixed while editing; UIKit will scroll a long amount to
                    // keep its caret visible without relaying out the Form.
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BudgetBeaverPalette.ink)
                    // Keep the editor's geometry stable while typing. Tying
                    // its width to its own text forces the whole Form to lay
                    // itself out again on every digit and can interrupt a
                    // simultaneous focus transfer on physical devices.
                    .frame(width: 230, alignment: .leading)
                    .focused($focusedInput, equals: .amount)
                    .accessibilityLabel("Amount")
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { focusedInput = .amount }

            Text(viewModel.type == .expense ? "Expense" : "Income")
                .font(.caption.weight(.semibold))
                .foregroundStyle(viewModel.type == .expense ? AppTheme.expenseText : AppTheme.incomeText)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(viewModel.type == .expense ? AppTheme.expenseTint : AppTheme.incomeTint, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .background(AppTheme.background)
    }

    private var recurringSection: some View {
        Section("Recurring") {
            Toggle("Repeat monthly", isOn: $viewModel.repeatsMonthly)
                .tint(AppTheme.brand)

            if viewModel.repeatsMonthly {
                Toggle("Add stop date", isOn: $viewModel.hasRecurrenceEndDate)
                    .tint(AppTheme.brand)

                if viewModel.hasRecurrenceEndDate {
                    DatePicker("Stop Date", selection: $viewModel.recurrenceEndDate, displayedComponents: .date)
                }

                Text(recurringHelpText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var recurringHelpText: String {
        if viewModel.hasRecurrenceEndDate {
            return "This repeats monthly until the stop date."
        }
        return "This repeats monthly with no stop date. You can add a stop date later."
    }

    @ViewBuilder
    private var splitSection: some View {
        Section("Split") {
            Toggle("Split this expense", isOn: $viewModel.isSplit)
                .tint(AppTheme.brand)

            if viewModel.isSplit {
                Picker("Method", selection: $viewModel.splitMethod) {
                    ForEach(SplitMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                let equalSharesByMember = equalSharesByMember()
                ForEach(memberViewModel.members) { member in
                    participantRow(for: member, equalSharesByMember: equalSharesByMember)
                }

                if viewModel.splitMethod == .custom {
                    HStack {
                        Text("Entered")
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Text(CurrencyFormatter.amountString(viewModel.customSplitTotal, symbol: currencySymbol))
                            .font(.roundedBold(15))
                            .foregroundStyle(viewModel.isSplitValid ? AppTheme.income : AppTheme.expense)
                    }
                }

                if let message = viewModel.splitValidationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppTheme.expense)
                }
            }
        }
    }

    private func participantRow(for member: BudgetMember, equalSharesByMember: [UUID: Double]) -> some View {
        let isIncluded = viewModel.participants.contains(member.id)
        let isPayer = member.id == payerId
        return HStack(spacing: 12) {
            Button {
                toggleParticipant(member.id)
            } label: {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isIncluded ? AppTheme.brand : BudgetBeaverPalette.wood.opacity(0.45))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isIncluded ? "Remove \(member.displayName) from split" : "Include \(member.displayName) in split")

            MemberInitialsBadge(
                initials: member.displayInitials,
                colorHex: member.colorHex,
                size: 28,
                accessibilityLabel: "Member \(member.displayName)"
            )

            Text(member.displayName + (isPayer ? " (paid)" : ""))
                .foregroundStyle(isIncluded ? AppTheme.textPrimary : AppTheme.textSecondary)

            Spacer()

            if isIncluded {
                switch viewModel.splitMethod {
                case .equally:
                    Text(CurrencyFormatter.amountString(equalSharesByMember[member.id] ?? 0, symbol: currencySymbol))
                        .font(.roundedBold(15))
                        .foregroundStyle(AppTheme.textPrimary)
                case .custom:
                    TextField("0.00", text: customBinding(member.id))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedInput, equals: .customSplit(member.id))
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func equalSharesByMember() -> [UUID: Double] {
        guard let resolved = viewModel.resolvedSplits(payerId: payerId) else { return [:] }
        return Dictionary(resolved, uniquingKeysWith: { first, _ in first })
    }

    private func toggleParticipant(_ id: UUID) {
        if viewModel.participants.contains(id) {
            viewModel.participants.remove(id)
        } else {
            viewModel.participants.insert(id)
        }
    }

    private func customBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.customAmountText(for: id) },
            set: { viewModel.updateCustomAmount($0, for: id) }
        )
    }

    private func saveTransaction(using cloudSyncStore: CloudSyncStore) {
        focusedInput = nil
        saveErrorMessage = nil
        let member = memberViewModel.members.first(where: { $0.id == selectedMemberId }) ?? defaultTransactionMember
        if let transactionToEdit {
            viewModel.applyChanges(to: transactionToEdit, paidBy: member)
            transactionToEdit.ownerUserId = authStore.currentBudgetScopeId
            replaceSplits(for: transactionToEdit, paidBy: member)
            do {
                try modelContext.save()
            } catch {
                cloudSyncStore.recordSyncIssue(error, context: "Saving edited transaction")
                saveErrorMessage = "Couldn't save this transaction. Check your data and try again."
                return
            }
            cloudSyncStore.saveTransaction(
                transactionToEdit,
                userScopeId: authStore.currentUserScopeId,
                budgetScopeId: authStore.currentBudgetScopeId
            )
            transactionFlow.recordLocalSave()
            dismiss()
            return
        }

        guard let transaction = viewModel.buildTransaction(addedBy: member) else { return }
        transaction.ownerUserId = authStore.currentBudgetScopeId
        modelContext.insert(transaction)
        insertSplits(for: transaction, paidBy: member)

        do {
            try modelContext.save()
        } catch {
            cloudSyncStore.recordSyncIssue(error, context: "Saving new transaction")
            modelContext.delete(transaction)
            saveErrorMessage = "Couldn't save this transaction. Check your data and try again."
            return
        }
        cloudSyncStore.saveTransaction(
            transaction,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
        transactionFlow.recordLocalSave()
        dismiss()
    }

    private func replaceSplits(for transaction: Transaction, paidBy member: BudgetMember) {
        for split in Array(transaction.splits) {
            modelContext.delete(split)
        }
        insertSplits(for: transaction, paidBy: member)
    }

    private func insertSplits(for transaction: Transaction, paidBy member: BudgetMember) {
        guard let splits = viewModel.resolvedSplits(payerId: member.id) else { return }
        for entry in splits where entry.amount > 0 {
            let split = TransactionSplit(
                memberId: entry.memberId,
                amount: entry.amount,
                transaction: transaction
            )
            modelContext.insert(split)
        }
    }

    private func ensureSelectedMemberIsValid() {
        let ids = Set(memberViewModel.members.map(\.id))
        if let selectedMemberId, ids.contains(selectedMemberId) {
            return
        }
        selectedMemberId = transactionToEdit?.createdByMemberId ?? defaultTransactionMember.id
    }
}

/// Isolates CloudSyncStore's frequently changing status publications from the
/// transaction editor. A sync no longer invalidates the entire Form while the
/// user is in the middle of a keystroke; only this small toolbar button updates.
private struct TransactionSaveToolbarButton: View {
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore

    let title: String
    let isEnabled: Bool
    let action: (CloudSyncStore) -> Void

    var body: some View {
        Button(title) {
            action(cloudSyncStore)
        }
        .fontWeight(.bold)
        .foregroundStyle(AppTheme.brand)
        .disabled(!isEnabled)
    }
}

/// Keeps the editor's high-frequency body independent from coordinator status
/// publications while still allowing passive sync to pause for the full edit.
private struct TransactionEditorActivityReporter: View {
    @EnvironmentObject private var transactionFlow: TransactionFlowCoordinator

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear { transactionFlow.setTransactionEditorActive(true) }
            .onDisappear { transactionFlow.setTransactionEditorActive(false) }
    }
}

#Preview {
    AddTransactionView()
        .environmentObject(MemberViewModel())
        .environmentObject(SettingsStore())
        .environmentObject(AuthSessionStore())
        .environmentObject(CloudSyncStore())
        .environmentObject(TransactionFlowCoordinator())
        .modelContainer(PreviewContainer.seeded)
}

import SwiftData
import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var memberViewModel: MemberViewModel
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore
    @StateObject private var viewModel: AddTransactionViewModel
    private let transactionToEdit: Transaction?
    @State private var selectedMemberId: UUID?
    @FocusState private var amountFocused: Bool

    init(transactionToEdit: Transaction? = nil) {
        self.transactionToEdit = transactionToEdit
        _viewModel = StateObject(wrappedValue: AddTransactionViewModel(transaction: transactionToEdit))
    }

    private var payerId: UUID {
        selectedMemberId ?? memberViewModel.activeMember.id
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

                Form {
                    Section("Details") {
                        TextField("Title", text: $viewModel.title)

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

                    Section(viewModel.type == .expense ? "Paid By" : "Budget Member") {
                        Picker("Log For", selection: $selectedMemberId) {
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
                .background(AppTheme.background)
                .tint(AppTheme.brand)
            }
            .background(AppTheme.background)
            .navigationTitle(transactionToEdit == nil ? "Add Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.updateAvailableExpenseCategories(from: settingsStore.settings)
                ensureSelectedMemberIsValid()
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(BudgetBeaverPalette.wood)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(transactionToEdit == nil ? "Save" : "Update") {
                        saveTransaction()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(AppTheme.brand)
                    .disabled(!viewModel.canSave)
                }
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

                TextField("0", text: amountBinding)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.roundedBold(60))
                    .foregroundStyle(BudgetBeaverPalette.ink)
                    .lineLimit(1)
                    .frame(minWidth: 120)
                    .focused($amountFocused)
                    .accessibilityLabel("Amount")
            }
            .frame(maxWidth: .infinity)

            Text(viewModel.type == .expense ? "Expense" : "Income")
                .font(.caption.weight(.semibold))
                .foregroundStyle(viewModel.type == .expense ? AppTheme.danger : AppTheme.brand)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(viewModel.type == .expense ? AppTheme.expense : AppTheme.income, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .background(AppTheme.background)
        .contentShape(Rectangle())
        .onTapGesture { amountFocused = true }
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
                initials: member.initials,
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
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func equalSharesByMember() -> [UUID: Double] {
        guard let resolved = viewModel.resolvedSplits(payerId: payerId) else { return [:] }
        return Dictionary(uniqueKeysWithValues: resolved)
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

    private func saveTransaction() {
        let member = memberViewModel.members.first(where: { $0.id == selectedMemberId }) ?? memberViewModel.activeMember
        if let transactionToEdit {
            viewModel.applyChanges(to: transactionToEdit, paidBy: member)
            transactionToEdit.ownerUserId = authStore.currentBudgetScopeId
            replaceSplits(for: transactionToEdit, paidBy: member)
            do {
                try modelContext.save()
            } catch {
                cloudSyncStore.recordSyncIssue(error, context: "Saving edited transaction")
            }
            cloudSyncStore.saveTransaction(
                transactionToEdit,
                userScopeId: authStore.currentUserScopeId,
                budgetScopeId: authStore.currentBudgetScopeId
            )
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
        }
        cloudSyncStore.saveTransaction(
            transaction,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
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
        selectedMemberId = transactionToEdit?.createdByMemberId ?? memberViewModel.activeMember.id
    }
}

#Preview {
    AddTransactionView()
        .environmentObject(MemberViewModel())
        .environmentObject(SettingsStore())
        .environmentObject(AuthSessionStore())
        .environmentObject(CloudSyncStore())
        .modelContainer(PreviewContainer.seeded)
}

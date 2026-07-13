import SwiftData
import SwiftUI

/// Optional context when opening from a balance breakdown line.
struct TransactionBalanceContext {
    let explanation: String
    let signedAmount: Double
}

struct TransactionDetailView: View {
    let transaction: Transaction
    let members: [BudgetMember]
    let currencySymbol: String
    var balanceContext: TransactionBalanceContext? = nil
    private let membersById: [UUID: BudgetMember]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore
    @Query private var allTransactions: [Transaction]
    @State private var isEditing = false
    @State private var isShowingDeleteOptions = false

    init(
        transaction: Transaction,
        members: [BudgetMember],
        currencySymbol: String,
        balanceContext: TransactionBalanceContext? = nil
    ) {
        self.transaction = transaction
        self.members = members
        self.currencySymbol = currencySymbol
        self.balanceContext = balanceContext
        self.membersById = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var payer: BudgetMember? {
        membersById[transaction.createdByMemberId]
    }

    private var sourceTransaction: Transaction {
        let sourceId = transaction.recurringSourceId ?? transaction.id
        return allTransactions.first {
            $0.id == sourceId &&
                $0.ownerUserId == authStore.currentBudgetScopeId
        } ?? transaction
    }

    private var shouldShowRecurringActions: Bool {
        transaction.isMonthlyRecurring || transaction.isGeneratedRecurringOccurrence
    }

    private var sortedSplits: [TransactionSplit] {
        transaction.splits.sorted { $0.amount > $1.amount }
    }

    private var amountTint: Color {
        transaction.type == .income ? AppTheme.incomeTint : AppTheme.expenseTint
    }

    private var signedAmount: String {
        let sign = transaction.type == .income ? "+" : "-"
        return "\(sign)\(CurrencyFormatter.amountString(transaction.amount, symbol: currencySymbol))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    headerCard
                    if let balanceContext {
                        balanceContextCard(balanceContext)
                    }
                    detailsCard
                    if transaction.isSplit {
                        splitCard
                    }
                    deleteButton
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        isEditing = true
                    }
                }
            }
            .fullScreenCover(isPresented: $isEditing) {
                AddTransactionView(transactionToEdit: sourceTransaction)
            }
            .confirmationDialog("Recurring Transaction", isPresented: $isShowingDeleteOptions) {
                Button("Stop Future Occurrences", role: .destructive) {
                    stopFutureOccurrences()
                }

                Button("Delete Entire Series", role: .destructive) {
                    deleteTransaction(sourceTransaction)
                }

                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Choose what should happen to this monthly recurring transaction.")
            }
        }
    }

    private func balanceContextCard(_ context: TransactionBalanceContext) -> some View {
        CardContainer(showsShadow: false) {
            VStack(alignment: .leading, spacing: 8) {
                Text("In this balance")
                    .font(.roundedBold(16))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(context.explanation)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                Text(signedBalanceAmount(context.signedAmount))
                    .font(.roundedBold(22))
                    .foregroundStyle(context.signedAmount >= 0 ? AppTheme.expenseText : AppTheme.incomeText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func signedBalanceAmount(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "−"
        return "\(sign)\(CurrencyFormatter.amountString(abs(value), symbol: currencySymbol))"
    }

    private var headerCard: some View {
        CardContainer(showsShadow: false) {
            VStack(spacing: 10) {
                Text(transaction.title)
                    .font(.roundedBold(20))
                    .foregroundStyle(BudgetBeaverPalette.ink)
                    .multilineTextAlignment(.center)

                Text(signedAmount)
                    .font(.roundedBold(40))
                    .foregroundStyle(transaction.type == .income ? AppTheme.incomeText : AppTheme.expenseText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(transaction.type == .expense ? "Expense" : "Income")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(transaction.type == .income ? AppTheme.incomeText : AppTheme.expenseText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(amountTint))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var detailsCard: some View {
        CardContainer(showsShadow: false) {
            VStack(spacing: 0) {
                detailRow(label: "Category") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(CategoryColor.color(for: transaction.category))
                            .frame(width: 10, height: 10)
                        Text(transaction.category.displayName)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }

                Divider()

                if let paymentMethod = transaction.paymentMethod {
                    detailRow(label: "Payment") {
                        Text(paymentMethod.displayName)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    Divider()
                }

                detailRow(label: "Date") {
                    Text(transaction.date, format: .dateTime.weekday(.wide).month().day().year())
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Divider()

                if transaction.isMonthlyRecurring {
                    detailRow(label: "Repeats") {
                        Text("Monthly")
                            .foregroundStyle(AppTheme.textPrimary)
                    }

                    Divider()
                }

                detailRow(label: transaction.type == .expense ? "Paid by" : "Logged by") {
                    HStack(spacing: 8) {
                        if let payer {
                            MemberInitialsBadge(
                                initials: payer.displayInitials,
                                colorHex: payer.colorHex,
                                size: 24,
                                accessibilityLabel: "Member \(payer.displayName)",
                                showsShadow: false
                            )
                            Text(payer.displayName)
                                .foregroundStyle(AppTheme.textPrimary)
                        } else {
                            Text("Member unavailable")
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var splitCard: some View {
        CardContainer(showsShadow: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Split \(transaction.splits.count) ways")
                    .font(.roundedBold(22))
                    .foregroundStyle(BudgetBeaverPalette.ink)

                if let payer {
                    Text("\(firstName(payer)) paid \(CurrencyFormatter.amountString(transaction.amount, symbol: currencySymbol)). Each person below shows their share.")
                    .font(.subheadline)
                    .foregroundStyle(BudgetBeaverPalette.wood)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(sortedSplits, id: \.id) { split in
                    splitRow(split)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func splitRow(_ split: TransactionSplit) -> some View {
        let member = membersById[split.memberId]
        let isPayer = split.memberId == transaction.createdByMemberId
        let percent = transaction.amount > 0 ? Int((split.amount / transaction.amount * 100).rounded()) : 0
        return HStack(spacing: 10) {
            if let member {
                MemberInitialsBadge(
                    initials: member.displayInitials,
                    colorHex: member.colorHex,
                    size: 30,
                    accessibilityLabel: "Member \(member.displayName)",
                    showsShadow: false
                )
            } else {
                Circle()
                    .fill(AppTheme.surfaceAlt)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(member?.displayName ?? "Member unavailable")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.ink)
                Text(splitCaption(for: member, isPayer: isPayer))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isPayer ? AppTheme.brand : BudgetBeaverPalette.wood)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(CurrencyFormatter.amountString(split.amount, symbol: currencySymbol))
                    .font(.roundedBold(15))
                    .foregroundStyle(BudgetBeaverPalette.ink)
                Text("\(percent)%")
                    .font(.caption2)
                    .foregroundStyle(BudgetBeaverPalette.wood)
            }
        }
    }

    private func splitCaption(for member: BudgetMember?, isPayer: Bool) -> String {
        if isPayer { return "Paid the bill" }
        if let payer {
            return "Owes \(firstName(payer))"
        }
        return "Owes payer"
    }

    private func firstName(_ member: BudgetMember) -> String {
        let first = member.displayName.split(separator: " ").first.map(String.init) ?? member.displayName
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? member.displayName : trimmed
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            if shouldShowRecurringActions {
                isShowingDeleteOptions = true
            } else {
                deleteTransaction(transaction)
            }
        } label: {
            Label(shouldShowRecurringActions ? "Manage Recurring Transaction" : "Delete Transaction", systemImage: "trash")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppTheme.expenseTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.expense.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    private func stopFutureOccurrences() {
        let calendar = Calendar.current
        let source = sourceTransaction
        let stopDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: transaction.date)) ?? .now
        source.recurrenceRule = Transaction.monthlyRecurrenceRule(until: stopDate)
        source.needsSync = true
        do {
            try modelContext.save()
        } catch {
            cloudSyncStore.recordSyncIssue(error, context: "Stopping recurring transaction")
        }
        cloudSyncStore.saveTransaction(
            source,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
        dismiss()
    }

    private func deleteTransaction(_ transactionToDelete: Transaction) {
        cloudSyncStore.deleteTransaction(
            transactionToDelete,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
        modelContext.delete(transactionToDelete)
        do {
            try modelContext.save()
        } catch {
            cloudSyncStore.recordSyncIssue(error, context: "Deleting transaction locally")
        }
        dismiss()
    }

    private func detailRow<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            trailing()
                .font(.subheadline.weight(.medium))
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    TransactionDetailView(
        transaction: PreviewTransactions.samples[1],
        members: MemberSampleData.members,
        currencySymbol: "$"
    )
    .environmentObject(AuthSessionStore())
    .environmentObject(CloudSyncStore())
}

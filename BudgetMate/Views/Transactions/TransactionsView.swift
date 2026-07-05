import SwiftData
import SwiftUI

struct TransactionsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var memberViewModel: MemberViewModel
    @EnvironmentObject private var transactionFlow: TransactionFlowCoordinator
    @EnvironmentObject private var monthSelectionStore: MonthSelectionStore
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore
    @EnvironmentObject private var appRefreshStore: AppRefreshStore
    @Environment(\.modelContext) private var modelContext
    var onOpenSettings: () -> Void = {}
    let budgetScopeId: String
    @State private var selectedMemberId: UUID? = nil
    @State private var selectedTransaction: Transaction?

    init(budgetScopeId: String, onOpenSettings: @escaping () -> Void = {}) {
        self.budgetScopeId = budgetScopeId
        self.onOpenSettings = onOpenSettings
        _transactions = Query(
            filter: #Predicate<Transaction> { $0.ownerUserId == budgetScopeId },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    private var isShowingAddTransaction: Binding<Bool> {
        Binding(
            get: { transactionFlow.shouldPresentAddTransaction },
            set: { transactionFlow.shouldPresentAddTransaction = $0 }
        )
    }

    @Query private var transactions: [Transaction]

    // Query is already scoped to the active budget in init.
    private var scopedTransactions: [Transaction] { transactions }

    private var monthTransactions: [Transaction] {
        guard let monthInterval = monthSelectionStore.monthInterval() else { return [] }
        return RecurringTransactionResolver.transactions(in: monthInterval, from: scopedTransactions)
    }

    private var filteredTransactions: [Transaction] {
        guard let selectedMemberId else { return monthTransactions }
        return monthTransactions.filter { $0.involves(memberId: selectedMemberId) }
    }

    private var summaryTotals: DashboardTotals {
        DashboardViewModel.totals(
            transactions: filteredTransactions,
            monthlyBudget: settingsStore.settings.monthlyBudget,
            forMember: selectedMemberId
        )
    }

    private var shouldShowMemberFilter: Bool {
        memberViewModel.members.count > 1
    }

    private var groupedByDay: [(date: Date, items: [Transaction])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredTransactions) { calendar.startOfDay(for: $0.date) }
        return groups
            .map { (date: $0.key, items: sortedTransactions($0.value)) }
            .sorted { $0.date > $1.date }
    }

    private var currencySymbol: String {
        settingsStore.settings.currencySymbol
    }

    private func sortedTransactions(_ transactions: [Transaction]) -> [Transaction] {
        transactions.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AppTopBar(
                        member: memberViewModel.activeMember,
                        onProfileTap: onOpenSettings
                    )

                    VStack(spacing: 16) {
                        MonthSliderView()
                        if shouldShowMemberFilter {
                            memberFilterCard
                        }

                        summaryCard

                        if filteredTransactions.isEmpty {
                            emptyStateCard
                        } else {
                            VStack(spacing: 40) {
                                ForEach(groupedByDay, id: \.date) { group in
                                    dayCard(date: group.date, items: group.items)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .sheet(item: $selectedTransaction) { transaction in
                        TransactionDetailView(
                            transaction: transaction,
                            members: memberViewModel.members,
                            currencySymbol: currencySymbol
                        )
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable {
                await appRefreshStore.refreshCurrentBudget(forceSync: true)
            }
            .background(AppTheme.background)
            .statusBarScrim()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: isShowingAddTransaction) {
                AddTransactionView()
            }
            .onChange(of: memberViewModel.members.count) { _, count in
                if count <= 1 {
                    selectedMemberId = nil
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                summaryMetric(
                    title: "Income",
                    value: amount(summaryTotals.totalIncome)
                )
                summaryMetric(
                    title: "Expenses",
                    value: amount(summaryTotals.totalExpenses)
                )
                summaryMetric(
                    title: "Balance",
                    value: signedAmount(summaryTotals.currentBalance)
                )
            }
            .padding(.vertical, 18)
            .background(AppTheme.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.surfaceStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func summaryMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.roundedBold(18))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.58)

            Text(title)
                .font(.caption.weight(.bold))
                .tracking(2.6)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }

    private func amount(_ value: Double) -> String {
        CurrencyFormatter.amountString(value, symbol: currencySymbol)
    }

    private func signedAmount(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(CurrencyFormatter.amountString(abs(value), symbol: currencySymbol))"
    }

    private var memberFilterCard: some View {
        HStack(spacing: 12) {
            memberFilterButton(
                title: "All",
                color: AppTheme.brand,
                selection: nil,
                accessibilityLabel: "Show all members"
            )
            ForEach(memberViewModel.members) { member in
                memberFilterButton(
                    title: member.displayInitials,
                    color: Color(hex: member.colorHex),
                    selection: member.id,
                    accessibilityLabel: "Filter transactions to \(member.displayName)"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func memberFilterButton(
        title: String,
        color: Color,
        selection: UUID?,
        accessibilityLabel: String
    ) -> some View {
        MemberFilterButton(
            title: title,
            color: color,
            isSelected: selectedMemberId == selection,
            accessibilityLabel: accessibilityLabel
        ) {
            selectedMemberId = selection
        }
    }

    private func dayCard(date: Date, items: [Transaction]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dayTitle(for: date))
                    .font(.roundedBold(18))
                    .foregroundStyle(BudgetBeaverPalette.wood)
                Spacer()
                Text(dayNetLabel(for: items))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.wood)
            }

            ForEach(items) { transaction in
                CompactTransactionRow(
                    transaction: transaction,
                    currencySymbol: currencySymbol,
                    members: memberViewModel.members
                )
                .padding(14)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .onTapGesture {
                    selectedTransaction = transaction
                }
                .contextMenu {
                    if transaction.isGeneratedRecurringOccurrence {
                        Text("Recurring occurrence")
                    } else {
                        Button(role: .destructive) {
                            delete(transaction)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyStateCard: some View {
        CardContainer {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppTheme.brand)
                Text("No transactions yet")
                    .font(.roundedBold(18))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(emptyStateMessage)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func delete(_ transaction: Transaction) {
        guard transaction.ownerUserId == authStore.currentBudgetScopeId else { return }
        cloudSyncStore.deleteTransaction(
            transaction,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
        modelContext.delete(transaction)
    }

    private var emptyStateMessage: String {
        if selectedMemberId != nil {
            return "No transactions for this member this month. Try another member or add one with the + button."
        }
        return "No transactions for this month yet. Add income or an expense with the + button."
    }

    private func dayTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func dayNetLabel(for items: [Transaction]) -> String {
        let net = items.reduce(0.0) { partial, transaction in
            partial + (transaction.type == .income ? transaction.amount : -transaction.amount)
        }
        let sign = net >= 0 ? "+" : "-"
        return "\(sign)\(CurrencyFormatter.amountString(abs(net), symbol: currencySymbol))"
    }
}

#Preview {
    TransactionsView(budgetScopeId: "local")
        .environmentObject(SettingsStore())
        .environmentObject(MemberViewModel())
        .environmentObject(TransactionFlowCoordinator())
        .environmentObject(MonthSelectionStore())
        .environmentObject(AuthSessionStore())
        .environmentObject(CloudSyncStore())
        .environmentObject(AppRefreshStore())
        .modelContainer(PreviewContainer.seeded)
}

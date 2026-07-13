import SwiftData
import SwiftUI

struct TransactionsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var memberViewModel: MemberViewModel
    @EnvironmentObject private var monthSelectionStore: MonthSelectionStore
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore
    @EnvironmentObject private var appRefreshStore: AppRefreshStore
    @EnvironmentObject private var transactionFlow: TransactionFlowCoordinator
    @Environment(\.modelContext) private var modelContext
    var onOpenSettings: () -> Void = {}
    let budgetScopeId: String
    @State private var selectedMemberId: UUID? = nil
    @State private var selectedTransaction: Transaction?
    @State private var derivedMetrics = TransactionsTabMetrics()

    init(budgetScopeId: String, onOpenSettings: @escaping () -> Void = {}) {
        self.budgetScopeId = budgetScopeId
        self.onOpenSettings = onOpenSettings
        _transactions = Query(
            filter: #Predicate<Transaction> { $0.ownerUserId == budgetScopeId },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    @Query private var transactions: [Transaction]

    private var monthlyBudget: Double {
        settingsStore.monthlyBudget(in: monthSelectionStore.selectedMonthDate)
    }

    private var shouldShowMemberFilter: Bool {
        memberViewModel.members.count > 1
    }

    private var currencySymbol: String {
        settingsStore.settings.currencySymbol
    }

    // Recompute the derived list/summary only when the underlying data or
    // filters change, not on every body evaluation (see DashboardView).
    private var metricsRefreshToken: String {
        let dataHash = FinancialDataFingerprint.hash(transactions: transactions, settlements: [])
        return "\(dataHash)-\(monthSelectionStore.selectedMonthIndex)-\(selectedMemberId?.uuidString ?? "all")-\(monthlyBudget)-\(authStore.currentBudgetScopeId)"
    }

    private func refreshDerivedMetrics() {
        derivedMetrics = TransactionsTabMetrics.compute(
            transactions: transactions,
            monthInterval: monthSelectionStore.monthInterval(),
            selectedMemberId: selectedMemberId,
            monthlyBudget: monthlyBudget
        )
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

                        if derivedMetrics.filteredTransactions.isEmpty {
                            emptyStateCard
                        } else {
                    LazyVStack(spacing: 24) {
                                ForEach(derivedMetrics.groupedByDay, id: \.date) { group in
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
            .task(id: metricsRefreshToken) {
                refreshDerivedMetrics()
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
                    value: amount(derivedMetrics.summaryTotals.totalIncome)
                )
                summaryMetric(
                    title: "Expenses",
                    value: amount(derivedMetrics.summaryTotals.totalExpenses)
                )
                summaryMetric(
                    title: "Net",
                    value: signedAmount(derivedMetrics.summaryTotals.currentBalance)
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .background(AppTheme.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.surfaceStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func summaryMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
                .allowsTightening(true)

            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(2.1)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
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
                textColor: Color.accessibleForeground(forHex: "#1E3A2B"),
                selection: nil,
                accessibilityLabel: "Show all members"
            )
            ForEach(memberViewModel.members) { member in
                memberFilterButton(
                title: member.displayInitials,
                color: Color(hex: member.colorHex),
                textColor: Color.accessibleForeground(forHex: member.colorHex),
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
        textColor: Color,
        selection: UUID?,
        accessibilityLabel: String
    ) -> some View {
        MemberFilterButton(
            title: title,
            color: color,
            textColor: textColor,
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
                    .padding(12)
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

                Button(selectedMemberId == nil ? "Add transaction" : "Show everyone") {
                    if selectedMemberId == nil {
                        transactionFlow.openAddTransaction()
                    } else {
                        selectedMemberId = nil
                    }
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.brand)
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
        do {
            try modelContext.save()
        } catch {
            cloudSyncStore.recordSyncIssue(error, context: "Deleting transaction locally")
        }
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

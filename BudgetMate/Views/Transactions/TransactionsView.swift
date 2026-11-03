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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var onOpenSettings: () -> Void = {}
    let budgetScopeId: String
    @State private var selectedMemberId: UUID? = nil
    @State private var selectedTransaction: Transaction?
    @State private var transactionPendingDeletion: Transaction?
    @State private var isShowingDeleteConfirmation = false
    @State private var derivedMetrics = TransactionsTabMetrics()

    private var recentDayGroups: [(date: Date, items: [Transaction])] {
        derivedMetrics.groupedByDay.compactMap { group in
            let items = group.items.filter { !$0.isUpcomingTransaction }
            return items.isEmpty ? nil : (date: group.date, items: items)
        }
    }

    private var upcomingDayGroups: [(date: Date, items: [Transaction])] {
        derivedMetrics.groupedByDay.reversed().compactMap { group in
            let items = Array(group.items.filter(\.isUpcomingTransaction).reversed())
            return items.isEmpty ? nil : (date: group.date, items: items)
        }
    }

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

    private var mutationDecision: RecordMutationDecision {
        SharedRecordMutationCapability.decision(
            currentUserScopeId: authStore.currentUserScopeId,
            activeBudgetScopeId: authStore.currentBudgetScopeId,
            recordBudgetScopeId: budgetScopeId,
            members: memberViewModel.members
        )
    }

    // Recompute the derived list/summary only when the underlying data or
    // filters change, not on every body evaluation (see DashboardView).
    private var metricsRefreshToken: String {
        let dataHash = FinancialDataFingerprint.hash(transactions: transactions, settlements: [])
        return "\(dataHash)-\(monthSelectionStore.selectedMonthKey)-\(selectedMemberId?.uuidString ?? "all")-\(monthlyBudget)-\(authStore.currentBudgetScopeId)"
    }

    private func refreshDerivedMetrics() {
        derivedMetrics = TransactionsTabMetrics.compute(
            transactions: transactions,
            monthInterval: monthSelectionStore.monthInterval(),
            selectedMemberId: selectedMemberId,
            monthlyBudget: monthlyBudget,
            currencyCode: settingsStore.settings.currencyCode,
            calendar: monthSelectionStore.selectionCalendar
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
                        if !derivedMetrics.summaryTotals.anomalies.isEmpty {
                            Label(
                                "A money record needs review. Open its details and check the amount and currency before using this total.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BudgetBeaverPalette.amountRed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if shouldShowMemberFilter {
                            memberFilterCard
                        }

                        summaryCard

                        if !upcomingDayGroups.isEmpty {
                            Label(
                                "Totals include projected upcoming transactions.",
                                systemImage: "calendar.badge.clock"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if derivedMetrics.filteredTransactions.isEmpty {
                            emptyStateCard
                        } else {
                            if !recentDayGroups.isEmpty {
                                transactionGroup("Recent activity", groups: recentDayGroups)
                            }
                            if !upcomingDayGroups.isEmpty {
                                transactionGroup("Upcoming", groups: upcomingDayGroups)
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
            .confirmationDialog("Delete Transaction", isPresented: $isShowingDeleteConfirmation) {
                Button("Delete Transaction", role: .destructive) {
                    if let transactionPendingDeletion {
                        delete(transactionPendingDeletion)
                    }
                    transactionPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    transactionPendingDeletion = nil
                }
            } message: {
                if let transactionPendingDeletion {
                    Text("Delete “\(transactionPendingDeletion.title)” from this budget? This cannot be undone.")
                }
            }
        }
    }

    private func transactionGroup(
        _ title: String,
        groups: [(date: Date, items: [Transaction])]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            LazyVStack(spacing: 24) {
                ForEach(groups, id: \.date) { group in
                    dayCard(date: group.date, items: group.items)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCard: some View {
        VStack(spacing: 0) {
            let metricLayout: AnyLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 0))
            metricLayout {
                summaryMetric(
                    title: upcomingDayGroups.isEmpty ? "Income" : "Projected income",
                    value: amount(derivedMetrics.summaryTotals.totalIncome)
                )
                summaryMetric(
                    title: upcomingDayGroups.isEmpty ? "Expenses" : "Projected expenses",
                    value: amount(derivedMetrics.summaryTotals.totalExpenses)
                )
                summaryMetric(
                    title: upcomingDayGroups.isEmpty ? "Net" : "Projected net",
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
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
                .allowsTightening(true)

            Text(title)
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.textMuted)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
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
                Button {
                    selectedTransaction = transaction
                } label: {
                    CompactTransactionRow(
                        transaction: transaction,
                        currencySymbol: currencySymbol,
                        members: memberViewModel.members
                    )
                    .padding(12)
                }
                .buttonStyle(.plain)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHint("Opens transaction details. Use the actions menu to delete this transaction.")
                .contextMenu {
                    if transaction.isGeneratedRecurringOccurrence {
                        Text("Recurring occurrence")
                    } else if transaction.isMonthlyRecurring {
                        Button {
                            selectedTransaction = transaction
                        } label: {
                            Label("Manage Recurring Transaction", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } else if SharedRecordMutationCapability.decision(
                        currentUserScopeId: authStore.currentUserScopeId,
                        activeBudgetScopeId: authStore.currentBudgetScopeId,
                        recordBudgetScopeId: transaction.ownerUserId,
                        members: memberViewModel.members,
                        recordCreatorUserId: transaction.createdByUserId
                    ).isAllowed {
                        Button(role: .destructive) {
                            transactionPendingDeletion = transaction
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } else {
                        Label("Read only in this shared budget", systemImage: "lock.fill")
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
                    .foregroundStyle(AppTheme.brandForeground)
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
                .foregroundStyle(AppTheme.brandForeground)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func delete(_ transaction: Transaction) {
        guard SharedRecordMutationCapability.decision(
            currentUserScopeId: authStore.currentUserScopeId,
            activeBudgetScopeId: authStore.currentBudgetScopeId,
            recordBudgetScopeId: transaction.ownerUserId,
            members: memberViewModel.members,
            recordCreatorUserId: transaction.createdByUserId
        ).isAllowed else { return }
        guard transaction.ownerUserId == authStore.currentBudgetScopeId else { return }
        let transactionId = transaction.id
        let expectedRowVersion = transaction.rowVersion
        modelContext.delete(transaction)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            cloudSyncStore.recordSyncIssue(error, context: "Deleting transaction locally")
            return
        }
        cloudSyncStore.deleteTransaction(
            id: transactionId,
            expectedRowVersion: expectedRowVersion,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
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

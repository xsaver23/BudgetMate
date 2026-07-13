import SwiftData
import SwiftUI
import OSLog

private let dashboardMetricsLog = OSLog(subsystem: "BudgetMate", category: "DashboardMetrics")

struct DashboardView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var memberViewModel: MemberViewModel
    @EnvironmentObject private var monthSelectionStore: MonthSelectionStore
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore
    @EnvironmentObject private var appRefreshStore: AppRefreshStore
    var onOpenSettings: () -> Void = {}
    var onOpenBudget: () -> Void = {}
    let budgetScopeId: String
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedMemberId: UUID? = nil
    @State private var selectedTransaction: Transaction?
    @State private var pendingSettlement: SettlementSuggestion?
    @State private var breakdownPresentation: BreakdownPresentation?
    @State private var isShowingSettlementList = false
    @State private var derivedMetrics = DashboardDerivedMetrics()

    @Query private var transactions: [Transaction]
    @Query private var settlementRecords: [Settlement]

    init(
        budgetScopeId: String,
        onOpenSettings: @escaping () -> Void = {},
        onOpenBudget: @escaping () -> Void = {}
    ) {
        self.budgetScopeId = budgetScopeId
        self.onOpenSettings = onOpenSettings
        self.onOpenBudget = onOpenBudget
        _transactions = Query(
            filter: #Predicate<Transaction> { $0.ownerUserId == budgetScopeId },
            sort: \Transaction.date,
            order: .reverse
        )
        _settlementRecords = Query(
            filter: #Predicate<Settlement> { $0.ownerUserId == budgetScopeId }
        )
    }

    // Queries are already scoped to the active budget in init.
    private var scopedTransactions: [Transaction] { transactions }
    private var scopedSettlementRecords: [Settlement] { settlementRecords }

    private var monthlyBudget: Double {
        settingsStore.monthlyBudget(in: monthSelectionStore.selectedMonthDate)
    }

    private var budgetProgress: Double {
        guard monthlyBudget > 0 else { return 0 }
        return derivedMetrics.totals.totalExpenses / monthlyBudget
    }

    private var currencySymbol: String {
        settingsStore.settings.currencySymbol
    }

    private var shouldShowMemberFilter: Bool {
        memberViewModel.members.count > 1
    }

    private var metricsRevision: UInt64 {
        let needsSharedBalanceWork = memberViewModel.members.count > 1
        let dataRevision = FinancialDataFingerprint.shallowDashboardRevision(
            transactions: scopedTransactions,
            settlements: needsSharedBalanceWork ? scopedSettlementRecords : [],
            members: memberViewModel.members
        )

        var hasher = Hasher()
        hasher.combine(dataRevision)
        hasher.combine(monthSelectionStore.selectedMonthIndex)
        hasher.combine(selectedMemberId)
        hasher.combine(monthlyBudget)
        hasher.combine(authStore.currentBudgetScopeId)
        return UInt64(bitPattern: Int64(hasher.finalize()))
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
                        balanceHeroCard
                        budgetPacingCard
                        oweCard
                        categorySpendingCard
                    }
                    .padding(.horizontal)
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
            .background {
                DashboardMetricsLoader(revision: metricsRevision) {
                    await refreshDerivedMetrics()
                }
            }
            .onChange(of: memberViewModel.members.count) { _, count in
                if count <= 1 {
                    selectedMemberId = nil
                }
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(
                    transaction: transaction,
                    members: memberViewModel.members,
                    currencySymbol: currencySymbol
                )
            }
            .fullScreenCover(item: $breakdownPresentation) { presentation in
                SettlementBreakdownView(
                    presentation: presentation,
                    members: memberViewModel.members,
                    currencySymbol: currencySymbol,
                    onSettle: { settle(presentation.suggestion) }
                )
            }
            .sheet(isPresented: $isShowingSettlementList) {
                SettlementListView(
                    suggestions: derivedMetrics.settlementCache.suggestions,
                    currencySymbol: currencySymbol,
                    onClose: { isShowingSettlementList = false },
                    onBreakdown: { settlement in
                        isShowingSettlementList = false
                        breakdownPresentation = derivedMetrics.settlementCache.makeBreakdownPresentation(for: settlement)
                    },
                    onSettle: { settlement in
                        isShowingSettlementList = false
                        presentPendingSettlement(settlement)
                    }
                )
            }
            .overlay {
                if let settlement = pendingSettlement {
                    settlementConfirmationOverlay(settlement)
                        .transition(settlementOverlayTransition)
                }
            }
        }
    }

    @MainActor
    private func refreshDerivedMetrics() async {
        let signpostID = OSSignpostID(log: dashboardMetricsLog)
        os_signpost(.begin, log: dashboardMetricsLog, name: "Refresh Metrics", signpostID: signpostID)
        defer {
            os_signpost(.end, log: dashboardMetricsLog, name: "Refresh Metrics", signpostID: signpostID)
        }

        do {
            let metrics = try await DashboardDerivedMetrics.compute(
                transactions: scopedTransactions,
                settlements: scopedSettlementRecords,
                members: memberViewModel.members,
                monthInterval: monthSelectionStore.monthInterval(),
                selectedMemberId: selectedMemberId,
                monthlyBudget: monthlyBudget,
                computeSettlements: memberViewModel.members.count > 1
            )
            try Task.checkCancellation()
            derivedMetrics = metrics
        } catch is CancellationError {
            return
        } catch {
            assertionFailure("Dashboard metrics failed: \(error)")
        }
    }

    private func settle(_ settlement: SettlementSuggestion) {
        let record = Settlement(
            fromMemberId: settlement.from.id,
            toMemberId: settlement.to.id,
            amount: settlement.amount,
            ownerUserId: authStore.currentBudgetScopeId
        )
        record.needsSync = true
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            cloudSyncStore.recordSyncIssue(error, context: "Saving settle-up record")
        }
        cloudSyncStore.saveSettlement(
            record,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
        clearPendingSettlement()
    }

    private var settlementOverlayAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.2, dampingFraction: 0.9)
    }

    private var settlementOverlayTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }

    private func presentPendingSettlement(_ settlement: SettlementSuggestion) {
        withAnimation(settlementOverlayAnimation) {
            pendingSettlement = settlement
        }
    }

    private func clearPendingSettlement() {
        withAnimation(settlementOverlayAnimation) {
            pendingSettlement = nil
        }
    }

    // MARK: - Member filter

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
                    accessibilityLabel: "Filter dashboard to \(member.displayName)"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
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

    // MARK: - Balance hero

    private var balanceHeroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(netScopeLabel)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.wood)

                Text(amount(derivedMetrics.totals.currentBalance))
                    .font(.roundedBold(48))
                    .foregroundStyle(BudgetBeaverPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.48)
            }

            HStack(alignment: .center, spacing: 14) {
                miniStat(
                    title: "Income",
                    value: derivedMetrics.totals.totalIncome,
                    tint: AppTheme.income,
                    systemImage: "arrow.down.left"
                )
                miniStat(
                    title: "Expenses",
                    value: derivedMetrics.totals.totalExpenses,
                    tint: AppTheme.expense,
                    systemImage: "arrow.up.right"
                )
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniStat(title: String, value: Double, tint: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: systemImage)
                .font(.headline.weight(.black))
                .foregroundStyle(AppTheme.brand)
                .frame(width: 40, height: 40)
                .background(AppTheme.brandSoft, in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.weight(.bold))
                Text(amount(value))
                    .font(.title2.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .foregroundStyle(BudgetBeaverPalette.ink)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.surfaceStroke, lineWidth: 1)
        )
    }

    // MARK: - Budget pacing dam bar

    private var budgetPacingCard: some View {
        Group {
            if monthlyBudget > 0 {
                damBarSummary
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set up category budgets to track your pacing.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BudgetBeaverPalette.wood)

                    Button("Set up budgets", action: onOpenBudget)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.warningText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .background(AppTheme.warningTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.secondaryAction.opacity(0.28), lineWidth: 1)
        )
    }

    private var netScopeLabel: String {
        let calendar = Calendar.current
        return calendar.isDate(monthSelectionStore.selectedMonthDate, equalTo: .now, toGranularity: .month)
            ? "Net this month"
            : "Net for \(monthSelectionStore.selectedMonthDate.formatted(.dateTime.month(.wide).year()))"
    }

    private var damBarSummary: some View {
        let clampedProgress = min(max(budgetProgress, 0), 1)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Budget pacing")
                    .font(.title3.weight(.black))
                    .foregroundStyle(BudgetBeaverPalette.wood)
                Spacer()
                Text(spentPercentageText)
                    .font(.title3.weight(.black))
                    .foregroundStyle(BudgetBeaverPalette.wood)
            }

            ProgressView(value: clampedProgress)
                .tint(AppTheme.secondaryAction)
                .scaleEffect(x: 1, y: 1.4, anchor: .center)
                .accessibilityLabel("Budget pacing")
                .accessibilityValue(spentPercentageText)

            pacingStatusBox
        }
        .padding(20)
    }

    private func spentLabel(_ spent: Double) -> Text {
        Text("Spent: ")
            .font(.footnote.weight(.medium))
            .foregroundColor(BudgetBeaverPalette.wood.opacity(0.7)) +
        Text(amount(spent))
            .font(.footnote.weight(.bold))
            .foregroundColor(BudgetBeaverPalette.ink)
    }

    private var spentPercentageText: String {
        guard monthlyBudget > 0 else { return "0%" }
        return (budgetProgress * 100).formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    private var pacingStatusBox: some View {
        let insight = damBarInsight()

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight.systemImage)
                .foregroundStyle(insight.iconColor)

            insight.text
                .font(.subheadline)
                .foregroundStyle(insight.textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Who owes whom

    private var oweCard: some View {
        let suggestions = derivedMetrics.settlementCache.suggestions
        let displayedSuggestions = Array(suggestions.prefix(3))

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Settle up")
                    .font(.title3.weight(.black))
                    .foregroundStyle(BudgetBeaverPalette.ink)

                Spacer()

                if suggestions.count > 1 {
                    Button("More") {
                        isShowingSettlementList = true
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.wood)
                }
            }

            if !displayedSuggestions.isEmpty {
                ForEach(displayedSuggestions) { settlement in
                    beaverSettlementRow(settlement)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BudgetBeaverPalette.forest)
                    Text("No split balances right now.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BudgetBeaverPalette.grayText)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surfaceAlt, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.top, 2)
    }

    private func beaverSettlementRow(_ settlement: SettlementSuggestion) -> some View {
        VStack(spacing: 14) {
            Button {
                breakdownPresentation = derivedMetrics.settlementCache.makeBreakdownPresentation(for: settlement)
            } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        settlementAvatar(member: settlement.from, color: avatarColor(for: settlement.from), borderColor: BudgetBeaverPalette.innerSurface)
                        Image(systemName: "arrow.right")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(BudgetBeaverPalette.wood)
                        settlementAvatar(member: settlement.to, color: avatarColor(for: settlement.to), borderColor: BudgetBeaverPalette.innerSurface)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(firstName(settlement.from)) owes \(firstName(settlement.to))")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(BudgetBeaverPalette.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)

                        Text("Tap for breakdown")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BudgetBeaverPalette.wood)
                    }

                    Spacer(minLength: 6)

                    Text(amount(settlement.amount))
                        .font(.title3.weight(.black))
                        .foregroundStyle(BudgetBeaverPalette.amountRed)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .buttonStyle(PressableButtonStyle(scale: 0.985, pressedOpacity: 0.9))

            Button {
                presentPendingSettlement(settlement)
            } label: {
                Text("Settle up")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(AppTheme.brand, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97))
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(settlement.from.displayName) owes \(settlement.to.displayName)")
        .accessibilityValue(amount(settlement.amount))
        .accessibilityHint("Tap for breakdown.")
    }

    private func settlementAvatar(member: BudgetMember, color: Color, borderColor: Color) -> some View {
        Text(member.displayInitials)
            .font(.system(size: 20, weight: .black, design: .rounded))
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
            .background(color, in: Circle())
            .overlay(Circle().stroke(borderColor, lineWidth: 3))
    }

    private func avatarColor(for member: BudgetMember) -> Color {
        Color(hex: member.colorHex)
    }

    private func settlementConfirmationOverlay(_ settlement: SettlementSuggestion) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    clearPendingSettlement()
                }

            VStack(spacing: 18) {
                Text("\(firstName(settlement.from)) paid \(firstName(settlement.to)) \(amount(settlement.amount))?")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.amountDark)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 10) {
                    Button {
                        settle(settlement)
                    } label: {
                        Text("Mark as paid")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(BudgetBeaverPalette.jenBlue, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())

                    Button {
                        clearPendingSettlement()
                    } label: {
                        Text("Cancel")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(BudgetBeaverPalette.amountDark)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.gray.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 24)
        }
    }

    private func firstName(_ member: BudgetMember) -> String {
        let first = member.displayName.split(separator: " ").first.map(String.init) ?? member.displayName
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? member.displayName : trimmed
    }

    // MARK: - Category spending podium

    private var categorySpendingCard: some View {
        let topCategories = Array(derivedMetrics.expenseBreakdown.prefix(3))

        return VStack(spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2.fill")
                        .foregroundStyle(BudgetBeaverPalette.wood)

                    Text("Top 3 Categories")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(BudgetBeaverPalette.ink)
                }

                Spacer()

                Text("THIS MONTH")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.warningTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if topCategories.isEmpty {
                emptyState(
                    systemImage: "chart.bar.xaxis",
                    title: "No category spending yet",
                    message: "Add an expense this month to see where your money is going."
                )
            } else {
                podiumHeroCard(topCategories[0])

                if topCategories.count > 1 {
                    HStack(spacing: 12) {
                        podiumSplitCard(topCategories[1], tint: BudgetBeaverPalette.forest)

                        if topCategories.count > 2 {
                            podiumSplitCard(topCategories[2], tint: BudgetBeaverPalette.clay)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(BudgetBeaverPalette.paper, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(BudgetBeaverPalette.border, lineWidth: 1)
        )
    }

    private func podiumHeroCard(_ item: ExpenseCategoryBreakdown) -> some View {
        let iconName = categoryIconName(for: item.category)

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HIGHEST SPEND")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BudgetBeaverPalette.water)

                    Text(item.category.displayName)
                        .font(.title3.weight(.black))
                        .foregroundStyle(BudgetBeaverPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer()

                Image(systemName: iconName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.water)
                    .frame(width: 46, height: 46)
                    .background(BudgetBeaverPalette.water.opacity(0.12), in: Circle())
            }

            Text(amount(item.amount))
                .font(.largeTitle.weight(.black))
                .foregroundStyle(BudgetBeaverPalette.water)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottomTrailing) {
            Image(systemName: iconName)
                .font(.system(size: 110, weight: .black))
                .foregroundStyle(BudgetBeaverPalette.water.opacity(0.03))
                .offset(x: 6, y: 10)
        }
        .background(BudgetBeaverPalette.bank, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BudgetBeaverPalette.border, lineWidth: 1)
        )
    }

    private func podiumSplitCard(_ item: ExpenseCategoryBreakdown, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: categoryIconName(for: item.category))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)

                Text(item.category.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Text(amount(item.amount))
                .font(.title3.weight(.black))
                .foregroundStyle(BudgetBeaverPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BudgetBeaverPalette.bank, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BudgetBeaverPalette.border, lineWidth: 1)
        )
    }

    private func categoryIconName(for category: TransactionCategory) -> String {
        switch category {
        case .shopping:
            return "bag.fill"
        case .restaurant, .food:
            return "fork.knife"
        case .groceries:
            return "cart.fill"
        case .rent, .household:
            return "house.fill"
        case .transportation, .gas, .parking:
            return "car.fill"
        case .bills, .subscription:
            return "doc.text.fill"
        case .health:
            return "cross.case.fill"
        case .entertainment:
            return "sparkles.tv.fill"
        case .vacation:
            return "airplane"
        case .gift:
            return "gift.fill"
        default:
            return "tag.fill"
        }
    }

    private func amount(_ value: Double) -> String {
        CurrencyFormatter.amountString(value, symbol: currencySymbol)
    }

    private func damBarInsight() -> (text: Text, systemImage: String, iconColor: Color, textColor: Color, background: Color) {
        if derivedMetrics.totals.remainingBudget < 0 {
            let overAmount = amount(abs(derivedMetrics.totals.remainingBudget))
            return (
                Text("You're over budget by ")
                    .fontWeight(.regular) +
                Text(overAmount)
                    .fontWeight(.bold) +
                Text("."),
                "exclamationmark.triangle.fill",
                AppTheme.expense,
                AppTheme.expense,
                AppTheme.expense.opacity(0.1)
            )
        }

        guard let monthInterval = monthSelectionStore.monthInterval() else {
            return (
                Text("You're on track so far."),
                "checkmark.circle.fill",
                BudgetBeaverPalette.forest,
                BudgetBeaverPalette.forestText,
                BudgetBeaverPalette.forestSoft
            )
        }

        let calendar = Calendar.current
        let now = Date()
        let start = monthInterval.start
        let end = monthInterval.end

        if now < start {
            return (
                Text("This month hasn't started yet. Your budget is ")
                    .fontWeight(.regular) +
                Text(amount(monthlyBudget))
                    .fontWeight(.bold) +
                Text("."),
                "calendar",
                BudgetBeaverPalette.wood,
                BudgetBeaverPalette.ink,
                BudgetBeaverPalette.bank
            )
        }

        if now >= end {
            return (
                Text("This month ended with ")
                    .fontWeight(.regular) +
                Text(amount(derivedMetrics.totals.remainingBudget))
                    .fontWeight(.bold) +
                Text(" remaining."),
                "checkmark.circle.fill",
                BudgetBeaverPalette.forest,
                BudgetBeaverPalette.forestText,
                BudgetBeaverPalette.forestSoft
            )
        }

        let totalDays = max(calendar.dateComponents([.day], from: start, to: end).day ?? 1, 1)
        let elapsedDays = max((calendar.dateComponents([.day], from: start, to: now).day ?? 0) + 1, 1)
        let remainingDays = max(totalDays - elapsedDays + 1, 1)
        let dailyRemaining = derivedMetrics.totals.remainingBudget / Double(remainingDays)
        let expectedSpend = monthlyBudget * (Double(elapsedDays) / Double(totalDays))
        let tolerance = monthlyBudget * 0.05
        let dailyPhrase = remainingDays == 1
            ? "\(amount(derivedMetrics.totals.remainingBudget)) left for today"
            : "about \(amount(dailyRemaining)) per day left"

        if derivedMetrics.totals.totalExpenses <= expectedSpend + tolerance {
            return (
                Text("You're on track. You have ")
                    .fontWeight(.regular) +
                Text(dailyPhrase)
                    .fontWeight(.bold) +
                Text("."),
                "checkmark.circle.fill",
                BudgetBeaverPalette.forest,
                BudgetBeaverPalette.forestText,
                BudgetBeaverPalette.forestSoft
            )
        }

        return (
            Text("You're spending faster than planned. You have ")
                .fontWeight(.regular) +
            Text(dailyPhrase)
                .fontWeight(.bold) +
            Text("."),
            "speedometer",
            AppTheme.warning,
            AppTheme.warning,
            AppTheme.warning.opacity(0.1)
        )
    }

    private func pacingInsight() -> (text: String, systemImage: String, tint: Color) {
        guard monthlyBudget > 0 else {
            return ("Set a monthly budget to track pacing.", "calendar.badge.clock", AppTheme.textSecondary)
        }

        if derivedMetrics.totals.remainingBudget < 0 {
            return (
                "You're over budget by \(amount(abs(derivedMetrics.totals.remainingBudget))).",
                "exclamationmark.triangle.fill",
                AppTheme.expense
            )
        }

        guard let monthInterval = monthSelectionStore.monthInterval() else {
            return ("You're on track so far.", "checkmark.circle.fill", AppTheme.income)
        }

        let calendar = Calendar.current
        let now = Date()
        let start = monthInterval.start
        let end = monthInterval.end
        let totalDays = max(calendar.dateComponents([.day], from: start, to: end).day ?? 1, 1)

        if now < start {
            return (
                "This month hasn't started yet. Your budget is \(amount(monthlyBudget)).",
                "calendar",
                AppTheme.textSecondary
            )
        }

        if now >= end {
            return (
                "This month ended with \(amount(derivedMetrics.totals.remainingBudget)) remaining.",
                "checkmark.circle.fill",
                AppTheme.income
            )
        }

        let elapsedDays = max((calendar.dateComponents([.day], from: start, to: now).day ?? 0) + 1, 1)
        let remainingDays = max(totalDays - elapsedDays + 1, 1)
        let dailyRemaining = derivedMetrics.totals.remainingBudget / Double(remainingDays)
        let expectedSpend = monthlyBudget * (Double(elapsedDays) / Double(totalDays))
        let tolerance = monthlyBudget * 0.05
        let remainingPhrase = remainingDays == 1
            ? "\(amount(derivedMetrics.totals.remainingBudget)) left for today"
            : "about \(amount(dailyRemaining)) per day left"

        if derivedMetrics.totals.totalExpenses <= expectedSpend + tolerance {
            return (
                "You're on track. \(remainingPhrase).",
                "checkmark.circle.fill",
                AppTheme.income
            )
        }

        return (
            "You're spending faster than planned. \(remainingPhrase).",
            "speedometer",
            AppTheme.expense
        )
    }

    private func emptyState(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(AppTheme.brand)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func filterLabel(for member: BudgetMember) -> String {
        let trimmed = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return member.displayInitials }

        // Segmented controls are tight; prefer first name for readability.
        let firstWord = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        return firstWord
    }
}

/// Keeps transaction-editor and cloud-sync publications below DashboardView so
/// they can cancel/restart metrics work without invalidating the whole screen.
private struct DashboardMetricsLoader: View {
    @EnvironmentObject private var transactionFlow: TransactionFlowCoordinator
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore

    let revision: UInt64
    let load: () async -> Void

    private var isTransactionEditorActive: Bool {
        transactionFlow.shouldPresentAddTransaction || transactionFlow.isTransactionEditorActive
    }

    private var loadKey: DashboardMetricsLoadKey {
        DashboardMetricsLoadKey(
            revision: revision,
            cloudLastSyncedAt: cloudSyncStore.lastSyncedAt,
            isTransactionEditorActive: isTransactionEditorActive
        )
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: loadKey) {
                guard !isTransactionEditorActive else { return }

                do {
                    // Let the first frame and a newly requested keyboard win
                    // before walking the dashboard's relationship-backed data.
                    try await Task.sleep(for: .milliseconds(180))
                    try Task.checkCancellation()
                    await Task.yield()
                    try Task.checkCancellation()
                    await load()
                } catch is CancellationError {
                    return
                } catch {
                    assertionFailure("Dashboard metrics loader failed: \(error)")
                }
            }
    }
}

private struct DashboardMetricsLoadKey: Hashable {
    let revision: UInt64
    let cloudLastSyncedAt: Date?
    let isTransactionEditorActive: Bool
}

#Preview {
    DashboardView(budgetScopeId: "local")
        .environmentObject(SettingsStore())
        .environmentObject(MemberViewModel())
        .environmentObject(MonthSelectionStore())
        .environmentObject(AuthSessionStore())
        .environmentObject(CloudSyncStore())
        .environmentObject(AppRefreshStore())
        .environmentObject(TransactionFlowCoordinator())
        .modelContainer(PreviewContainer.seeded)
}

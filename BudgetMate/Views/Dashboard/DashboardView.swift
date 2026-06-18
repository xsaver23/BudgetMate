import SwiftData
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var memberViewModel: MemberViewModel
    @EnvironmentObject private var monthSelectionStore: MonthSelectionStore
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore
    var onOpenSettings: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @State private var selectedMemberId: UUID? = nil
    @State private var selectedTransaction: Transaction?
    @State private var pendingSettlement: SettlementSuggestion?
    @State private var breakdownPresentation: BreakdownPresentation?
    @State private var derivedMetrics = DashboardDerivedMetrics()

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @Query private var settlementRecords: [Settlement]

    private var scopedTransactions: [Transaction] {
        transactions.filter { $0.ownerUserId == authStore.currentBudgetScopeId }
    }

    private var scopedSettlementRecords: [Settlement] {
        settlementRecords.filter { $0.ownerUserId == authStore.currentBudgetScopeId }
    }

    private var monthlyBudget: Double {
        settingsStore.settings.monthlyBudget
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

    private var metricsRefreshToken: String {
        let dataHash = FinancialDataFingerprint.hash(
            transactions: scopedTransactions,
            settlements: scopedSettlementRecords
        )
        return "\(dataHash)-\(monthSelectionStore.selectedMonthIndex)-\(selectedMemberId?.uuidString ?? "all")-\(monthlyBudget)-\(authStore.currentBudgetScopeId)"
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
            .overlay {
                if let settlement = pendingSettlement {
                    settlementConfirmationOverlay(settlement)
                }
            }
        }
    }

    private func refreshDerivedMetrics() {
        derivedMetrics = DashboardDerivedMetrics.compute(
            transactions: scopedTransactions,
            settlements: scopedSettlementRecords,
            members: memberViewModel.members,
            monthInterval: monthSelectionStore.monthInterval(),
            selectedMemberId: selectedMemberId,
            monthlyBudget: monthlyBudget
        )
    }

    private func settle(_ settlement: SettlementSuggestion) {
        let record = Settlement(
            fromMemberId: settlement.from.id,
            toMemberId: settlement.to.id,
            amount: settlement.amount,
            ownerUserId: authStore.currentBudgetScopeId
        )
        modelContext.insert(record)
        try? modelContext.save()
        cloudSyncStore.saveSettlement(
            record,
            userScopeId: authStore.currentUserScopeId,
            budgetScopeId: authStore.currentBudgetScopeId
        )
        pendingSettlement = nil
    }

    // MARK: - Member filter

    private var memberFilterCard: some View {
        CardContainer {
            Picker("View", selection: $selectedMemberId) {
                Text("Combined").tag(Optional<UUID>.none)
                ForEach(memberViewModel.members) { member in
                    Text(filterLabel(for: member)).tag(Optional(member.id))
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Balance hero

    private var balanceHeroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TOTAL BALANCE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.6))

                Text(amount(derivedMetrics.totals.currentBalance))
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(BudgetBeaverPalette.water)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }

            HStack(alignment: .center, spacing: 12) {
                miniStat(
                    title: "Income",
                    value: derivedMetrics.totals.totalIncome,
                    tint: BudgetBeaverPalette.forest,
                    systemImage: "arrow.down.left"
                )
                miniStat(
                    title: "Expenses",
                    value: derivedMetrics.totals.totalExpenses,
                    tint: BudgetBeaverPalette.clay,
                    systemImage: "arrow.up.right"
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BudgetBeaverPalette.paper, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(BudgetBeaverPalette.border, lineWidth: 1)
        )
    }

    private func miniStat(title: String, value: Double, tint: Color, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.7))
                    .lineLimit(1)

                Text(amount(value))
                    .font(.title3.weight(.black))
                    .foregroundStyle(BudgetBeaverPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BudgetBeaverPalette.bank.opacity(0.6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BudgetBeaverPalette.border, lineWidth: 1)
        )
    }

    // MARK: - Budget pacing dam bar

    private var budgetPacingCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Budget Pacing")
                .font(.roundedBold(18))
                .foregroundStyle(BudgetBeaverPalette.ink)

            if monthlyBudget > 0 {
                damBarSummary
            } else {
                Text("Set a monthly budget in Settings to track your pacing.")
                    .font(.subheadline)
                    .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BudgetBeaverPalette.bank, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
    }

    private var damBarSummary: some View {
        let spent = derivedMetrics.totals.totalExpenses
        let remaining = derivedMetrics.totals.remainingBudget
        let clampedProgress = min(max(budgetProgress, 0), 1)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(remaining >= 0 ? "REMAINING" : "OVER BUDGET")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.6))

                    Text(amount(abs(remaining)))
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(BudgetBeaverPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }

                Spacer(minLength: 12)

                Text("of \(amount(monthlyBudget))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            DamProgressBar(progress: clampedProgress)
                .frame(height: 20)

            HStack {
                spentLabel(spent)

                Spacer()

                Text(spentPercentageText)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.water)
            }

            pacingStatusBox
        }
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
        .background(insight.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Who owes whom

    private var oweCard: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Text("$")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)
                        .frame(width: 32, height: 32)
                        .background(BudgetBeaverPalette.rebBrown, in: Circle())

                    Text("Settle Balance")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(BudgetBeaverPalette.ink)
                }

                Spacer()

                Text("SPLIT BILL")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.wood.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BudgetBeaverPalette.bank, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let settlement = derivedMetrics.settlementCache.suggestions.first {
                beaverSettlementCard(settlement)
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
                .background(BudgetBeaverPalette.bank.opacity(0.6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
    }

    private func beaverSettlementCard(_ settlement: SettlementSuggestion) -> some View {
        VStack(spacing: 10) {
            Button {
                breakdownPresentation = derivedMetrics.settlementCache.makeBreakdownPresentation(for: settlement)
            } label: {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(firstName(settlement.from).uppercased()) OWES \(firstName(settlement.to).uppercased())")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BudgetBeaverPalette.muted)
                            .padding(.bottom, 6)

                        Text(amount(settlement.amount))
                            .font(.largeTitle.weight(.black))
                            .foregroundStyle(BudgetBeaverPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .padding(.bottom, 2)

                        Text("Tap for breakdown")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BudgetBeaverPalette.jenBlue)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                    .padding(.trailing, 90)

                    HStack(spacing: -8) {
                        settlementAvatar(
                            member: settlement.from,
                            color: BudgetBeaverPalette.rebBrown,
                            borderColor: BudgetBeaverPalette.innerSurface
                        )
                        settlementAvatar(
                            member: settlement.to,
                            color: BudgetBeaverPalette.jenBlue,
                            borderColor: BudgetBeaverPalette.innerSurface
                        )
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BudgetBeaverPalette.innerSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                pendingSettlement = settlement
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))

                    Text("Settle Balance")
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(BudgetBeaverPalette.darkButton, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(settlement.from.displayName) owes \(settlement.to.displayName) \(amount(settlement.amount)). Tap for breakdown.")
    }

    private func settlementAvatar(member: BudgetMember, color: Color, borderColor: Color) -> some View {
        Text(String(member.initials.prefix(1)).uppercased())
            .font(.system(size: 20, weight: .black, design: .rounded))
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
            .background(color, in: Circle())
            .overlay(Circle().stroke(borderColor, lineWidth: 3))
    }

    private func settlementConfirmationOverlay(_ settlement: SettlementSuggestion) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    pendingSettlement = nil
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
                    .buttonStyle(.plain)

                    Button {
                        pendingSettlement = nil
                    } label: {
                        Text("Cancel")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(BudgetBeaverPalette.amountDark)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.gray.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
                    .background(BudgetBeaverPalette.bank, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        .background(BudgetBeaverPalette.paper, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
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
                    .background(.white.opacity(0.6), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
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
                .offset(x: 12, y: 18)
        }
        .background(
            LinearGradient(
                colors: [
                    BudgetBeaverPalette.water.opacity(0.10),
                    BudgetBeaverPalette.water.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BudgetBeaverPalette.water.opacity(0.20), lineWidth: 1)
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
        .background(BudgetBeaverPalette.bank.opacity(0.6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
        guard !trimmed.isEmpty else { return member.initials }

        // Segmented controls are tight; prefer first name for readability.
        let firstWord = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        return firstWord
    }
}

private enum BudgetBeaverPalette {
    static let warmBackground = Color(hex: "#E8E4DC")
    static let ink = Color(hex: "#4A3B32")
    static let wood = Color(hex: "#8B5A2B")
    static let paper = Color(hex: "#FEFDFB")
    static let bank = Color(hex: "#F4F1EA")
    static let innerSurface = Color(hex: "#F5F3F0")
    static let pill = Color(hex: "#F1ECE2")
    static let border = Color(hex: "#E8E3D9")
    static let water = Color(hex: "#4A90E2")
    static let rebBrown = Color(hex: "#7B5A3E")
    static let jenBlue = Color(hex: "#5B93E8")
    static let darkButton = Color(hex: "#4A3F35")
    static let amountDark = Color(hex: "#3D3D3D")
    static let amountRed = Color(hex: "#D4183D")
    static let grayText = Color(hex: "#717182")
    static let muted = Color(hex: "#B4A592")
    static let forest = Color(hex: "#3E885B")
    static let forestText = Color(hex: "#2C6341")
    static let forestSoft = Color(hex: "#F2F7F4")
    static let clay = Color(hex: "#D97757")
}

private struct DamProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BudgetBeaverPalette.bank)
                    .frame(height: 20)

                Capsule()
                    .fill(BudgetBeaverPalette.water)
                    .frame(width: max(proxy.size.width * progress, 0), height: 20)
            }
        }
        .frame(height: 20)
        .accessibilityLabel("Budget spent")
        .accessibilityValue((progress * 100).formatted(.number.precision(.fractionLength(0...1))) + "%")
    }
}

#Preview {
    DashboardView()
        .environmentObject(SettingsStore())
        .environmentObject(MemberViewModel())
        .environmentObject(MonthSelectionStore())
        .modelContainer(PreviewContainer.seeded)
}

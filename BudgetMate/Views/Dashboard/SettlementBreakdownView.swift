import SwiftData
import SwiftUI

/// Explains *why* one member owes another: a pairwise list of every split bill
/// and settlement between them, with each line's effect on the running balance.
struct SettlementBreakdownView: View {
    let presentation: BreakdownPresentation
    let members: [BudgetMember]
    let currencySymbol: String
    var onSettle: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore
    @State private var selectedTransaction: Transaction?
    @State private var selectedSettlementDetail: SettlementDetailPayload?

    private var suggestion: SettlementSuggestion { presentation.suggestion }
    private var lineItems: [BalanceLineItem] { presentation.lineItems }

    private var debtorName: String { firstName(suggestion.from) }
    private var creditorName: String { firstName(suggestion.to) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    headerCard
                    breakdownCard
                    settleButton
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Balance Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .fullScreenCover(item: $selectedTransaction) { transaction in
                TransactionDetailView(
                    transaction: transaction,
                    members: members,
                    currencySymbol: currencySymbol,
                    balanceContext: presentation.balanceContextByTransactionId[transaction.id]
                )
            }
            .fullScreenCover(item: $selectedSettlementDetail) { payload in
                SettlementDetailView(
                    settlement: payload.settlement,
                    lineItem: payload.lineItem,
                    debtor: suggestion.from,
                    creditor: suggestion.to,
                    members: members,
                    currencySymbol: currencySymbol
                )
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        CardContainer {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    memberBadge(suggestion.from, size: 46)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.textSecondary)
                    memberBadge(suggestion.to, size: 46)
                }

                Text("\(debtorName) owes \(creditorName)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)

                Text(amount(suggestion.amount))
                    .font(.roundedBold(40))
                    .foregroundStyle(AppTheme.expense)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func memberBadge(_ member: BudgetMember, size: CGFloat) -> some View {
        MemberInitialsBadge(
            initials: String(member.initials.prefix(1)).uppercased(),
            colorHex: member.colorHex,
            size: size,
            accessibilityLabel: "Member \(member.displayName)"
        )
    }

    // MARK: - Breakdown list

    private var breakdownCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("How this adds up")
                    .font(.roundedBold(18))
                    .foregroundStyle(AppTheme.textPrimary)

                if lineItems.isEmpty {
                    Text("No shared bills found between \(debtorName) and \(creditorName).")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(lineItems.enumerated()), id: \.element.id) { index, item in
                        lineRow(item)
                        if index < lineItems.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func lineRow(_ item: BalanceLineItem) -> some View {
        Button {
            openDetail(for: item)
        } label: {
            HStack(spacing: 12) {
                iconCircle(for: item)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.subtitle)
                        Text("·")
                        Text(item.date, format: .dateTime.month().day())
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(signedString(item))
                        .font(.roundedBold(15))
                        .foregroundStyle(item.signedAmount >= 0 ? AppTheme.expense : AppTheme.income)

                    if item.isTappable {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .buttonStyle(PressableButtonStyle(scale: 0.98, pressedOpacity: item.isTappable ? 0.9 : 1))
        .disabled(!item.isTappable)
        .accessibilityHint(item.isTappable ? "Opens details" : "")
    }

    private func openDetail(for item: BalanceLineItem) {
        if let transactionId = item.transactionId,
           let transaction = presentation.transactionById[transactionId] {
            selectedTransaction = transaction
        } else if let settlementId = item.settlementId,
                  let settlement = presentation.settlementById[settlementId] {
            selectedSettlementDetail = SettlementDetailPayload(settlement: settlement, lineItem: item)
        }
    }

    private func iconCircle(for item: BalanceLineItem) -> some View {
        let tint: Color
        let systemImage: String
        switch item.kind {
        case .debtorShare:
            tint = item.category.map { CategoryColor.color(for: $0) } ?? AppTheme.expense
            systemImage = "arrow.up.right"
        case .creditorShare:
            tint = item.category.map { CategoryColor.color(for: $0) } ?? AppTheme.income
            systemImage = "arrow.down.left"
        case .settlement:
            tint = AppTheme.brand
            systemImage = "checkmark"
        }
        return Image(systemName: systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(Circle().fill(tint.opacity(0.14)))
    }

    private var settleButton: some View {
        Button {
            onSettle()
            dismiss()
        } label: {
            Text("Settle Up · \(amount(suggestion.amount))")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    // MARK: - Helpers

    private func signedString(_ item: BalanceLineItem) -> String {
        let sign = item.signedAmount >= 0 ? "+" : "−"
        return "\(sign)\(amount(abs(item.signedAmount)))"
    }

    private func amount(_ value: Double) -> String {
        CurrencyFormatter.amountString(value, symbol: currencySymbol)
    }

    private func firstName(_ member: BudgetMember) -> String {
        let first = member.displayName.split(separator: " ").first.map(String.init) ?? member.displayName
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? member.displayName : trimmed
    }
}

// MARK: - Settlement detail

private struct SettlementDetailPayload: Identifiable {
    let settlement: Settlement
    let lineItem: BalanceLineItem
    var id: UUID { settlement.id }
}

private struct SettlementDetailView: View {
    let settlement: Settlement
    let lineItem: BalanceLineItem
    let debtor: BudgetMember
    let creditor: BudgetMember
    let members: [BudgetMember]
    let currencySymbol: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore

    private var payer: BudgetMember? {
        members.first(where: { $0.id == settlement.fromMemberId })
    }

    private var payee: BudgetMember? {
        members.first(where: { $0.id == settlement.toMemberId })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    headerCard
                    balanceContextCard
                    detailsCard
                    deleteButton
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Settle Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var headerCard: some View {
        CardContainer(showsShadow: false) {
            VStack(spacing: 10) {
                Text("Settled up")
                    .font(.roundedBold(20))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(amount(settlement.amount))
                    .font(.roundedBold(40))
                    .foregroundStyle(AppTheme.brand)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text("Recorded payment")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(AppTheme.brand)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AppTheme.brandSoft))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var balanceContextCard: some View {
        CardContainer(showsShadow: false) {
            VStack(alignment: .leading, spacing: 8) {
                Text("In this balance")
                    .font(.roundedBold(16))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(lineItem.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                Text(signedBalanceAmount(lineItem.signedAmount))
                    .font(.roundedBold(22))
                    .foregroundStyle(lineItem.signedAmount >= 0 ? AppTheme.expense : AppTheme.income)
                Text("Between \(firstName(debtor)) and \(firstName(creditor))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detailsCard: some View {
        CardContainer(showsShadow: false) {
            VStack(spacing: 0) {
                detailRow(label: "Paid by") {
                    memberRow(payer)
                }
                Divider()
                detailRow(label: "Received by") {
                    memberRow(payee)
                }
                Divider()
                detailRow(label: "Date") {
                    Text(settlement.date, format: .dateTime.weekday(.wide).month().day().year())
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
        }
    }

    private func memberRow(_ member: BudgetMember?) -> some View {
        HStack(spacing: 8) {
            if let member {
                MemberInitialsBadge(
                    initials: String(member.initials.prefix(1)).uppercased(),
                    colorHex: member.colorHex,
                    size: 24,
                    accessibilityLabel: "Member \(member.displayName)",
                    showsShadow: false
                )
                Text(member.displayName)
                    .foregroundStyle(AppTheme.textPrimary)
            } else {
                Text("Unknown")
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            cloudSyncStore.deleteSettlement(
                settlement,
                userScopeId: authStore.currentUserScopeId,
                budgetScopeId: authStore.currentBudgetScopeId
            )
            modelContext.delete(settlement)
            try? modelContext.save()
            dismiss()
        } label: {
            Label("Remove Settle Up Record", systemImage: "trash")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(AppTheme.expense)
        .controlSize(.large)
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

    private func signedBalanceAmount(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "−"
        return "\(sign)\(amount(abs(value)))"
    }

    private func amount(_ value: Double) -> String {
        CurrencyFormatter.amountString(value, symbol: currencySymbol)
    }

    private func firstName(_ member: BudgetMember) -> String {
        let first = member.displayName.split(separator: " ").first.map(String.init) ?? member.displayName
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? member.displayName : trimmed
    }
}

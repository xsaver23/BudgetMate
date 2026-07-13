import SwiftUI

struct TransactionRowView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    let transaction: Transaction
    let currencySymbol: String
    let members: [BudgetMember]

    private var amountColor: Color {
        transaction.type == .income ? AppTheme.incomeText : AppTheme.expenseText
    }

    private var signedAmount: String {
        let sign = transaction.type == .income ? "+" : "-"
        return "\(sign)\(CurrencyFormatter.numberString(transaction.amount))"
    }

    private var createdByMember: BudgetMember? {
        members.first(where: { $0.id == transaction.createdByMemberId })
    }

    private var categoryLine: String {
        if let paymentMethod = transaction.paymentMethod {
            return "\(transaction.category.displayName) • \(paymentMethod.displayName)"
        }

        return transaction.category.displayName
    }

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                CategoryIconView(
                    category: transaction.category,
                    emoji: settingsStore.categoryEmoji(for: transaction.category),
                    size: 38
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(transaction.title)
                            .font(.headline)
                        if let createdByMember {
                            MemberInitialsBadge(
                                initials: createdByMember.displayInitials,
                                colorHex: createdByMember.colorHex,
                                size: 22,
                                accessibilityLabel: "Added by \(createdByMember.displayName)"
                            )
                        }
                    }
                    Text(categoryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(signedAmount)
                        .font(.headline)
                        .foregroundStyle(amountColor)
                    Text(transaction.date, format: .dateTime.month().day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Lightweight transaction row used inside grouped day cards and dashboard
/// summaries. The payer's avatar leads the row for shared-context color-coding.
struct CompactTransactionRow: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    let transaction: Transaction
    let currencySymbol: String
    let members: [BudgetMember]

    private var createdByMember: BudgetMember? {
        members.first(where: { $0.id == transaction.createdByMemberId })
    }

    private var amountColor: Color {
        transaction.type == .income ? AppTheme.incomeText : AppTheme.expenseText
    }

    private var signedAmount: String {
        let sign = transaction.type == .income ? "+" : "-"
        return "\(sign)\(CurrencyFormatter.numberString(transaction.amount))"
    }

    private var categoryLine: String {
        var line = transaction.category.displayName
        if let paymentMethod = transaction.paymentMethod {
            line += " • \(paymentMethod.displayName)"
        }
        if transaction.isSplit {
            line += " • Split \(transaction.splits.count) ways"
        }
        if transaction.isMonthlyRecurring {
            line += " • Monthly"
        }
        return line
    }

    private var participantMembers: [BudgetMember] {
        transaction.participantIds.compactMap { id in
            members.first(where: { $0.id == id })
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            TransactionIdentityIcon(
                transaction: transaction,
                createdByMember: createdByMember,
                participantMembers: participantMembers,
                emoji: settingsStore.categoryEmoji(for: transaction.category)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.ink)
                    .lineLimit(1)
                Text(categoryLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BudgetBeaverPalette.wood)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(signedAmount)
                .font(.roundedBold(16))
                .foregroundStyle(transaction.type == .income ? AppTheme.brand : AppTheme.danger)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .contentShape(Rectangle())
    }
}

private struct TransactionIdentityIcon: View {
    let transaction: Transaction
    let createdByMember: BudgetMember?
    let participantMembers: [BudgetMember]
    let emoji: String?

    private var uniqueParticipantMembers: [BudgetMember] {
        participantMembers.reduce(into: [BudgetMember]()) { result, member in
            if !result.contains(where: { $0.id == member.id }) {
                result.append(member)
            }
        }
    }

    private var splitMembers: [BudgetMember] {
        Array(uniqueParticipantMembers.prefix(2))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CategoryIconView(
                category: transaction.category,
                emoji: emoji,
                size: 38
            )

            if transaction.isSplit && !splitMembers.isEmpty {
                HStack(spacing: -4) {
                    ForEach(splitMembers) { member in
                        MemberInitialsBadge(
                            initials: member.displayInitials,
                            colorHex: member.colorHex,
                            size: 17,
                            accessibilityLabel: "Split with \(member.displayName)"
                        )
                    }
                }
                .offset(x: 7, y: 7)
            } else if let createdByMember {
                MemberInitialsBadge(
                    initials: createdByMember.displayInitials,
                    colorHex: createdByMember.colorHex,
                    size: 18,
                    accessibilityLabel: "Added by \(createdByMember.displayName)"
                )
                .offset(x: 4, y: 4)
            }
        }
        .frame(width: 46, height: 46)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack {
        TransactionRowView(
            transaction: PreviewTransactions.samples[1],
            currencySymbol: "$",
            members: MemberSampleData.members
        )
        CompactTransactionRow(
            transaction: PreviewTransactions.samples[1],
            currencySymbol: "$",
            members: MemberSampleData.members
        )
        .padding()
        .background(AppTheme.surface)
    }
    .padding()
    .background(AppTheme.background)
    .environmentObject(SettingsStore())
}

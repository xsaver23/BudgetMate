import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction
    let currencySymbol: String
    let members: [BudgetMember]

    private var amountColor: Color {
        transaction.type == .income ? AppTheme.income : AppTheme.expense
    }

    private var signedAmount: String {
        let sign = transaction.type == .income ? "+" : "-"
        return "\(sign)\(CurrencyFormatter.amountString(transaction.amount, symbol: currencySymbol))"
    }

    private var createdByMember: BudgetMember? {
        members.first(where: { $0.id == transaction.createdByMemberId })
    }

    private var badgeInitials: String {
        createdByMember?.initials ?? "?"
    }

    private var badgeSymbol: String {
        String(badgeInitials.prefix(1)).uppercased()
    }

    private var badgeColor: String {
        createdByMember?.colorHex ?? "#9CA3AF"
    }

    private var badgeAccessibilityLabel: String {
        if let member = createdByMember {
            return "Added by \(member.displayName)"
        }
        return "Added by unknown member"
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
                Circle()
                    .fill(Color.black.opacity(0.06))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: transaction.type == .income ? "arrow.down.circle" : "arrow.up.circle")
                            .foregroundStyle(.primary)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(transaction.title)
                            .font(.headline)
                        MemberInitialsBadge(
                            initials: badgeSymbol,
                            colorHex: badgeColor,
                            size: 22,
                            accessibilityLabel: badgeAccessibilityLabel
                        )
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
    let transaction: Transaction
    let currencySymbol: String
    let members: [BudgetMember]

    private var createdByMember: BudgetMember? {
        members.first(where: { $0.id == transaction.createdByMemberId })
    }

    private var amountColor: Color {
        transaction.type == .income ? AppTheme.income : AppTheme.expense
    }

    private var signedAmount: String {
        let sign = transaction.type == .income ? "+" : "-"
        return "\(sign)\(CurrencyFormatter.amountString(transaction.amount, symbol: currencySymbol))"
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

    private var badgeSymbol: String {
        String((createdByMember?.initials ?? "?").prefix(1)).uppercased()
    }

    private var badgeAccessibilityLabel: String {
        if let member = createdByMember {
            return "Added by \(member.displayName)"
        }
        return "Added by unknown member"
    }

    private var participantMembers: [BudgetMember] {
        transaction.participantIds.compactMap { id in
            members.first(where: { $0.id == id })
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if transaction.isSplit {
                MemberAvatarCluster(members: participantMembers, size: 34)
                    .frame(minWidth: 78, alignment: .leading)
            } else {
                MemberInitialsBadge(
                    initials: badgeSymbol,
                    colorHex: createdByMember?.colorHex ?? "#9CA3AF",
                    size: 38,
                    accessibilityLabel: badgeAccessibilityLabel
                )
            }

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
}

import SwiftUI

struct SettlementListView: View {
    let suggestions: [SettlementSuggestion]
    let currencySymbol: String
    let onClose: () -> Void
    let onBreakdown: (SettlementSuggestion) -> Void
    let onSettle: (SettlementSuggestion) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if suggestions.isEmpty {
                        emptyState
                    } else {
                        ForEach(suggestions) { settlement in
                            settlementListRow(settlement)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 18)
            }
            .background(AppTheme.background)
            .navigationTitle("Who Owes Who")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                        .font(.headline.weight(.semibold))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(BudgetBeaverPalette.forest)
            Text("No split balances right now.")
                .font(.headline.weight(.bold))
                .foregroundStyle(BudgetBeaverPalette.ink)
            Text("When people owe each other money, each balance will show here.")
                .font(.subheadline)
                .foregroundStyle(BudgetBeaverPalette.grayText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(BudgetBeaverPalette.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BudgetBeaverPalette.border, lineWidth: 1)
        )
    }

    private func settlementListRow(_ settlement: SettlementSuggestion) -> some View {
        VStack(spacing: 12) {
            Button {
                onBreakdown(settlement)
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: -8) {
                        avatar(for: settlement.from)
                        avatar(for: settlement.to)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(firstName(settlement.from)) owes \(firstName(settlement.to))")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(BudgetBeaverPalette.ink)

                        Text("Tap for breakdown")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BudgetBeaverPalette.jenBlue)
                    }

                    Spacer(minLength: 8)

                    Text(amount(settlement.amount))
                        .font(.title3.weight(.black))
                        .foregroundStyle(BudgetBeaverPalette.amountRed)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.985, pressedOpacity: 0.9))

            Button {
                onSettle(settlement)
            } label: {
                Label("Settle Balance", systemImage: "checkmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(BudgetBeaverPalette.darkButton, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(16)
        .background(BudgetBeaverPalette.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BudgetBeaverPalette.border, lineWidth: 1)
        )
    }

    private func avatar(for member: BudgetMember) -> some View {
        Text(member.displayInitials)
            .font(.system(size: 20, weight: .black, design: .rounded))
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
            .background(Color(hex: member.colorHex), in: Circle())
            .overlay(Circle().stroke(BudgetBeaverPalette.paper, lineWidth: 3))
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

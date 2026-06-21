import SwiftUI

struct FirstRunIntroView: View {
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 24)

                VStack(spacing: 18) {
                    appMark

                    VStack(spacing: 10) {
                        Text("Welcome to BudgetMate")
                            .font(.roundedBold(30))
                            .foregroundStyle(BudgetBeaverPalette.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("A calmer place to track shared money.")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(BudgetBeaverPalette.wood)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .lineLimit(2)
                            .minimumScaleFactor(0.88)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)
                    }
                }

                VStack(spacing: 12) {
                    introRow(
                        icon: "creditcard",
                        title: "Track the money",
                        subtitle: "Log income and expenses without landing in a spreadsheet."
                    )
                    introRow(
                        icon: "person.2",
                        title: "Share the household view",
                        subtitle: "Split bills between members and keep everyone visible."
                    )
                    introRow(
                        icon: "checkmark.circle",
                        title: "Settle up clearly",
                        subtitle: "See simple balances when someone fronts a shared cost."
                    )
                }

                Spacer(minLength: 16)

                Button {
                    onContinue()
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.brand, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .buttonStyle(PressableButtonStyle(scale: 0.98))

                Text("You can adjust budget, currency, and household members in Settings.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
    }

    private var appMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.brand)
                .frame(width: 96, height: 96)

            Image(systemName: "chart.pie.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }

    private func introRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.brand)
                .frame(width: 38, height: 38)
                .background(Circle().fill(rowColor(for: icon)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.surfaceStroke, lineWidth: 1)
        )
    }

    private func rowColor(for icon: String) -> Color {
        switch icon {
        case "creditcard":
            return AppTheme.secondaryAction
        case "person.2":
            return AppTheme.income
        default:
            return BudgetBeaverPalette.jenBlue.opacity(0.45)
        }
    }
}

#Preview {
    FirstRunIntroView {}
}

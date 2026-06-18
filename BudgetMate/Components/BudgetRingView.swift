import SwiftUI

/// Custom ring chart used for budget pacing. Renders a track + a trimmed
/// progress arc with a stacked label in the center.
struct BudgetRingView: View {
    let progress: Double
    var lineWidth: CGFloat = 18
    var tint: Color = AppTheme.brand
    var trackColor: Color = AppTheme.brandSoft

    let centerCaption: String
    let centerValue: String
    var centerFootnote: String? = nil

    private var clamped: Double { min(max(progress, 0), 1) }
    private var isOver: Bool { progress > 1 }
    private var arcColor: Color { isOver ? AppTheme.expense : tint }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(arcColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 3) {
                Text(centerCaption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(centerValue)
                    .font(.roundedBold(28))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let centerFootnote {
                    Text(centerFootnote)
                        .font(.caption)
                        .foregroundStyle(isOver ? AppTheme.expense : AppTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(lineWidth + 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(centerCaption) \(centerValue). \(Int((clamped * 100).rounded())) percent of budget used.")
    }
}

#Preview {
    HStack(spacing: 24) {
        BudgetRingView(
            progress: 0.62,
            centerCaption: "Remaining",
            centerValue: "$760",
            centerFootnote: "of $2,000"
        )
        .frame(width: 170, height: 170)

        BudgetRingView(
            progress: 1.18,
            centerCaption: "Remaining",
            centerValue: "-$180",
            centerFootnote: "Over budget"
        )
        .frame(width: 170, height: 170)
    }
    .padding()
    .background(AppTheme.background)
}

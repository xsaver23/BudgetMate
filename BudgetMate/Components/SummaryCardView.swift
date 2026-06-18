import SwiftUI

struct SummaryCardView: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(AppTheme.textSecondary)

                Text(value)
                    .font(.roundedBold(22))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    SummaryCardView(title: "Current Balance", value: "$2,120.70", tint: .blue)
        .padding()
}

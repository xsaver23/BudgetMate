import SwiftUI

struct DamProgressBar: View {
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

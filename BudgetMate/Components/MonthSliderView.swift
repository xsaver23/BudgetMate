import SwiftUI

/// Month picker for the selected year. Uses chevron steppers to move between
/// months while keeping the selected month prominent.
struct MonthSliderView: View {
    @EnvironmentObject private var monthSelectionStore: MonthSelectionStore

    private var selectedIndex: Int { monthSelectionStore.selectedMonthIndex }

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MONTH")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BudgetBeaverPalette.wood)
                    Text(monthSelectionStore.selectedMonthTitle)
                        .font(.roundedBold(22))
                        .foregroundStyle(BudgetBeaverPalette.ink)
                        .animation(.easeOut(duration: 0.16), value: selectedIndex)
                }

                Spacer()

                stepper(systemImage: "chevron.left", enabled: selectedIndex > 0) {
                    monthSelectionStore.updateMonthIndex(selectedIndex - 1)
                }
                stepper(systemImage: "chevron.right", enabled: selectedIndex < 11) {
                    monthSelectionStore.updateMonthIndex(selectedIndex + 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stepper(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? AppTheme.brand : AppTheme.textSecondary.opacity(0.42))
                .frame(width: 34, height: 34)
                .background(Circle().fill(enabled ? AppTheme.background : AppTheme.surfaceAlt.opacity(0.6)))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.94))
        .disabled(!enabled)
        .accessibilityLabel(systemImage == "chevron.left" ? "Previous month" : "Next month")
    }
}

#Preview {
    MonthSliderView()
        .environmentObject(MonthSelectionStore())
        .padding()
        .background(AppTheme.background)
}

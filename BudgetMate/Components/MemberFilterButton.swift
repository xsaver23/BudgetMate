import SwiftUI

struct MemberFilterButton: View {
    let title: String
    let color: Color
    let isSelected: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 44, height: 44)
                .background(color, in: Circle())
                .overlay {
                    Circle()
                        .stroke(isSelected ? AppTheme.secondaryAction : .clear, lineWidth: 4)
                }
        }
        .buttonStyle(PressableButtonStyle(scale: 0.92))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

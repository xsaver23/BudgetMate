import SwiftUI

struct CategoryIconView: View {
    let category: TransactionCategory
    let emoji: String?
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .fill(CategoryColor.color(for: category).opacity(emoji == nil ? 1 : 0.18))
                .frame(width: size, height: size)

            if let emoji {
                Text(emoji)
                    .font(.system(size: size * 0.58))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

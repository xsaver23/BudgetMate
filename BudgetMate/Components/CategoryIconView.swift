import SwiftUI

struct CategoryIconView: View {
    let category: TransactionCategory
    let emoji: String?
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .fill(CategoryColor.color(for: category).opacity(emoji == nil ? 0.16 : 0.18))
                .frame(width: size, height: size)

            if let emoji {
                Text(emoji)
                    .font(.system(size: size * 0.58))
                    .frame(width: size, height: size)
            } else {
                Image(systemName: category.systemImageName)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(CategoryColor.textColor(for: category))
            }
        }
        .accessibilityHidden(true)
    }
}

private extension TransactionCategory {
    var systemImageName: String {
        switch self {
        case .food, .restaurant, .groceries: return "fork.knife"
        case .rent, .household: return "house"
        case .bills, .subscription: return "doc.text"
        case .studentLoans: return "graduationcap"
        case .health: return "cross.case"
        case .gift: return "gift"
        case .date: return "heart"
        case .vacation: return "airplane"
        case .parking, .gas, .transportation: return "car"
        case .shopping: return "bag"
        case .entertainment: return "play.tv"
        case .salary, .refund, .work, .eTransfer: return "arrow.down.left"
        case .other: return "ellipsis"
        default: return "tag"
        }
    }
}

private extension CategoryColor {
    static func textColor(for category: TransactionCategory) -> Color {
        switch category {
        case .food, .bills, .subscription, .gas, .shopping:
            return AppTheme.warningText
        case .restaurant, .health, .gift, .date:
            return AppTheme.expenseText
        case .groceries, .vacation, .salary, .refund, .work, .eTransfer:
            return AppTheme.incomeText
        case .studentLoans, .parking, .other:
            return AppTheme.textSecondary
        default:
            return AppTheme.brand
        }
    }
}

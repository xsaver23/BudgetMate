import SwiftUI

enum CategoryColor {
    static func color(for category: TransactionCategory) -> Color {
        switch category {
        case .food:
            return AppTheme.warning
        case .restaurant:
            return AppTheme.expense
        case .groceries:
            return AppTheme.income
        case .rent:
            return AppTheme.brand
        case .subscription:
            return AppTheme.warning
        case .health:
            return AppTheme.expense
        case .household:
            return AppTheme.brandAlt
        case .gift:
            return AppTheme.expense
        case .studentLoans:
            return BudgetBeaverPalette.purple
        case .date:
            return AppTheme.expense
        case .vacation:
            return AppTheme.income
        case .parking:
            return AppTheme.textMuted
        case .gas:
            return AppTheme.warning
        case .transportation:
            return AppTheme.brandAlt
        case .shopping:
            return AppTheme.secondaryAction
        case .entertainment:
            return BudgetBeaverPalette.purple
        case .bills:
            return AppTheme.warning
        case .salary:
            return AppTheme.income
        case .refund:
            return AppTheme.income
        case .work:
            return AppTheme.brandAlt
        case .eTransfer:
            return AppTheme.income
        case .other:
            return AppTheme.textMuted
        default:
            return customColor(for: category.rawValue)
        }
    }

    private static func customColor(for rawValue: String) -> Color {
        let palette: [Color] = [
            AppTheme.brand,
            AppTheme.income,
            AppTheme.expense,
            AppTheme.secondaryAction,
            BudgetBeaverPalette.purple,
            AppTheme.warning
        ]
        let hash = rawValue.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}

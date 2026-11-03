import SwiftUI
import UIKit

/// Central design tokens for the Ledger direction shared by iOS and web.
/// Change a value here and it propagates everywhere.
enum AppTheme {
    // Brand
    static let brand = Color(light: "#1E3A2B", dark: "#1E3A2B")
    static let brandAlt = Color(light: "#2C4A39", dark: "#315541")
    static let brandSoft = Color(light: "#E8F2EA", dark: "#203326")
    static let secondaryAction = Color(light: "#E7B84B", dark: "#F0C66A")
    static let secondaryActionText = Color(light: "#1F2419", dark: "#1F2419")

    // Foregrounds stay distinct from forest fills when they sit on dark surfaces.
    static let brandForeground = Color(light: "#1E3A2B", dark: "#B5DFB6")
    static let link = brandForeground
    static let selection = Color(light: "#8A650E", dark: "#F0C66A")

    // Surfaces
    static let background = Color(light: "#F8F4EC", dark: "#121710")
    static let surface = Color(light: "#FFFDF8", dark: "#1D241A")
    static let surfaceAlt = Color(light: "#F2EBDD", dark: "#252B21")
    static let colorBlockYellow = Color(light: "#F8F4EC", dark: "#252B21")
    static let surfaceStroke = Color(light: "#E4DAC8", dark: "#3A4334")
    static let track = Color(light: "#EEE6D7", dark: "#32382F")

    // Semantic
    static let income = Color(light: "#3F9E5E", dark: "#79C992")
    static let incomeTint = Color(light: "#E8F2EA", dark: "#203326")
    static let expense = Color(light: "#D6694C", dark: "#F19981")
    static let expenseTint = Color(light: "#FBEEEA", dark: "#3A241F")
    static let positive = income
    static let warning = Color(light: "#A6781C", dark: "#E7C36C")
    static let warningTint = Color(light: "#FBF1DC", dark: "#352C18")
    static let danger = Color(light: "#8A2F1F", dark: "#F19981")

    // Text
    static let textPrimary = Color(light: "#1F2419", dark: "#F7F2E7")
    static let textSecondary = Color(light: "#5E5D50", dark: "#C8C1B1")
    static let textMuted = Color(light: "#6F6D61", dark: "#9E988A")

    // Semantic foregrounds stay readable when the brighter chart colors are
    // used as fills, dots, or progress accents.
    static let incomeText = Color(light: "#2E7545", dark: "#79C992")
    static let expenseText = Color(light: "#A84734", dark: "#F19981")
    static let warningText = Color(light: "#7A5A14", dark: "#E7C36C")

    // Card metrics
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 14
    static let cardShadow = Color.clear
}

enum BudgetBeaverPalette {
    static let warmBackground = AppTheme.background
    static let ink = AppTheme.textPrimary
    static let wood = AppTheme.textSecondary
    static let paper = AppTheme.surface
    static let bank = AppTheme.surfaceAlt
    static let innerSurface = AppTheme.surface
    static let pill = AppTheme.brandSoft
    static let border = AppTheme.surfaceStroke
    static let water = AppTheme.link
    static let rebBrown = AppTheme.warning
    static let jenBlue = Color(hex: "#3B8FE2")
    static let darkButton = AppTheme.textPrimary
    static let amountDark = AppTheme.textPrimary
    static let amountRed = AppTheme.danger
    static let grayText = AppTheme.textSecondary
    static let muted = AppTheme.textMuted
    static let forest = AppTheme.income
    static let forestText = AppTheme.link
    static let forestSoft = AppTheme.incomeTint
    static let clay = AppTheme.expense
    static let amber = AppTheme.secondaryAction
    static let teal = AppTheme.positive
    static let purple = Color(hex: "#6F6CA8")
    static let coral = AppTheme.expense
}

extension Font {
    /// Rounded + bold display font used for amounts and primary headers.
    static func roundedBold(_ size: CGFloat) -> Font {
        .system(
            size: UIFontMetrics.default.scaledValue(for: size),
            weight: .bold,
            design: .rounded
        )
    }
}

/// Subtle press feedback for plain SwiftUI buttons. Use it when we opt out of
/// native button styles but still want the control to feel physically responsive.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var pressedOpacity: Double = 0.92

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? scale : 1))
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.16, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

/// Reusable Bright Household surface: cream cards, bold rounded corners, soft lift.
struct CardSurface: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = AppTheme.cardRadius
    var showsShadow: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.surfaceStroke, lineWidth: 1)
            )
            .shadow(
                color: showsShadow ? AppTheme.cardShadow : .clear,
                radius: showsShadow ? 10 : 0,
                x: 0,
                y: showsShadow ? 5 : 0
            )
    }
}

extension View {
    func cardSurface(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = AppTheme.cardRadius,
        showsShadow: Bool = true
    ) -> some View {
        modifier(CardSurface(padding: padding, cornerRadius: cornerRadius, showsShadow: showsShadow))
    }

    /// Paints the phone status-bar safe area so scrolling content cannot pass
    /// underneath the time, signal, or battery indicators.
    func statusBarScrim(_ color: Color = AppTheme.background) -> some View {
        overlay(alignment: .top) {
            GeometryReader { proxy in
                color
                    .frame(height: proxy.safeAreaInsets.top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension Color {
    /// Creates a color from a `#RRGGBB` (or `RRGGBB`) hex string. Falls back to gray.
    init(hex: String) {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard normalized.count == 6,
              let value = Int(normalized, radix: 16) else {
            self = .gray
            return
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        self = Color(red: red, green: green, blue: blue)
    }

    init(light: String, dark: String) {
        self = Color(uiColor: UIColor { traits in
            let selected = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(hex: selected)
        })
    }

    /// Picks a stable foreground for a stored member/category color. The
    /// identity color remains intact while initials stay readable in both
    /// light and dark appearances.
    static func accessibleForeground(forHex hex: String) -> Color {
        let background = UIColor(hex: hex)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard background.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return .white
        }

        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        let luminance = 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
        let lightContrast = (1.0 + 0.05) / (luminance + 0.05)
        let darkLuminance = 0.2126 * channel(0.0667) + 0.7152 * channel(0.0824) + 0.0722 * channel(0.0588)
        let darkContrast = (max(luminance, darkLuminance) + 0.05) / (min(luminance, darkLuminance) + 0.05)
        return lightContrast >= darkContrast ? Color(hex: "#FFFDF8") : Color(hex: "#11150F")
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard normalized.count == 6,
              let value = Int(normalized, radix: 16) else {
            self.init(white: 0.5, alpha: 1)
            return
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255

        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

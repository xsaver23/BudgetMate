import SwiftUI

/// Central design tokens for the Ledger direction shared by iOS and web.
/// Change a value here and it propagates everywhere.
enum AppTheme {
    // Brand
    static let brand = Color(hex: "#1E3A2B")
    static let brandAlt = Color(hex: "#2C4A39")
    static let brandSoft = Color(hex: "#E8F2EA")
    static let secondaryAction = Color(hex: "#E7B84B")
    static let secondaryActionText = Color(hex: "#1F2419")

    // Surfaces
    static let background = Color(light: "#FBF1DC", dark: "#121710")
    static let surface = Color(light: "#FFF7E8", dark: "#1D241A")
    static let surfaceAlt = Color(light: "#F5E9D2", dark: "#252B21")
    static let colorBlockYellow = Color(hex: "#FBF1DC")
    static let surfaceStroke = Color(light: "#EADFCA", dark: "#3A4334")
    static let track = Color(light: "#EEE6D7", dark: "#32382F")

    // Semantic
    static let income = Color(hex: "#3F9E5E")
    static let incomeTint = Color(hex: "#E8F2EA")
    static let expense = Color(hex: "#D6694C")
    static let expenseTint = Color(hex: "#FBEEEA")
    static let positive = Color(hex: "#3F9E5E")
    static let warning = Color(hex: "#A6781C")
    static let warningTint = Color(hex: "#FBF1DC")
    static let danger = Color(hex: "#8A2F1F")

    // Text
    static let textPrimary = Color(light: "#1F2419", dark: "#F7F2E7")
    static let textSecondary = Color(light: "#5E5D50", dark: "#C8C1B1")
    static let textMuted = Color(light: "#9A9788", dark: "#9E988A")

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
    static let water = AppTheme.brand
    static let rebBrown = AppTheme.warning
    static let jenBlue = Color(hex: "#3B8FE2")
    static let darkButton = AppTheme.textPrimary
    static let amountDark = AppTheme.textPrimary
    static let amountRed = AppTheme.danger
    static let grayText = AppTheme.textSecondary
    static let muted = AppTheme.textMuted
    static let forest = AppTheme.income
    static let forestText = AppTheme.brand
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
        .system(size: size, weight: .bold, design: .rounded)
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

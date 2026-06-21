import SwiftUI

/// Central design tokens for the "Bright Household Hub" direction.
/// Change a value here and it propagates everywhere.
enum AppTheme {
    // Brand
    static let brand = Color(hex: "#173404")
    static let brandSoft = Color(hex: "#173404").opacity(0.12)
    static let secondaryAction = Color(hex: "#FFCF70")
    static let secondaryActionText = Color(hex: "#3F2109")

    // Surfaces
    static let background = Color(light: "#FAEEDA", dark: "#141B10")
    static let surface = Color(light: "#FFFDF7", dark: "#202B1A")
    static let surfaceAlt = Color(light: "#F5E6C9", dark: "#2B351F")
    static let colorBlockYellow = Color(hex: "#FFCA6A")
    static let surfaceStroke = Color(light: "#7A4A14", dark: "#FAEEDA").opacity(0.10)

    // Semantic
    static let income = Color(hex: "#9CC957")
    static let expense = Color(hex: "#F49379")
    static let positive = Color(hex: "#1FA37D")
    static let warning = Color(hex: "#9A5308")
    static let danger = Color(hex: "#7D2B17")

    // Text
    static let textPrimary = Color(light: "#173404", dark: "#F9F0DA")
    static let textSecondary = Color(light: "#8B4E0A", dark: "#E4BE83")

    // Card metrics
    static let cardRadius: CGFloat = 22
    static let cardShadow = Color(hex: "#7A4A14").opacity(0.06)
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
    static let muted = AppTheme.textSecondary
    static let forest = AppTheme.income
    static let forestText = AppTheme.brand
    static let forestSoft = AppTheme.income.opacity(0.22)
    static let clay = AppTheme.expense
    static let amber = AppTheme.secondaryAction
    static let teal = Color(hex: "#1FA37D")
    static let purple = Color(hex: "#7B6EE6")
    static let coral = Color(hex: "#E2572E")
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

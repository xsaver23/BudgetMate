import SwiftUI

/// Central design tokens for the "Card-based Modern" direction.
/// Change a value here and it propagates everywhere.
enum AppTheme {
    // Brand
    static let brand = Color(hex: "#2563EB")
    static let brandSoft = Color(hex: "#2563EB").opacity(0.12)

    // Surfaces
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfaceStroke = Color.primary.opacity(0.08)

    // Semantic
    static let income = Color(hex: "#16A34A")
    static let expense = Color(hex: "#DC2626")
    static let positive = Color(hex: "#0D9488")
    static let warning = Color(hex: "#EA580C")

    // Text
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    // Card metrics
    static let cardRadius: CGFloat = 16
    static let cardShadow = Color.black.opacity(0.05)
}

enum BudgetBeaverPalette {
    static let warmBackground = AppTheme.background
    static let ink = AppTheme.textPrimary
    static let wood = AppTheme.textSecondary
    static let paper = AppTheme.surface
    static let bank = Color(uiColor: .tertiarySystemGroupedBackground)
    static let innerSurface = Color(uiColor: .systemGroupedBackground)
    static let pill = AppTheme.brandSoft
    static let border = AppTheme.surfaceStroke
    static let water = AppTheme.brand
    static let rebBrown = AppTheme.warning
    static let jenBlue = AppTheme.brand
    static let darkButton = AppTheme.textPrimary
    static let amountDark = AppTheme.textPrimary
    static let amountRed = AppTheme.expense
    static let grayText = AppTheme.textSecondary
    static let muted = AppTheme.textSecondary
    static let forest = AppTheme.income
    static let forestText = AppTheme.income
    static let forestSoft = AppTheme.income.opacity(0.10)
    static let clay = AppTheme.warning
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

/// Reusable "Card-based Modern" surface: adaptive fill, soft rounded corners, soft shadow.
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
                radius: showsShadow ? 8 : 0,
                x: 0,
                y: showsShadow ? 3 : 0
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
}

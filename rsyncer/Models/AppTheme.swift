import AppKit
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    /// `blue` keeps the old `deepBlue` raw value so themes already saved to UserDefaults still resolve.
    case lightPurple, lightBlue, yellow, red, blue = "deepBlue", deepGreen

    static let storageKey = "theme"
    static var current: AppTheme {
        get { AppTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .lightPurple }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lightPurple: return "Light purple"
        case .lightBlue: return "Light blue"
        case .yellow: return "Yellow"
        case .red: return "Red"
        case .blue: return "Blue"
        case .deepGreen: return "Deep green"
        }
    }

    /// Tint for controls, icons and filled badges. Dark enough to carry white text.
    var accent: Color {
        switch self {
        case .lightPurple: return Color(red: 0.45, green: 0.33, blue: 0.72)
        case .lightBlue: return Color(red: 0.05, green: 0.44, blue: 0.95)
        case .yellow: return Color(red: 0.60, green: 0.45, blue: 0.08)
        case .red: return Color(red: 0.70, green: 0.21, blue: 0.21)
        case .blue: return Color(red: 0.16, green: 0.46, blue: 0.72)
        case .deepGreen: return Color(red: 0.19, green: 0.43, blue: 0.34)
        }
    }

    /// Vivid companion used for progress, arrows and other highlights.
    var accentBright: Color {
        switch self {
        case .lightPurple: return Color(red: 0.66, green: 0.52, blue: 0.96)
        case .lightBlue: return Color(red: 0.16, green: 0.74, blue: 1.00)
        case .yellow: return Color(red: 0.86, green: 0.63, blue: 0.10)
        case .red: return Color(red: 0.95, green: 0.42, blue: 0.38)
        case .blue: return Color(red: 0.33, green: 0.72, blue: 0.98)
        case .deepGreen: return Color(red: 0.29, green: 0.82, blue: 0.60)
        }
    }

    /// Soft tint for marks drawn on the dark sidebar, where `accent` would be too dim.
    var soft: Color {
        switch self {
        case .lightPurple: return Color(red: 0.78, green: 0.70, blue: 0.98)
        case .lightBlue: return Color(red: 0.56, green: 0.87, blue: 1.00)
        case .yellow: return Color(red: 0.97, green: 0.85, blue: 0.50)
        case .red: return Color(red: 0.98, green: 0.66, blue: 0.62)
        case .blue: return Color(red: 0.62, green: 0.84, blue: 0.99)
        case .deepGreen: return Color(red: 0.65, green: 0.85, blue: 0.62)
        }
    }

    /// Sidebar backdrop. Always dark so the white sidebar text stays readable.
    var sidebar: Color {
        switch self {
        case .lightPurple: return Color(red: 0.16, green: 0.13, blue: 0.24)
        case .lightBlue: return Color(red: 0.05, green: 0.12, blue: 0.26)
        case .yellow: return Color(red: 0.18, green: 0.14, blue: 0.05)
        case .red: return Color(red: 0.20, green: 0.08, blue: 0.08)
        case .blue: return Color(red: 0.08, green: 0.15, blue: 0.23)
        case .deepGreen: return Color(red: 0.09, green: 0.15, blue: 0.14)
        }
    }
}

enum Palette {
    static var theme: AppTheme { AppTheme.current }
    static var accent: Color { theme.accent }
    static var accentBright: Color { theme.accentBright }
    static var soft: Color { theme.soft }
    static var sidebar: Color { theme.sidebar }

    /// Page backdrop. Light mode is a soft grey so white cards read as raised surfaces against it;
    /// the system window color is nearly white and leaves cards invisible.
    static let canvas = dynamic(light: NSColor(white: 0.929, alpha: 1), dark: .windowBackgroundColor)
    /// Card face. Light mode is plain white against the grey canvas; dark mode lifts off the backdrop.
    static let cardFill = dynamic(light: .white, dark: NSColor(white: 1, alpha: 0.055))
    /// Card outline. Firm enough in light mode to hold an edge where the shadow is subtle.
    static let cardStroke = dynamic(light: NSColor(white: 0, alpha: 0.13), dark: NSColor(white: 1, alpha: 0.11))
    /// Drop shadow under cards. Dark mode relies on the lighter fill instead.
    static let cardShadow = dynamic(light: NSColor(white: 0, alpha: 0.10), dark: .clear)
    /// Panels recessed into a card, such as path fields and option groups.
    static let insetFill = dynamic(light: NSColor(white: 0, alpha: 0.045), dark: NSColor(white: 1, alpha: 0.05))

    /// Resolves per appearance so `Palette` can stay static instead of threading `colorScheme` through views.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light })
    }
}

/// Shared card treatment: fill, outline and a light-mode shadow, so every surface separates
/// from the page the same way in both appearances.
struct CardSurface: ViewModifier {
    var radius: CGFloat
    var fill: Color
    var stroke: Color
    var dash: [CGFloat]

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(stroke, style: StrokeStyle(lineWidth: 1, dash: dash)) }
            .shadow(color: Palette.cardShadow, radius: 3, y: 1)
    }
}

extension View {
    func cardSurface(radius: CGFloat = 12, fill: Color = Palette.cardFill,
                     stroke: Color = Palette.cardStroke, dash: [CGFloat] = []) -> some View {
        modifier(CardSurface(radius: radius, fill: fill, stroke: stroke, dash: dash))
    }
}

import SwiftUI

/// Palette and materials for the app's 1980s portable-cassette-player look.
///
/// Modelled on the charcoal-and-brushed-aluminium Walkman decks (WM-D6C era)
/// rather than the silver TPS-L2, so the design stays comfortable in dark mode:
/// dark plastic chassis, metal faceplates, amber indicators.
enum Theme {

    /// The plastic chassis the whole device is moulded from.
    static let background = Color(red: 0.086, green: 0.086, blue: 0.094)

    /// Slightly raised plastic, for panels sitting on the chassis.
    static let surface = Color(red: 0.137, green: 0.137, blue: 0.149)

    /// Recessed wells: the tape window, the text slot.
    static let recess = Color(red: 0.043, green: 0.043, blue: 0.047)

    /// Amber, as used for record lamps and level indicators.
    static let accent = Color(red: 0.96, green: 0.45, blue: 0.09)

    /// The brighter lamp colour, for the "power on" LED.
    static let led = Color(red: 1.0, green: 0.32, blue: 0.14)

    /// Cassette paper labels — slightly warm off-white.
    static let label = Color(red: 0.90, green: 0.88, blue: 0.83)

    static let primaryText = Color(red: 0.92, green: 0.92, blue: 0.90)
    static let secondaryText = Color.white.opacity(0.45)

    /// Engraved legends on the metal, like silkscreened button labels.
    static let legend = Color.white.opacity(0.55)

    static let border = Color.black.opacity(0.6)
    static let highlight = Color.white.opacity(0.14)

    static let cornerRadius: CGFloat = 6

    /// Brushed aluminium, used for faceplates and key caps.
    static var brushedMetal: LinearGradient {
        LinearGradient(
            colors: [
                Color(white: 0.34),
                Color(white: 0.22),
                Color(white: 0.27),
                Color(white: 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The darker metal used for the chassis faceplate behind controls.
    static var darkMetal: LinearGradient {
        LinearGradient(
            colors: [Color(white: 0.20), Color(white: 0.13), Color(white: 0.16)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// A raised plastic/metal panel with a lit top edge and a shadowed bottom edge.
///
/// Can be hidden rather than removed, so whatever it wraps keeps its identity —
/// a player inside would otherwise be torn down and restarted.
struct RaisedPanel: ViewModifier {
    var cornerRadius: CGFloat = Theme.cornerRadius
    var isShown = true

    func body(content: Content) -> some View {
        content
            .background(Theme.surface.opacity(isShown ? 1 : 0), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Theme.highlight, .clear, Color.black.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .opacity(isShown ? 1 : 0)
            )
            .shadow(color: .black.opacity(isShown ? 0.5 : 0), radius: 4, y: 2)
    }
}

/// A well cut into the chassis: dark, with the shadow on the *inside* top edge.
/// Hides like `RaisedPanel`.
struct RecessedWell: ViewModifier {
    var cornerRadius: CGFloat = Theme.cornerRadius
    var isShown = true

    func body(content: Content) -> some View {
        content
            .background(Theme.recess.opacity(isShown ? 1 : 0), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.black.opacity(0.9), .clear, Theme.highlight],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .opacity(isShown ? 1 : 0)
            )
    }
}

extension View {
    func raisedPanel(cornerRadius: CGFloat = Theme.cornerRadius, isShown: Bool = true) -> some View {
        modifier(RaisedPanel(cornerRadius: cornerRadius, isShown: isShown))
    }

    func recessedWell(cornerRadius: CGFloat = Theme.cornerRadius, isShown: Bool = true) -> some View {
        modifier(RecessedWell(cornerRadius: cornerRadius, isShown: isShown))
    }

    /// Silkscreened legend text, as printed next to controls on the case.
    func legendStyle() -> some View {
        font(.system(size: 10, weight: .semibold, design: .default))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(Theme.legend)
    }
}

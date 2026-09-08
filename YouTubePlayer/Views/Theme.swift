import SwiftUI

/// The app's dark palette, kept in one place so the player, history and controls
/// stay visually consistent.
enum Theme {

    /// Page background — near-black, so video content is the brightest thing on screen.
    static let background = Color(red: 0.043, green: 0.043, blue: 0.055)

    /// Raised surfaces: input rows, cards, list rows.
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.13)

    /// Hairline separators and control outlines.
    static let border = Color.white.opacity(0.10)

    /// Brand accent used for primary actions.
    static let accent = Color(red: 0.94, green: 0.17, blue: 0.20)

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.58)

    static let cornerRadius: CGFloat = 14
}

/// Standard card container for a block of controls.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

import SwiftUI

// MARK: - Transport keys

/// The chunky rectangular keys of a cassette deck. Real transport keys are
/// squared-off and travel downward when pressed, so the style shifts the cap
/// down and collapses its shadow rather than fading it.
struct DeckKeyStyle: ButtonStyle {

    var width: CGFloat = 62
    var height: CGFloat = 46
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        return configuration.label
            .font(.system(size: 17, weight: .black))
            .foregroundStyle(tint ?? Theme.primaryText)
            .frame(width: width, height: height)
            .background(
                // The shadow belongs to the key cap alone — putting it on the
                // whole button would emboss the glyph too and muddy it.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.brushedMetal)
                    .overlay(
                        // Lit top edge and dark bottom edge give the cap its moulding.
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.35), .clear, Color.black.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.8), radius: 0, y: pressed ? 1 : 4)
            )
            .offset(y: pressed ? 3 : 0)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// A transport key with its silkscreened legend printed underneath, deck-style.
struct DeckKey<Label: View>: View {

    let legend: String
    var width: CGFloat = 62
    var tint: Color?
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action, label: label)
                .buttonStyle(DeckKeyStyle(width: width, tint: tint))
            Text(legend)
                .legendStyle()
        }
    }
}

// MARK: - Tape transport

/// A cassette hub: the toothed centre plus the tape wound around it.
struct TapeReel: View {

    var diameter: CGFloat = 34

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.12))

            // Wound tape, slightly glossy.
            Circle()
                .strokeBorder(Color(white: 0.18), lineWidth: diameter * 0.18)
                .padding(diameter * 0.06)

            // The six drive teeth of a cassette hub.
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(Color(white: 0.42))
                    .frame(width: diameter * 0.07, height: diameter * 0.22)
                    .offset(y: -diameter * 0.17)
                    .rotationEffect(.degrees(Double(index) / 6 * 360))
            }

            Circle()
                .fill(Color(white: 0.08))
                .frame(width: diameter * 0.2)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Two hubs that turn while the tape is running.
///
/// The rotation is derived from the timeline's own clock rather than an
/// animation on state, so pausing simply stops the clock and the reels hold
/// their position instead of snapping back to zero.
struct TapeTransport: View {

    let isRunning: Bool
    var diameter: CGFloat = 34

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isRunning)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate * 55

            HStack(spacing: 26) {
                TapeReel(diameter: diameter).rotationEffect(.degrees(angle))
                TapeReel(diameter: diameter).rotationEffect(.degrees(angle))
            }
        }
    }
}

/// The mechanical tape counter — three digits behind a small window.
struct TapeCounter: View {

    let seconds: TimeInterval

    private var digits: String {
        guard seconds.isFinite, seconds >= 0 else { return "000" }
        return String(format: "%03d", Int(seconds) % 1000)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                Text(String(digit))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.label)
                    .frame(width: 15, height: 22)
                    .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 2))
                    .overlay(
                        // The seam across the middle of a counter drum.
                        Rectangle()
                            .fill(Color.black.opacity(0.55))
                            .frame(height: 1)
                    )
            }
        }
        .padding(3)
        .background(Color(white: 0.03), in: RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Chassis details

/// The embossed brand plate on the front of the case.
struct Wordmark: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 19, weight: .heavy))
            .tracking(3.5)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(white: 0.95), Color(white: 0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: .black.opacity(0.9), radius: 0, y: 1)
    }
}

/// A power/status lamp. Lit lamps get a soft bloom, like a real LED behind plastic.
struct IndicatorLamp: View {

    let isLit: Bool
    var color: Color = Theme.led
    var diameter: CGFloat = 8

    var body: some View {
        Circle()
            .fill(isLit ? color : color.opacity(0.18))
            .frame(width: diameter, height: diameter)
            .overlay(Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1))
            .shadow(color: isLit ? color.opacity(0.85) : .clear, radius: 5)
            .animation(.easeInOut(duration: 0.2), value: isLit)
    }
}

/// A case screw, for the corners of metal plates.
struct CaseScrew: View {
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.30), Color(white: 0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 7, height: 7)
            .overlay(
                Rectangle()
                    .fill(Color.black.opacity(0.65))
                    .frame(width: 5, height: 1)
                    .rotationEffect(.degrees(35))
            )
            .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 0.5))
    }
}

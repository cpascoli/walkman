import SwiftUI

/// The tape that's playing, seen in the deck with the door open: a compact
/// cassette with the video's artwork printed on its label, the tape packs and
/// hubs showing through the window, and the deck's head and pinch roller
/// reaching into the openings along the bottom edge.
///
/// Laid out in fractions of the shell, using the real proportions of a compact
/// cassette (100.4 × 63.8 mm) so it reads right at any width.
struct CassetteView: View {

    let title: String
    let thumbnailURL: URL?
    let isRunning: Bool
    /// How far through the tape we are, 0...1. Nil when unknown (livestreams,
    /// the embedded player), which leaves the tape wound half and half.
    var progress: Double?
    /// Written on the label next to the title, e.g. "3:42".
    var length: String?

    static let aspectRatio: CGFloat = 100.4 / 63.8

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(size: geometry.size)

            ZStack(alignment: .topLeading) {
                shell(layout)
                TapeWindow(layout: layout, isRunning: isRunning, progress: progress ?? 0.5)
                label(layout)
                windowGlass(layout)
                headArea(layout)
                screws(layout)
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .shadow(color: .black.opacity(0.7), radius: 6, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cassette: \(title)")
        .accessibilityIdentifier("cassette")
    }

    // MARK: - Shell

    /// Smoked plastic, like the translucent black shells of the 80s.
    private func shell(_ layout: Layout) -> some View {
        RoundedRectangle(cornerRadius: layout.w * 0.035)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.21), Color(white: 0.13), Color(white: 0.16)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: layout.w * 0.035)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), .clear, Color.black.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .frame(width: layout.w, height: layout.h)
    }

    // MARK: - Label

    private func label(_ layout: Layout) -> some View {
        let rect = layout.label
        let window = layout.window.offsetBy(dx: -rect.minX, dy: -rect.minY)
        let bandHeight = layout.h * 0.15

        return ZStack(alignment: .top) {
            artwork
                .frame(width: rect.width, height: rect.height)
                .clipped()

            // The strip along the top you'd write the title on.
            titleBand(layout, height: bandHeight)
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(RoundedRectangle(cornerRadius: layout.w * 0.018))
        // Printed paper: a thin margin, then the window punched out of it.
        .overlay(
            RoundedRectangle(cornerRadius: layout.w * 0.018)
                .strokeBorder(Theme.label, lineWidth: layout.w * 0.008)
        )
        .mask(
            LabelCutout(window: window, cornerRadius: window.height / 2)
                .fill(style: FillStyle(eoFill: true))
        )
        .overlay(alignment: .topLeading) {
            // The lip of the window, shadowed where it meets the plastic below.
            RoundedRectangle(cornerRadius: window.height / 2)
                .strokeBorder(Color.black.opacity(0.55), lineWidth: 1.5)
                .frame(width: window.width, height: window.height)
                .offset(x: window.minX, y: window.minY)
        }
        .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
        .offset(x: rect.minX, y: rect.minY)
    }

    private var artwork: some View {
        AsyncImage(url: thumbnailURL) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
                    // Ink on paper is never quite as punchy as a screen.
                    .saturation(0.88)
                    .overlay(Theme.label.opacity(0.1).blendMode(.multiply))
            } else {
                // Blank label stock until the artwork arrives.
                LinearGradient(
                    colors: [Theme.label, Theme.label.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func titleBand(_ layout: Layout, height: CGFloat) -> some View {
        HStack(spacing: layout.w * 0.025) {
            Text("A")
                .font(.system(size: height * 0.62, weight: .black))
                .foregroundStyle(Color(white: 0.12))

            Text(title)
                .font(.custom("Marker Felt", size: height * 0.5))
                .foregroundStyle(Self.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let length {
                Text(length)
                    .font(.custom("Marker Felt", size: height * 0.42))
                    .foregroundStyle(Self.ink)
            }
        }
        .padding(.horizontal, layout.w * 0.03)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(
            // Ruled like a real insert.
            Theme.label.overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(red: 0.75, green: 0.3, blue: 0.2).opacity(0.55))
                    .frame(height: 1)
                    .padding(.bottom, height * 0.16)
            }
        )
    }

    /// Ballpoint blue.
    private static let ink = Color(red: 0.12, green: 0.17, blue: 0.42)

    // MARK: - Window glass

    /// The clear plastic over the window catches a diagonal highlight.
    private func windowGlass(_ layout: Layout) -> some View {
        let window = layout.window
        return RoundedRectangle(cornerRadius: window.height / 2)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.0), location: 0.25),
                        .init(color: .white.opacity(0.10), location: 0.4),
                        .init(color: .white.opacity(0.0), location: 0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: window.width, height: window.height)
            .offset(x: window.minX, y: window.minY)
            .allowsHitTesting(false)
    }

    // MARK: - Head area

    /// The raised trapezoid along the bottom edge, with its openings, the tape
    /// running across them, and the deck's head and pinch roller reaching in.
    private func headArea(_ layout: Layout) -> some View {
        let w = layout.w, h = layout.h
        let openingTop = h * 0.9
        let openingHeight = h - openingTop
        let tapeY = h * 0.955

        return ZStack(alignment: .topLeading) {
            HeadAreaShape()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.24), Color(white: 0.17)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(HeadAreaShape().stroke(Color.black.opacity(0.5), lineWidth: 1))
                .frame(width: w, height: h * 0.24)
                .offset(y: h * 0.76)

            // Capstan and guide holes.
            ForEach([-0.27, 0.27], id: \.self) { dx in
                Circle()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: w * 0.03)
                    .position(x: w * (0.5 + dx), y: h * 0.86)
            }

            // Openings: pinch rollers either side, the head in the middle.
            ForEach(Self.openings, id: \.x) { opening in
                Rectangle()
                    .fill(Color.black.opacity(0.9))
                    .frame(width: w * opening.width, height: openingHeight)
                    .position(x: w * opening.x, y: openingTop + openingHeight / 2)
            }

            // The deck's playback head, pressed up against the tape.
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.85), Color(white: 0.5), Color(white: 0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: w * 0.08, height: openingHeight * 0.75)
                .position(x: w * 0.5, y: h - openingHeight * 0.3)

            // Rubber pinch roller, in the right-hand opening.
            Circle()
                .fill(Color(white: 0.05))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                .frame(width: openingHeight * 0.85)
                .position(x: w * 0.68, y: h - openingHeight * 0.35)

            // The tape itself, running across the front edge.
            Rectangle()
                .fill(Self.tapeBrown)
                .frame(width: w * 0.52, height: max(1.5, h * 0.012))
                .position(x: w * 0.5, y: tapeY)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: w * 0.035))
    }

    private struct Opening { let x: CGFloat; let width: CGFloat }
    private static let openings = [
        Opening(x: 0.32, width: 0.06),
        Opening(x: 0.5, width: 0.12),
        Opening(x: 0.68, width: 0.06)
    ]

    static let tapeBrown = Color(red: 0.27, green: 0.16, blue: 0.09)

    // MARK: - Screws

    private func screws(_ layout: Layout) -> some View {
        let points: [CGPoint] = [
            CGPoint(x: 0.035, y: 0.055), CGPoint(x: 0.965, y: 0.055),
            CGPoint(x: 0.035, y: 0.945), CGPoint(x: 0.965, y: 0.945),
            CGPoint(x: 0.5, y: 0.82)
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(points.indices, id: \.self) { index in
                let point = points[index]
                CaseScrew()
                    .position(x: layout.w * point.x, y: layout.h * point.y)
            }
        }
        .frame(width: layout.w, height: layout.h, alignment: .topLeading)
    }
}

// MARK: - Layout

extension CassetteView {

    /// Where things sit on the shell, from real cassette measurements.
    struct Layout {
        let w: CGFloat
        let h: CGFloat

        init(size: CGSize) {
            w = size.width
            h = size.height
        }

        /// Hub centres: 42.5 mm apart, a little above the middle.
        var leftHub: CGPoint { CGPoint(x: w * 0.2885, y: h * 0.45) }
        var rightHub: CGPoint { CGPoint(x: w * 0.7115, y: h * 0.45) }

        /// The white hub ring.
        var hubRadius: CGFloat { w * 0.055 }
        /// A full pack. Two packs, one full and one bare, just clear each other.
        var maxPackRadius: CGFloat { w * 0.19 }

        var label: CGRect { CGRect(x: w * 0.05, y: h * 0.06, width: w * 0.9, height: h * 0.64) }

        /// A stadium around both hubs.
        var window: CGRect {
            let margin = w * 0.02
            let radius = hubRadius + margin
            return CGRect(
                x: leftHub.x - radius,
                y: leftHub.y - radius,
                width: rightHub.x - leftHub.x + radius * 2,
                height: radius * 2
            )
        }
    }
}

// MARK: - Window contents

/// What you see through the window: the tape wound on two packs and the hubs
/// turning. The packs trade tape as playback progresses, and each hub turns at
/// the speed its pack demands — the bare one spins fast, the full one slowly.
private struct TapeWindow: View {

    let layout: CassetteView.Layout
    let isRunning: Bool
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = ReelClock()

    var body: some View {
        let supply = packRadius(fill: 1 - progress)
        let takeUp = packRadius(fill: progress)

        ZStack(alignment: .topLeading) {
            // Deeper smoke behind the window.
            RoundedRectangle(cornerRadius: layout.window.height / 2)
                .fill(Color.black.opacity(0.2))
                .frame(width: layout.window.width, height: layout.window.height)
                .offset(x: layout.window.minX, y: layout.window.minY)

            WindowScale(layout: layout)

            // Inside the shell, so only what's behind the window shows.
            ZStack(alignment: .topLeading) {
                TapePack(radius: supply).position(layout.leftHub)
                TapePack(radius: takeUp).position(layout.rightHub)
            }
            .frame(width: layout.w, height: layout.h, alignment: .topLeading)
            .mask(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: layout.window.height / 2)
                    .frame(width: layout.window.width, height: layout.window.height)
                    .offset(x: layout.window.minX, y: layout.window.minY)
            }

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isRunning || reduceMotion)) { context in
                let angles = clock.advance(
                    to: context.date,
                    running: isRunning && !reduceMotion,
                    // Constant tape speed means angular speed goes as 1/radius.
                    leftSpeed: Self.bareHubSpeed * layout.hubRadius / supply,
                    rightSpeed: Self.bareHubSpeed * layout.hubRadius / takeUp
                )

                ZStack(alignment: .topLeading) {
                    Hub(radius: layout.hubRadius)
                        .rotationEffect(.degrees(angles.left))
                        .position(layout.leftHub)
                    Hub(radius: layout.hubRadius)
                        .rotationEffect(.degrees(angles.right))
                        .position(layout.rightHub)
                }
            }
        }
        .frame(width: layout.w, height: layout.h, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.8), value: progress)
    }

    /// Degrees per second for a hub with no tape on it.
    private static let bareHubSpeed = 220.0

    /// Tape area is conserved, so the radius goes as the square root of the fill.
    private func packRadius(fill: Double) -> CGFloat {
        let bare = layout.hubRadius * 1.05
        let full = layout.maxPackRadius
        let clamped = min(max(fill, 0), 1)
        return sqrt(bare * bare + (full * full - bare * bare) * clamped)
    }
}

/// The little printed scale between the hubs, for judging how much tape is left.
private struct WindowScale: View {
    let layout: CassetteView.Layout

    var body: some View {
        let window = layout.window
        let span = (layout.rightHub.x - layout.leftHub.x) * 0.36
        let ticks = 7

        ZStack(alignment: .topLeading) {
            ForEach(0..<ticks, id: \.self) { index in
                let x = layout.w / 2 - span / 2 + span * CGFloat(index) / CGFloat(ticks - 1)
                let long = index % 3 == 0
                ForEach([window.minY + 3, window.maxY - 3], id: \.self) { edge in
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 0.75, height: long ? window.height * 0.12 : window.height * 0.07)
                        .position(x: x, y: edge < layout.leftHub.y
                            ? edge + (long ? window.height * 0.06 : window.height * 0.035)
                            : edge - (long ? window.height * 0.06 : window.height * 0.035))
                }
            }
        }
        .frame(width: layout.w, height: layout.h, alignment: .topLeading)
    }
}

/// Accumulates each hub's angle frame by frame, so a change of speed never
/// makes a hub jump and a paused tape holds its position.
private final class ReelClock {
    private var last: Date?
    private var left = 0.0
    private var right = 17.0

    func advance(to date: Date, running: Bool, leftSpeed: Double, rightSpeed: Double) -> (left: Double, right: Double) {
        defer { last = date }
        guard running, let last else { return (left, right) }
        // After a pause the timeline resumes with a stale date; don't lurch.
        let dt = min(date.timeIntervalSince(last), 1.0 / 15.0)
        left = (left + leftSpeed * dt).truncatingRemainder(dividingBy: 360)
        right = (right + rightSpeed * dt).truncatingRemainder(dividingBy: 360)
        return (left, right)
    }
}

/// Tape wound on a hub: glossy brown, with faint winding lines.
private struct TapePack: View {
    let radius: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [CassetteView.tapeBrown, Color(red: 0.36, green: 0.22, blue: 0.13), CassetteView.tapeBrown],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            ForEach([0.55, 0.75, 0.92], id: \.self) { fraction in
                Circle()
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
                    .padding(radius * (1 - fraction))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

/// A cassette hub: a white ring with six teeth pointing in, gripping the
/// deck's three-splined spindle in the middle.
private struct Hub: View {
    let radius: CGFloat

    var body: some View {
        let hole = radius * 0.62

        ZStack {
            Circle()
                .fill(Color(white: 0.93))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 0.5))

            Circle()
                .fill(Color(white: 0.07))
                .frame(width: hole * 2)

            ForEach(0..<6, id: \.self) { index in
                Rectangle()
                    .fill(Color(white: 0.93))
                    .frame(width: radius * 0.16, height: radius * 0.24)
                    .offset(y: -hole + radius * 0.1)
                    .rotationEffect(.degrees(Double(index) * 60))
            }

            // The deck spindle, turning with the hub it drives.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.75), Color(white: 0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: hole * 0.7)
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(Color(white: 0.55))
                    .frame(width: radius * 0.12, height: hole * 0.5)
                    .offset(y: -hole * 0.4)
                    .rotationEffect(.degrees(Double(index) * 120 + 30))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

// MARK: - Shapes

/// The label with the window punched out, for an even-odd fill.
private struct LabelCutout: Shape {
    let window: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: window, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        return path
    }
}

/// The raised section along the bottom edge: narrower at the top.
private struct HeadAreaShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.22, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 0.78, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 0.85, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width * 0.15, y: rect.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Deck well

/// The open deck the cassette sits in: the door's hinge knuckles along the
/// top edge and a little room around the shell.
struct CassetteBay<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                HStack {
                    hinge
                    Spacer()
                    hinge
                }
                .padding(.horizontal, 36)
            }
    }

    private var hinge: some View {
        Capsule()
            .fill(Theme.brushedMetal)
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.6), lineWidth: 0.5))
            .frame(width: 30, height: 6)
            .offset(y: 4)
    }
}

#Preview {
    CassetteBay {
        CassetteView(
            title: "Me at the zoo",
            thumbnailURL: HistoryEntry.defaultThumbnailURL(for: "jNQXAC9IVRw"),
            isRunning: true,
            progress: 0.3,
            length: "0:19"
        )
    }
    .recessedWell(cornerRadius: 8)
    .padding()
    .background(Theme.background)
}

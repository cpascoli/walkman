import SwiftUI

/// The controls for the landscape tape view, which has no keys: tap the
/// cassette to play or pause, double-tap for the next track, triple-tap to go
/// back to the start; press and hold the gap either side of it to wind back
/// or on, a few seconds at a time for as long as you hold.
///
/// Laid over the cassette bay, and shaped to match it.
struct DeckGestures: View {

    let isPlaying: Bool
    /// Where we are on the tape, for VoiceOver, e.g. "0:12".
    var position: String?
    let onTogglePlayback: () -> Void
    let onNextTrack: () -> Void
    let onRestart: () -> Void
    /// Winds by this many seconds; negative winds back.
    let onWind: (TimeInterval) -> Void

    enum Direction { case back, forward }

    /// How far each step of a held wind goes, and how often it steps.
    static let windStep: TimeInterval = 5
    private static let windInterval: Duration = .milliseconds(400)
    /// How long a press has to last before winding starts.
    private static let holdDelay: Duration = .milliseconds(300)

    /// How long to wait for another tap before acting on the ones so far.
    private static let multiTapWindow: Duration = .milliseconds(300)

    @GestureState private var pressed: Direction?
    @State private var taps = 0
    @State private var tapTask: Task<Void, Never>?
    @State private var winding: Direction?
    @State private var windTask: Task<Void, Never>?
    /// Bumped for a tick of haptic feedback: there's nothing to look at.
    @State private var feedback = 0

    var body: some View {
        GeometryReader { geometry in
            let tapWidth = Self.tapZoneWidth(in: geometry.size)
            let gapWidth = max(0, (geometry.size.width - tapWidth) / 2)

            HStack(spacing: 0) {
                windZone(.back)
                    .frame(width: gapWidth)
                tapZone
                    .frame(width: tapWidth)
                windZone(.forward)
                    .frame(width: gapWidth)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: feedback)
        .onChange(of: pressed) { _, pressed in
            if let pressed {
                startWinding(pressed)
            } else {
                stopWinding()
            }
        }
        .onDisappear {
            stopWinding()
            tapTask?.cancel()
            taps = 0
        }
    }

    /// The cassette, as it sits in the bay, with the bay's margin around it.
    static func tapZoneWidth(in size: CGSize) -> CGFloat {
        let insets = CassetteView.bayInsets
        let cassetteWidth = (size.height - insets.top - insets.bottom) * CassetteView.aspectRatio
        return min(size.width, cassetteWidth + insets.leading + insets.trailing)
    }

    // MARK: - Cassette

    private var tapZone: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: countTap)
            .accessibilityElement()
            .accessibilityIdentifier("deckGestures")
            .accessibilityLabel("Tape deck")
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Plays or pauses. More in actions.")
            .accessibilityAction(.default, onTogglePlayback)
            .accessibilityAction(named: "Next track", onNextTrack)
            .accessibilityAction(named: "Back to the start", onRestart)
            .accessibilityAction(named: Text("Wind back \(Self.windSeconds) seconds"), windBack)
            .accessibilityAction(named: Text("Wind on \(Self.windSeconds) seconds"), windOn)
    }

    private static let windSeconds = Int(windStep)

    private func windBack() { onWind(-Self.windStep) }
    private func windOn() { onWind(Self.windStep) }

    private var accessibilityValue: String {
        let state = isPlaying ? "Playing" : "Paused"
        guard let position else { return state }
        return "\(state), \(position)"
    }

    /// Taps are counted by hand: SwiftUI's double- and triple-tap gestures,
    /// chained, sometimes took a quick triple tap for a single one. So a single
    /// tap lands a moment after the finger lifts, in case another follows.
    private func countTap() {
        taps += 1
        tapTask?.cancel()
        guard taps < 3 else { return actOnTaps() }

        tapTask = Task {
            try? await Task.sleep(for: Self.multiTapWindow)
            guard !Task.isCancelled else { return }
            actOnTaps()
        }
    }

    private func actOnTaps() {
        let count = taps
        taps = 0
        switch count {
        case 1: perform(onTogglePlayback)
        case 2: perform(onNextTrack)
        default: perform(onRestart)
        }
    }

    private func perform(_ action: () -> Void) {
        feedback += 1
        action()
    }

    // MARK: - Gaps

    private func windZone(_ direction: Direction) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .overlay {
                // Lit while winding, like the arrow on a deck's key.
                if winding == direction {
                    Image(systemName: direction == .back ? "backward.fill" : "forward.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .shadow(color: Theme.accent.opacity(0.8), radius: 6)
                        .transition(.opacity)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, state, _ in state = direction }
            )
            // The tape deck's actions cover these for VoiceOver.
            .accessibilityHidden(true)
    }

    private func startWinding(_ direction: Direction) {
        windTask?.cancel()
        windTask = Task {
            try? await Task.sleep(for: Self.holdDelay)
            let step = direction == .back ? -Self.windStep : Self.windStep
            while !Task.isCancelled {
                if winding != direction {
                    withAnimation(.easeOut(duration: 0.15)) { winding = direction }
                }
                feedback += 1
                onWind(step)
                try? await Task.sleep(for: Self.windInterval)
            }
        }
    }

    private func stopWinding() {
        windTask?.cancel()
        windTask = nil
        withAnimation(.easeOut(duration: 0.15)) { winding = nil }
    }
}

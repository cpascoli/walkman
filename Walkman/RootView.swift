import SwiftUI

/// Something another tab asks the deck to do.
enum DeckCommand: Equatable {
    case play(PlaybackRequest)
    /// Fall silent without unloading, e.g. while a search preview plays.
    case pause
}

/// The app's tabs: the deck itself, then the places you find things to put on it.
///
/// Not a `TabView`: that takes hidden tabs off screen, and WebKit pauses a web
/// view that leaves the screen, so the embedded player would stop whenever you
/// looked at another tab. Here every tab stays on screen, the selected one on
/// top — the deck underneath keeps playing, as it does under the cassette.
struct RootView: View {

    enum Tab: String, CaseIterable, Identifiable {
        case player = "Player", search = "Search", library = "Library", settings = "Settings"

        var id: Self { self }

        var icon: String {
            switch self {
            case .player: "recordingtape"
            case .search: "magnifyingglass"
            case .library: "rectangle.stack"
            case .settings: "gearshape"
            }
        }
    }

    @ObservedObject var history: PlaybackHistoryStore
    @ObservedObject var nativeModel: NativePlayerModel
    @ObservedObject var downloads: DownloadManager
    @ObservedObject var queue: PlayQueue
    @ObservedObject var library: TapeLibrary

    @State private var tab: Tab = .player
    /// Bumped when a tab is tapped while showing, to take it back to its first
    /// screen: a new identity rebuilds the tab's navigation from the top.
    @State private var resets: [Tab: Int] = [:]
    @StateObject private var searchModel = SearchModel()
    @State private var deckCommand: DeckCommand?
    /// The player picked in Settings.
    @State private var engine: PlaybackEngine = .native
    @State private var isKeyboardVisible = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page(.player) {
                    ContentView(
                        history: history,
                        nativeModel: nativeModel,
                        downloads: downloads,
                        queue: queue,
                        library: library,
                        engine: $engine,
                        command: $deckCommand
                    )
                }
                page(.search) {
                    SearchView(store: history, library: library, onPreviewStart: {
                        deckCommand = .pause
                    }, model: searchModel)
                    .id(resets[.search, default: 0])
                }
                page(.library) {
                    LibraryView(store: history, library: library, downloads: downloads) { request in
                        deckCommand = .play(request)
                        // Over to the deck, to see it start.
                        tab = .player
                    }
                    .id(resets[.library, default: 0])
                }
                page(.settings) {
                    SettingsView(model: nativeModel, downloads: downloads, engine: $engine)
                }
            }

            // Out of the way while typing, as the system tab bar is.
            if !isKeyboardVisible {
                DeckTabBar(selection: $tab) { reselected in
                    // As with the system tab bar: tapping the tab you're on
                    // goes back to its first screen. The deck has no others.
                    guard reselected != .player else { return }
                    resets[reselected, default: 0] += 1
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    /// One tab's content. The deck always stays visible underneath the others;
    /// the rest are drawn only when selected. Anything not selected ignores
    /// touches and is hidden from VoiceOver.
    private func page(_ page: Tab, @ViewBuilder content: () -> some View) -> some View {
        let isSelected = page == tab
        return content()
            .opacity(isSelected || page == .player ? 1 : 0)
            .zIndex(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }
}

/// The tab bar, as a strip of the deck's dark metal with the current tab's
/// legend lit amber.
struct DeckTabBar: View {

    @Binding var selection: RootView.Tab
    /// The tab that's already showing was tapped again.
    var onReselect: (RootView.Tab) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RootView.Tab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    if tab == selection {
                        onReselect(tab)
                    } else {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        // A lit strip over the current tab, like a lamp behind the legend.
                        Capsule()
                            .fill(isSelected ? Theme.accent : .clear)
                            .frame(width: 22, height: 3)
                            .shadow(color: isSelected ? Theme.accent.opacity(0.8) : .clear, radius: 4)
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(height: 22)
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab.\(tab.rawValue)")
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .background(
            Theme.darkMetal
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.black.opacity(0.7)).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

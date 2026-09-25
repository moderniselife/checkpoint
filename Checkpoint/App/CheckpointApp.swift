import SwiftUI

@main
struct CheckpointApp: App {
    @State private var settings = AppSettings()
    @State private var store: PlanStore
    @State private var sync: SyncCoordinator
    @State private var inspector = TicketInspector()
    @State private var tour: TourGuide

    init() {
        let store = PlanStore()
        _store = State(initialValue: store)
        _sync = State(initialValue: SyncCoordinator(store: store))
        let tour = TourGuide()
        tour.store = store
        _tour = State(initialValue: tour)
    }

    var body: some Scene {
        WindowGroup("Checkpoint") {
            ContentView()
                .environment(settings)
                .environment(store)
                .environment(sync)
                .environment(inspector)
                .environment(\.tourGuide, tour)
                .onAppear {
                    inspector.attach(settings)
                    sync.startIfNeeded()
                }
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)

        .commands {
            CommandGroup(replacing: .appSettings) { SettingsCommand() }
            CommandGroup(replacing: .help) { HelpCommands(tour: tour) }
        }

        // A regular window rather than a Settings scene, so it gets the same unified
        // toolbar as the main window: sidebar toggle beside the traffic lights.
        Window("Checkpoint Settings", id: SettingsView.windowID) {
            SettingsView()
                .environment(settings)
                .environment(inspector)
                .environment(sync)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 860, height: 620)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        Self.shortcutsWindow
    }
}

/// App menu → Settings… (⌘,), opening the settings window.
private struct SettingsCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") { openWindow(id: SettingsView.windowID) }
            .keyboardShortcut(",", modifiers: .command)
    }
}

/// The Help menu: tour, welcome, guides, shortcuts and feedback. (macOS's Help search
/// still finds every menu item.)
private struct HelpCommands: View {
    let tour: TourGuide
    @AppStorage("onboardingComplete") private var onboarded = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Take the Tour") { tour.start() }
        Button("Welcome to Checkpoint…") { onboarded = false }
        Divider()
        Button("Checkpoint Guides") { openURL(HelpLinks.guides) }
            .keyboardShortcut("?", modifiers: .command)
        Button("Keyboard Shortcuts") { openWindow(id: KeyboardShortcutsView.windowID) }
            .keyboardShortcut("/", modifiers: .command)
        Button("What's New") { openURL(HelpLinks.releases) }
        Divider()
        Button("Report an Issue…") { openURL(HelpLinks.issues) }
        Button("Checkpoint Website") { openURL(HelpLinks.site) }
    }
}

extension CheckpointApp {
    static var shortcutsWindow: some Scene {
        Window("Keyboard Shortcuts", id: KeyboardShortcutsView.windowID) {
            KeyboardShortcutsView()
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
    }
}

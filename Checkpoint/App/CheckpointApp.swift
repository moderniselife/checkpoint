import SwiftUI

@main
struct CheckpointApp: App {
    @State private var settings = AppSettings()
    @State private var store: PlanStore
    @State private var sync: SyncCoordinator
    @State private var inspector = TicketInspector()

    init() {
        let store = PlanStore()
        _store = State(initialValue: store)
        _sync = State(initialValue: SyncCoordinator(store: store))
    }

    var body: some Scene {
        WindowGroup("Checkpoint") {
            ContentView()
                .environment(settings)
                .environment(store)
                .environment(sync)
                .environment(inspector)
                .onAppear {
                    inspector.attach(settings)
                    sync.startIfNeeded()
                }
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)

        .commands {
            CommandGroup(replacing: .appSettings) { SettingsCommand() }
            CommandGroup(before: .help) { WelcomeCommand() }
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

/// Help → Welcome to Checkpoint…, to see onboarding again.
private struct WelcomeCommand: View {
    @AppStorage("onboardingComplete") private var onboarded = false

    var body: some View {
        Button("Welcome to Checkpoint…") { onboarded = false }
        Divider()
    }
}

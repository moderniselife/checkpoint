import SwiftUI

@main
struct CheckpointApp: App {
    @State private var settings = AppSettings()
    @State private var store = PlanStore()
    @State private var inspector = TicketInspector()

    var body: some Scene {
        WindowGroup("Checkpoint") {
            ContentView()
                .environment(settings)
                .environment(store)
                .environment(inspector)
                .onAppear { inspector.attach(settings) }
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)

        .commands {
            CommandGroup(replacing: .appSettings) { SettingsCommand() }
        }

        // A regular window rather than a Settings scene, so it gets the same unified
        // toolbar as the main window: sidebar toggle beside the traffic lights.
        Window("Checkpoint Settings", id: SettingsView.windowID) {
            SettingsView()
                .environment(settings)
                .environment(inspector)
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

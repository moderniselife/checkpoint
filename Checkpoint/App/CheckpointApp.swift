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

        Settings {
            SettingsView()
                .environment(settings)
                .environment(inspector)
                // Resizable Settings window: NavigationSplitView inside defines
                // min/ideal sizes; this default size suits a 13" MacBook and the
                // user can stretch it on a desktop monitor.
                .frame(minWidth: 680, idealWidth: 960, minHeight: 480, idealHeight: 620)
        }
        .defaultSize(width: 960, height: 620)
        .windowResizability(.contentMinSize)
    }
}

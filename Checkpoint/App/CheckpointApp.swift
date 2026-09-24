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
        }
    }
}

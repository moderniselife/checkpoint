import SwiftUI

@main
struct CheckpointMobileApp: App {
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
        WindowGroup {
            MobileRootView()
                .environment(settings)
                .environment(store)
                .environment(sync)
                .environment(inspector)
                .onAppear {
                    inspector.attach(settings)
                    sync.startIfNeeded()
                }
        }
    }
}

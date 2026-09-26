import SwiftUI

@main
struct CheckpointMobileApp: App {
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
        WindowGroup {
            MobileRootView()
                .background { KeyboardDismisser() }
                .environment(settings)
                .environment(store)
                .environment(sync)
                .environment(inspector)
                .environment(\.tourGuide, tour)
                .onAppear {
                    inspector.attach(settings)
                    sync.startIfNeeded()
                }
        }
    }
}

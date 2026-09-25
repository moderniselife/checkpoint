import SwiftUI

@main
struct CheckpointMobileApp: App {
    @State private var settings = AppSettings()
    @State private var store = PlanStore()
    @State private var inspector = TicketInspector()

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environment(settings)
                .environment(store)
                .environment(inspector)
                .onAppear { inspector.attach(settings) }
        }
    }
}

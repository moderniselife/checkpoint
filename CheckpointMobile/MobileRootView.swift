import SwiftUI

/// iPhone and iPad shell around the shared views. iPhone: the plan list with the
/// ticket bar at the bottom; plans push in; the live research feed rises as a sheet.
/// iPad: a split view like the Mac, with the ticket bar over the detail.
struct MobileRootView: View {
    @Environment(PlanStore.self) private var store
    @Environment(TicketInspector.self) private var inspector
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("onboardingComplete") private var onboarded = false
    @State private var showingSettings = false
    @State private var columns: NavigationSplitViewVisibility = .all

    private var phone: Bool { sizeClass == .compact }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationTitle("Checkpoint")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Settings", systemImage: "gearshape") { showingSettings = true }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if phone {
                        TicketInputBar(stacked: true)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                    }
                }
        } detail: {
            detail
                .background { Backdrop().ignoresSafeArea() }
                .safeAreaInset(edge: .top) {
                    if !phone {
                        TicketInputBar()
                            .padding(.horizontal, 20)
                            .padding(.top, 6)
                            .padding(.bottom, 8)
                    }
                }
        }
        .overlay(alignment: .bottom) {
            if let error = store.error {
                ErrorBanner(message: error)
                    .padding(.horizontal, 16)
                    .padding(.bottom, phone ? 150 : 24)
                    .onTapGesture { store.error = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: store.error)
        // iPhone: watch the research live in a sheet; it closes and the new plan opens when done.
        .sheet(isPresented: Binding(get: { phone && store.isRunning }, set: { if !$0 && store.isRunning { store.cancel() } })) {
            NavigationStack {
                ProgressFeedView()
                    .background { Backdrop().ignoresSafeArea() }
                    .navigationTitle(store.runningKey ?? "Analyzing")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Stop", role: .destructive) { store.cancel() }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: Binding(get: { inspector.isOpen }, set: { if !$0 { inspector.close() } })) {
            TicketPanel()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            OnboardingView { onboarded = true }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if store.isRunning && !phone {
            ProgressFeedView()
        } else if let saved = store.selected {
            PlanView(saved: saved).id(saved.id)
                .navigationTitle(saved.plan.ticket.key)
                .navigationBarTitleDisplayMode(.inline)
        } else if let folder = store.selectedFolder {
            FolderOverview(folder: folder)
                .navigationTitle(folder.name)
                .navigationBarTitleDisplayMode(.inline)
        } else if let smart = store.selectedSmartFolder {
            SmartFolderOverview(smart: smart).id(smart.id)
                .navigationTitle(smart.name)
                .navigationBarTitleDisplayMode(.inline)
        } else if store.showingDashboard {
            DashboardView()
                .navigationTitle("Dashboard")
                .navigationBarTitleDisplayMode(.inline)
        } else {
            EmptyStateView()
        }
    }
}

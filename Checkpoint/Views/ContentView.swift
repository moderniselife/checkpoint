import SwiftUI

struct ContentView: View {
    @Environment(PlanStore.self) private var store
    @Environment(TicketInspector.self) private var inspector
    @AppStorage("panelWidth") private var panelWidth = 460.0
    @State private var dragStartWidth: Double?

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            HStack(spacing: 0) {
                main
                if inspector.isOpen {
                    TicketPanel()
                        .frame(width: panelWidth)
                        .padding(.vertical, 12)
                        .padding(.trailing, 12)
                        .overlay(alignment: .leading) { resizeHandle }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background { Backdrop() }
            .animation(.smooth(duration: 0.35), value: inspector.isOpen)
            .toolbar {
                if !inspector.isOpen && !inspector.tabs.isEmpty {
                    ToolbarItem {
                        Button {
                            withAnimation(.smooth) { inspector.show() }
                        } label: {
                            Label("Open tickets (\(inspector.tabs.count))", systemImage: "rectangle.stack")
                        }
                        .help("Show your open ticket tabs")
                    }
                }
            }
        }
    }

    /// Drag the panel's leading edge to resize it.
    private var resizeHandle: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 10)
            .contentShape(.rect)
            #if os(macOS)
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            #endif
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStartWidth ?? panelWidth
                    dragStartWidth = start
                    panelWidth = min(820, max(360, start - value.translation.width))
                }
                .onEnded { _ in dragStartWidth = nil })
            .offset(x: -5)
    }

    private var main: some View {
            ZStack(alignment: .top) {

                Group {
                    if store.isRunning {
                        ProgressFeedView()
                    } else if let saved = store.selected {
                        PlanView(saved: saved).id(saved.id)
                    } else if let folder = store.selectedFolder {
                        FolderOverview(folder: folder)
                    } else if let smart = store.selectedSmartFolder {
                        SmartFolderOverview(smart: smart).id(smart.id)
                    } else if store.showingDashboard {
                        DashboardView()
                    } else {
                        EmptyStateView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TicketInputBar()
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
            }
            .overlay(alignment: .bottom) {
                if let error = store.error {
                    ErrorBanner(message: error)
                        .padding(20)
                        .onTapGesture { store.error = nil }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth, value: store.error)
    }
}

/// A Jira key that opens the ticket side panel when clicked.
struct TicketKeyButton: View {
    let key: String
    var font: Font = .callout.monospaced().weight(.semibold)
    @Environment(TicketInspector.self) private var inspector
    @Environment(\.ticketTracker) private var tracker
    @State private var hovering = false

    var body: some View {
        Button { inspector.open(key, tracker: tracker) } label: {
            Text(key)
                .font(font)
                .underline(hovering)
                .foregroundStyle(hovering ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Show \(key) details")
    }
}

/// Soft coloured wash behind the content so the glass has something to refract.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.6, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
            colors: scheme == .dark
                ? [.indigo.opacity(0.35), .black, .teal.opacity(0.25),
                   .black, .purple.opacity(0.2), .black,
                   .teal.opacity(0.2), .black, .indigo.opacity(0.3)]
                : [.indigo.opacity(0.18), .white, .teal.opacity(0.16),
                   .white, .purple.opacity(0.1), .white,
                   .teal.opacity(0.12), .white, .indigo.opacity(0.16)]
        )
        .ignoresSafeArea()
    }
}

struct EmptyStateView: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .shadow(color: .indigo.opacity(0.25), radius: 18, y: 8)
            Text("Drop in a ticket, get a test plan.")
                .font(.title2.weight(.semibold))
            Text("Checkpoint reads the ticket, its children, linked issues, comments and specs, then tells you what to test, how, and what counts as done.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            if !settings.isConfigured {
                Button {
                    openWindow(id: SettingsView.windowID)
                } label: {
                    Label("Connect an AI provider + your tracker", systemImage: "key.fill")
                }
                .buttonStyle(.glassProminent)
                .padding(.top, 8)
            }
        }
        .padding(40)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(.red.opacity(0.25)), in: .capsule)
            .frame(maxWidth: 560)
            .textSelection(.enabled)
    }
}

extension EnvironmentValues {
    /// Tracker that ticket keys in this part of the UI belong to.
    @Entry var ticketTracker: Tracker = .jira
}

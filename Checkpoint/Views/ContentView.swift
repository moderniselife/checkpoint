import SwiftUI

struct ContentView: View {
    @Environment(PlanStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            ZStack(alignment: .top) {
                Backdrop()

                Group {
                    if store.isRunning {
                        ProgressFeedView()
                    } else if let saved = store.selected {
                        PlanView(saved: saved)
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

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop in a ticket, get a test plan.")
                .font(.title2.weight(.semibold))
            Text("Checkpoint reads the ticket, its children, linked issues, comments and specs, then tells you what to test, how, and what counts as done.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            if !settings.isConfigured {
                SettingsLink {
                    Label("Connect Anthropic + Atlassian", systemImage: "key.fill")
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

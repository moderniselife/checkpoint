import SwiftUI

struct SidebarView: View {
    @Environment(PlanStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selection) {
            if let key = store.runningKey {
                Section("Analyzing") {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(key).font(.body.monospaced())
                    }
                }
            }
            Section("Test plans") {
                ForEach(store.plans) { saved in
                    SidebarRow(saved: saved)
                        .tag(saved.id)
                        .contextMenu {
                            Button("Re-run") { rerun(saved) }
                            if let url = URL(string: saved.plan.ticket.url) {
                                Link("Open in Jira", destination: url)
                            }
                            Divider()
                            Button("Delete", role: .destructive) { store.delete(saved.id) }
                        }
                }
            }
        }
        .overlay {
            if store.plans.isEmpty && !store.isRunning {
                ContentUnavailableView("No plans yet", systemImage: "tray", description: Text("Analyze a ticket to start."))
            }
        }
    }

    @Environment(AppSettings.self) private var settings
    private func rerun(_ saved: SavedPlan) { store.analyze(saved.id, settings: settings) }
}

private struct SidebarRow: View {
    let saved: SavedPlan

    var body: some View {
        HStack(spacing: 10) {
            ProgressRing(value: saved.progress, lineWidth: 3)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(saved.plan.ticket.key)
                    .font(.body.monospaced().weight(.medium))
                Text(saved.plan.ticket.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ProgressRing: View {
    let value: Double
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: value)
                .stroke(value >= 1 ? Color.green : Color.accentColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.smooth, value: value)
    }
}

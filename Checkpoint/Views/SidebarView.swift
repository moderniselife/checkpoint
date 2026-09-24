import SwiftUI

struct SidebarView: View {
    @Environment(PlanStore.self) private var store
    @Environment(TicketInspector.self) private var inspector

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selection) {
            if let key = store.runningKey {
                Section("Analyzing") {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(key).font(.body.monospaced())
                        ModeBadge(mode: store.runningMode, compact: true)
                    }
                }
            }
            Section("Test plans") {
                ForEach(store.plans) { saved in
                    SidebarRow(saved: saved)
                        .tag(saved.id)
                        .contextMenu {
                            Button("Show ticket details") { inspector.open(saved.plan.ticket.key) }
                            Button("Run in \(saved.mode == .dev ? "QA" : "Dev") mode") {
                                store.analyze(saved.plan.ticket.key, mode: saved.mode == .dev ? .qa : .dev, settings: settings)
                            }
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
    private func rerun(_ saved: SavedPlan) { store.analyze(saved.plan.ticket.key, mode: saved.mode, settings: settings) }
}

private struct SidebarRow: View {
    let saved: SavedPlan

    var body: some View {
        HStack(spacing: 10) {
            ProgressRing(value: saved.progress, lineWidth: 3)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(saved.plan.ticket.key)
                        .font(.body.monospaced().weight(.medium))
                    ModeBadge(mode: saved.mode, compact: true)
                }
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

struct ModeBadge: View {
    let mode: TestMode
    var compact = false

    var body: some View {
        Label(mode.label, systemImage: mode.icon)
            .labelStyle(.titleAndIcon)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .padding(.horizontal, compact ? 5 : 8)
            .padding(.vertical, compact ? 1 : 3)
            .foregroundStyle(mode == .qa ? Color.teal : Color.indigo)
            .background((mode == .qa ? Color.teal : Color.indigo).opacity(0.14), in: .capsule)
            .help(mode.help)
    }
}

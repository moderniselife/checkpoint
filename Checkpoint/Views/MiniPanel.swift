import AppKit
import SwiftUI

/// Floating always-on-top mini checklist (IDEA-028): tick the current plan's
/// tasks while testing in a browser. Shares PlanStore, so ticks sync live.
@MainActor
final class MiniPanelController: NSObject {
    static let shared = MiniPanelController()
    private var panel: NSPanel?

    func toggle(with store: PlanStore) {
        if panel?.isVisible == true {
            panel?.close()
        } else {
            show(store: store)
        }
    }

    private func show(store: PlanStore) {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 330, height: 500),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered, defer: false)
            p.level = .floating
            p.title = "Checklist"
            p.isReleasedWhenClosed = false
            p.minSize = NSSize(width: 260, height: 200)
            panel = p
        }
        panel?.contentView = NSHostingView(rootView: MiniChecklistView().environment(store))
        panel?.makeKeyAndOrderFront(nil)
    }
}

private struct MiniChecklistView: View {
    @Environment(PlanStore.self) private var store
    @State private var planID: String?

    private var candidates: [SavedPlan] {
        store.plans.filter { !$0.archived && $0.progress < 1 }
    }

    private var current: SavedPlan? {
        planID.flatMap { id in store.plans.first { $0.id == id } }
            ?? store.selected
            ?? candidates.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if candidates.count > 1 {
                    Menu {
                        ForEach(candidates) { saved in
                            Button("\(saved.plan.ticket.key) — \(saved.plan.ticket.title)") {
                                planID = saved.id
                            }
                        }
                    } label: {
                        Label(current?.plan.ticket.key ?? "Checklist", systemImage: "list.bullet")
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                } else {
                    Label(current?.plan.ticket.key ?? "Checklist", systemImage: "list.bullet")
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let current {
                    ProgressRing(value: current.progress, lineWidth: 4)
                        .frame(width: 22, height: 22)
                }
            }
            if let current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(current.plan.tasks) { task in
                            HStack(alignment: .top, spacing: 8) {
                                Button {
                                    withAnimation(.smooth) { store.toggle(task.id, in: current.id) }
                                } label: {
                                    Image(systemName: current.verdict(of: task.id).icon)
                                        .foregroundStyle(verdictColor(current.verdict(of: task.id)))
                                }
                                .buttonStyle(.plain)
                                Text(task.title)
                                    .font(.callout)
                                    .strikethrough(current.done.contains(task.id))
                                    .foregroundStyle(current.done.contains(task.id) ? .secondary : .primary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                        }
                    }
                }
                .glassScrollIndicator()
            } else {
                ContentUnavailableView("No open plans", systemImage: "tray",
                                       description: Text("Analyze a ticket to start."))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { Backdrop() }
    }

    private func verdictColor(_ v: TaskVerdict) -> AnyShapeStyle {
        switch v {
        case .todo: AnyShapeStyle(.secondary)
        case .pass: AnyShapeStyle(.green)
        case .fail: AnyShapeStyle(.red)
        case .blocked: AnyShapeStyle(.orange)
        }
    }
}

import SwiftUI
import AppKit

/// Regression suite builder (IDEA-015): merge several plans (or a whole
/// folder tree) into one deduplicated run. The suite is transient — ticks live
/// in the sheet, source plans are untouched — and exports as Markdown.
struct SuiteBuilderSheet: View {
    let folder: PlanFolder
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var included: Set<String> = []
    @State private var ticks: Set<String> = []
    @State private var copied = false

    private var candidates: [SavedPlan] { store.allPlans(under: folder.id) }

    private var suite: [(plan: SavedPlan, task: TestPlan.Task)] {
        RegressionSuite.merge(candidates.filter { included.contains($0.id) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Regression suite — \(folder.name)").font(.headline)
            Text("Pick plans to merge. Shared setup is deduped by title; ticks stay in this sheet.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(candidates) { saved in
                        Toggle(isOn: Binding(
                            get: { included.contains(saved.id) },
                            set: { on in
                                if on { included.insert(saved.id) } else { included.remove(saved.id) }
                            }
                        )) {
                            HStack {
                                Text(saved.plan.ticket.key).font(.callout.monospaced())
                                Text(saved.plan.ticket.title).lineLimit(1).foregroundStyle(.secondary)
                                Spacer(minLength: 4)
                                Text("\(saved.plan.tasks.count)").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 180)
            Divider()
            Text("\(suite.count) checks").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(suite, id: \.task.id) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Button {
                                if ticks.contains(item.task.id) { ticks.remove(item.task.id) }
                                else { ticks.insert(item.task.id) }
                            } label: {
                                Image(systemName: ticks.contains(item.task.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(ticks.contains(item.task.id) ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.task.title).font(.callout.weight(.medium))
                                Text("\(item.plan.plan.ticket.key) · expected: \(item.task.expected)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(copied ? "Copied" : "Copy as Markdown", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(RegressionSuite.markdown(folderName: folder.name, suite: suite, ticks: ticks), forType: .string)
                    copied = true
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(suite.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 640)
        .onAppear(perform: { included = Set(candidates.map(\.id)) })
    }
}

/// Pure merge logic: order by plan, dedupe near-identical titles.
nonisolated enum RegressionSuite {
    static func merge(_ plans: [SavedPlan]) -> [(plan: SavedPlan, task: TestPlan.Task)] {
        var kept: [(plan: SavedPlan, task: TestPlan.Task)] = []
        var norms: [String] = []
        func norm(_ s: String) -> String {
            s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        for plan in plans {
            for task in plan.plan.tasks {
                let n = norm(task.title)
                guard !norms.contains(where: { $0.contains(n.prefix(24)) || n.contains($0.prefix(24)) }) else { continue }
                norms.append(n)
                kept.append((plan, task))
            }
        }
        return kept
    }

    static func markdown(folderName: String, suite: [(plan: SavedPlan, task: TestPlan.Task)], ticks: Set<String>) -> String {
        var md = "# Regression suite — \(folderName)\n\n"
        md += "> \(ticks.count)/\(suite.count) checked\n"
        var lastKey = ""
        for item in suite {
            if item.plan.plan.ticket.key != lastKey {
                md += "\n### \(item.plan.plan.ticket.key) — \(item.plan.plan.ticket.title)\n"
                lastKey = item.plan.plan.ticket.key
            }
            md += "\n- [\(ticks.contains(item.task.id) ? "x" : " ")] **\(item.task.title)**\n"
            for (i, step) in item.task.steps.enumerated() { md += "    \(i + 1). \(step)\n" }
            md += "    - **Expected:** \(item.task.expected)\n"
        }
        return md + "\n---\n_Generated by [Checkpoint](https://checkpoint.guide)._\n"
    }
}

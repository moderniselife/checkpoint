import SwiftUI

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
        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(candidates) { saved in
                        Toggle(isOn: Binding(
                            get: { included.contains(saved.id) },
                            set: { on in
                                if on { included.insert(saved.id) } else { included.remove(saved.id) }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Text(saved.plan.ticket.key).font(.callout.monospaced().weight(.medium))
                                Text(saved.plan.ticket.title).lineLimit(1).foregroundStyle(.secondary)
                                Spacer(minLength: 4)
                                Text("\(saved.plan.tasks.count) tasks").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                } header: {
                    Text("Regression suite — \(folder.name)")
                } footer: {
                    Text("Merges the plans you pick into one run, dropping near-duplicate tasks. Ticks stay in this sheet; the plans themselves aren't changed.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    if suite.isEmpty {
                        Text("Pick at least one plan.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(suite.enumerated()), id: \.offset) { _, item in
                        let key = RegressionSuite.key(item)
                        let done = ticks.contains(key)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Button {
                                withAnimation(.smooth) {
                                    if done { ticks.remove(key) } else { ticks.insert(key) }
                                }
                            } label: {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.task.title)
                                    .font(.callout.weight(.medium))
                                    .strikethrough(done)
                                    .foregroundStyle(done ? .secondary : .primary)
                                Text(item.task.expected)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 4)
                            Text(item.plan.plan.ticket.key).font(.caption.monospaced()).foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    HStack {
                        Text("\(suite.count) checks")
                        Spacer()
                        if !suite.isEmpty {
                            Text("\(ticks.count) done").monospacedDigit()
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(copied ? "Copied" : "Copy as Markdown", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    Platform.copy(RegressionSuite.markdown(folderName: folder.name, suite: suite, ticks: ticks))
                    copied = true
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(suite.isEmpty)
            }
            .padding(20)
        }
        .macSheetFrame(width: 580, height: 660)
        .onAppear { included = Set(candidates.map(\.id)) }
    }
}

/// Pure merge logic: order by plan, dedupe near-identical titles.
nonisolated enum RegressionSuite {
    /// Task ids repeat across plans (t1, t2…), so ticks key on plan + task.
    static func key(_ item: (plan: SavedPlan, task: TestPlan.Task)) -> String {
        item.plan.id + "/" + item.task.id
    }

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
            md += "\n- [\(ticks.contains(key(item)) ? "x" : " ")] **\(item.task.title)**\n"
            for (i, step) in item.task.steps.enumerated() { md += "    \(i + 1). \(step)\n" }
            md += "    - **Expected:** \(item.task.expected)\n"
        }
        return md + "\n---\n_Generated by [Checkpoint](https://checkpoint.guide)._\n"
    }
}

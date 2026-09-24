import SwiftUI
import AppKit

struct PlanView: View {
    let saved: SavedPlan
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var filter: Filter = .todo
    @State private var copied = false

    enum Filter: String, CaseIterable { case todo = "To do", all = "All" }

    private var plan: TestPlan { saved.plan }

    private var visibleTasks: [TestPlan.Task] {
        filter == .all ? plan.tasks : plan.tasks.filter { !saved.done.contains($0.id) }
    }

    /// Group tasks by ticket so epics read child-by-child, keeping plan order.
    private var groupedTasks: [(key: String, tasks: [TestPlan.Task])] {
        var order: [String] = []
        var groups: [String: [TestPlan.Task]] = [:]
        for t in visibleTasks {
            if groups[t.ticketKey] == nil { order.append(t.ticketKey) }
            groups[t.ticketKey, default: []].append(t)
        }
        return order.map { ($0, groups[$0]!) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !plan.preconditions.isEmpty {
                    Section(title: "Before you start", icon: "wrench.and.screwdriver") {
                        BulletList(items: plan.preconditions)
                    }
                }

                if !plan.acceptanceCriteria.isEmpty {
                    Section(title: "Acceptance criteria", icon: "target") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(plan.acceptanceCriteria) { ac in
                                CriterionRow(criterion: ac, state: coverage(of: ac))
                            }
                        }
                    }
                }

                Section(title: "Test tasks", icon: "checklist", accessory: {
                    Picker("", selection: $filter) {
                        ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 140)
                }) {
                    if visibleTasks.isEmpty {
                        Label("All done — nice.", systemImage: "party.popper")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groupedTasks, id: \.key) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                if groupedTasks.count > 1 || group.key != plan.ticket.key {
                                    TicketTag(key: group.key, title: title(for: group.key), url: url(for: group.key))
                                }
                                ForEach(group.tasks) { task in
                                    TaskRow(task: task, isDone: saved.done.contains(task.id)) {
                                        withAnimation(.smooth) { store.toggle(task.id, in: saved.id) }
                                    }
                                }
                            }
                        }
                    }
                }

                if !plan.edgeCases.isEmpty {
                    Section(title: "Edge cases worth poking", icon: "exclamationmark.triangle") {
                        BulletList(items: plan.edgeCases)
                    }
                }

                if !plan.openQuestions.isEmpty {
                    Section(title: "Open questions", icon: "questionmark.bubble") {
                        BulletList(items: plan.openQuestions)
                    }
                }

                if !plan.sources.isEmpty {
                    Section(title: "Read so you didn't have to", icon: "books.vertical") {
                        FlowLayout(spacing: 8) {
                            ForEach(plan.sources) { s in
                                SourceChip(source: s)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 92)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItemGroup {
                Button(copied ? "Copied" : "Copy as Markdown",
                       systemImage: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(plan.markdown(done: saved.done), forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
                Button("Re-run", systemImage: "arrow.clockwise") {
                    store.analyze(saved.id, settings: settings)
                }
                if let url = URL(string: plan.ticket.url) {
                    Link(destination: url) { Label("Open in Jira", systemImage: "arrow.up.right.square") }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(plan.ticket.key)
                        .font(.headline.monospaced())
                    Chip(text: plan.ticket.type)
                    Chip(text: plan.ticket.status, tint: .blue)
                }
                Text(plan.ticket.title)
                    .font(.title.weight(.semibold))
                    .textSelection(.enabled)
                Text(plan.summary)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                ZStack {
                    ProgressRing(value: saved.progress, lineWidth: 8)
                    Text("\(saved.done.intersection(plan.tasks.map(\.id)).count)/\(plan.tasks.count)")
                        .font(.headline.monospacedDigit())
                }
                .frame(width: 72, height: 72)
                Text("tested").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func coverage(of ac: TestPlan.Criterion) -> CriterionRow.State {
        let covering = plan.tasks.filter { $0.covers.contains(ac.id) }
        if covering.isEmpty { return .uncovered }
        return covering.allSatisfy { saved.done.contains($0.id) } ? .verified : .pending
    }

    private func source(for key: String) -> TestPlan.Source? { plan.sources.first { $0.key == key } }
    private func title(for key: String) -> String {
        key == plan.ticket.key ? plan.ticket.title : (source(for: key)?.title ?? "")
    }
    private func url(for key: String) -> URL? {
        URL(string: key == plan.ticket.key ? plan.ticket.url : (source(for: key)?.url ?? ""))
    }
}

// MARK: - Pieces

private struct Section<Content: View, Accessory: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(title: String, icon: String,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
                accessory
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.55), in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.separator.opacity(0.5)))
    }
}

private struct TaskRow: View {
    let task: TestPlan.Task
    let isDone: Bool
    let toggle: () -> Void
    @State private var expanded = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isDone ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(isDone ? "Mark untested" : "Mark tested")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .strikethrough(isDone)
                        .foregroundStyle(isDone ? .secondary : .primary)
                    Spacer(minLength: 8)
                    if !task.area.isEmpty { Chip(text: task.area) }
                    PriorityDot(priority: task.priority)
                }
                .contentShape(.rect)
                .onTapGesture { withAnimation(.smooth) { expanded.toggle() } }

                if expanded && !isDone {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(task.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(i + 1).")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 20, alignment: .trailing)
                                Text(step).font(.callout)
                            }
                        }
                    }
                    .textSelection(.enabled)

                    Label {
                        Text(task.expected).font(.callout)
                    } icon: {
                        Image(systemName: "checkmark.seal").foregroundStyle(.green)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.green.opacity(0.08), in: .rect(cornerRadius: 10))
                    .textSelection(.enabled)

                    if !task.covers.isEmpty {
                        Text("Covers " + task.covers.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(12)
        .background(.background.opacity(isDone ? 0.2 : 0.6), in: .rect(cornerRadius: 14))
    }
}

private struct CriterionRow: View {
    enum State { case verified, pending, uncovered }
    let criterion: TestPlan.Criterion
    let state: State

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .help(help)
            Text(criterion.id)
                .font(.callout.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            Text(criterion.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if criterion.source == "derived" {
                Chip(text: "derived", tint: .orange)
                    .help("No explicit AC on the ticket — inferred from the description.")
            } else {
                Text(criterion.source).font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
        }
    }

    private var icon: String {
        switch state {
        case .verified: "checkmark.seal.fill"
        case .pending: "seal"
        case .uncovered: "exclamationmark.circle"
        }
    }
    private var color: Color {
        switch state {
        case .verified: .green
        case .pending: .secondary
        case .uncovered: .orange
        }
    }
    private var help: String {
        switch state {
        case .verified: "All covering tasks ticked"
        case .pending: "Covering tasks still to do"
        case .uncovered: "No task covers this criterion"
        }
    }
}

struct Chip: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular.tint(tint.opacity(0.2)), in: .capsule)
    }
}

private struct PriorityDot: View {
    let priority: TestPlan.Priority

    var body: some View {
        Circle()
            .fill(priority == .high ? Color.red : priority == .medium ? .orange : .gray)
            .frame(width: 8, height: 8)
            .help("\(priority.rawValue.capitalized) priority")
    }
}

private struct TicketTag: View {
    let key: String
    let title: String
    let url: URL?

    var body: some View {
        HStack(spacing: 8) {
            Text(key).font(.subheadline.monospaced().weight(.semibold))
            Text(title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            if let url {
                Link(destination: url) { Image(systemName: "arrow.up.right") }
                    .font(.caption)
            }
        }
    }
}

private struct SourceChip: View {
    let source: TestPlan.Source

    var body: some View {
        let label = HStack(spacing: 6) {
            Text(source.key).font(.caption.monospaced().weight(.semibold))
            Text(source.relation).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular.interactive(), in: .capsule)
        .help(source.title)

        if let url = URL(string: source.url), !source.url.isEmpty {
            Link(destination: url) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }
}

private struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(.tertiary)
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }
}

/// Wrapping horizontal layout for chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (i, origin) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), origins)
    }
}

import SwiftUI
import AppKit

struct PlanView: View {
    let saved: SavedPlan
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(TicketInspector.self) private var inspector
    @State private var filter: Filter = .todo
    @State private var pane: Pane = .plan

    enum Pane: String, CaseIterable { case plan = "Plan", research = "Research" }
    @State private var copied = false

    enum Filter: String, CaseIterable { case todo = "To do", all = "All" }

    private var plan: TestPlan { saved.plan }
    private var detailsOpen: Bool { inspector.currentKey == plan.ticket.key.uppercased() }

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

                if pane == .plan {
                    if !plan.preconditions.isEmpty {
                        Section(title: "Before you start", icon: "wrench.and.screwdriver") {
                            BulletList(items: plan.preconditions)
                        }
                    }

                    if !plan.acceptanceCriteria.isEmpty {
                        Section(title: "Acceptance criteria", icon: "target") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(plan.acceptanceCriteria) { ac in
                                    CriterionRow(criterion: ac, state: coverage(of: ac),
                                                 isMet: saved.metCriteria.contains(ac.id)) {
                                        withAnimation(.smooth) { store.toggleCriterion(ac.id, in: saved.id) }
                                    }
                                }
                                CriteriaLegend(hasUncovered: plan.acceptanceCriteria.contains { coverage(of: $0) == .uncovered })
                                    .padding(.top, 4)
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

                    if !plan.scenarios.isEmpty {
                        Section(title: "Scenarios", icon: "theatermasks") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(plan.scenarios) { sc in
                                    ScenarioCard(scenario: sc, isDone: saved.done.contains("scenario:" + sc.id)) {
                                        withAnimation(.smooth) { store.toggle("scenario:" + sc.id, in: saved.id) }
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
                } else {
                    ResearchLog(saved: saved)
                }
            }
            .environment(\.ticketTracker, saved.tracker)
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 92)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .glassScrollIndicator()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $pane) {
                    Label("Plan", systemImage: "checklist").tag(Pane.plan)
                    Label("Research (\(saved.research.filter { $0.kind != .status }.count))", systemImage: "magnifyingglass")
                        .tag(Pane.research)
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleOnly)
                .help("Switch between the test plan and the research that produced it")
            }
            ToolbarItemGroup {
                Button(copied ? "Copied" : "Copy as Markdown",
                       systemImage: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(plan.markdown(done: saved.done, met: saved.metCriteria), forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
                Button("Re-run", systemImage: "arrow.clockwise") {
                    store.analyze(saved.plan.ticket.key, mode: saved.mode, tracker: saved.tracker, settings: settings)
                }
                if let url = URL(string: plan.ticket.url), url.scheme != nil {
                    Button("Open in \(saved.tracker.label)", systemImage: "arrow.up.right.square") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button(detailsOpen ? "Hide ticket details" : "Show ticket details", systemImage: "sidebar.right") {
                    withAnimation(.smooth) { inspector.toggle(plan.ticket.key, tracker: saved.tracker) }
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TicketKeyButton(key: plan.ticket.key, font: .headline.monospaced())
                    ModeBadge(mode: saved.mode)
                    if saved.tracker == .linear { Chip(text: "Linear", tint: .purple) }
                    Spacer(minLength: 8)
                    Button {
                        withAnimation(.smooth) { inspector.toggle(plan.ticket.key, tracker: saved.tracker) }
                    } label: {
                        Label(detailsOpen ? "Hide details" : "Ticket details", systemImage: "sidebar.right")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.glass)
                    .help("Show everything on the ticket (⌘I)")
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
            HStack(spacing: 16) {
                MetricRing(value: saved.progress, label: "tested",
                           text: "\(saved.tasksDone)/\(plan.tasks.count)", tint: .accentColor)
                if !plan.acceptanceCriteria.isEmpty {
                    MetricRing(value: saved.criteriaProgress, label: "AC met",
                               text: "\(saved.criteriaMet)/\(plan.acceptanceCriteria.count)", tint: .teal)
                }
            }
        }
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func coverage(of ac: TestPlan.Criterion) -> CriterionRow.Coverage {
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

/// Acceptance criterion with a checkbox: click the seal to mark it met.
/// While unmet, the seal hints at task coverage (uncovered / pending / ready).
private struct CriterionRow: View {
    enum Coverage { case verified, pending, uncovered }
    let criterion: TestPlan.Criterion
    let state: Coverage
    let isMet: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: toggle) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(color)
                    .scaleEffect(hovering ? 1.15 : 1)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(help)
            Text(criterion.id)
                .font(.callout.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            Text(criterion.text)
                .strikethrough(isMet, color: .secondary)
                .foregroundStyle(isMet ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if criterion.source == "derived" {
                Chip(text: "derived", tint: .orange)
                    .help("No explicit AC on the ticket — inferred from the description.")
            } else {
                TicketKeyButton(key: criterion.source, font: .caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .animation(.smooth(duration: 0.15), value: hovering)
    }

    private var icon: String {
        if isMet { return "checkmark.seal.fill" }
        if hovering { return "checkmark.seal" }
        switch state {
        case .verified: return "checkmark.seal"
        case .pending: return "seal"
        case .uncovered: return "exclamationmark.circle"
        }
    }
    private var color: Color {
        if isMet { return .green }
        if hovering { return .green.opacity(0.7) }
        switch state {
        case .verified: return .green
        case .pending: return .secondary
        case .uncovered: return .orange
        }
    }
    private var help: String {
        if isMet { return "Met — click to unmark" }
        switch state {
        case .verified: return "All covering tasks ticked — click to mark met"
        case .pending: return "Covering tasks still to do — click to mark met"
        case .uncovered: return "No task covers this criterion — click to mark met"
        }
    }
}

/// Big labelled progress ring for the plan header.
struct MetricRing: View {
    let value: Double
    let label: String
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ProgressRing(value: value, lineWidth: 8, tint: tint)
                Text(text).font(.headline.monospacedDigit())
            }
            .frame(width: 72, height: 72)
            Text(label).font(.caption).foregroundStyle(.secondary)
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
            TicketKeyButton(key: key, font: .subheadline.monospaced().weight(.semibold))
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
    @Environment(TicketInspector.self) private var inspector

    var body: some View {
        let label = HStack(spacing: 6) {
            Text(source.key).font(.caption.monospaced().weight(.semibold))
            Text(source.relation).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular.interactive(), in: .capsule)
        .help(source.title)

        if PlanStore.extractKey(source.key) == source.key {
            Button { inspector.open(source.key) } label: { label }.buttonStyle(.plain)
        } else if let url = URL(string: source.url), !source.url.isEmpty {
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
struct FlowLayout: Layout {
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

/// Everything the research step did for a plan: tickets opened, searches, and reasoning.
private struct ResearchLog: View {
    let saved: SavedPlan

    var body: some View {
        let items = saved.research
        let tools = items.filter { $0.kind == .tool }
        let tickets = Set(tools.compactMap { PlanStore.extractKey($0.detail) })
        let thoughts = items.filter { $0.kind == .thinking }.count

        VStack(alignment: .leading, spacing: 14) {
            if items.isEmpty {
                ContentUnavailableView(
                    "No research log",
                    systemImage: "magnifyingglass",
                    description: Text("This plan was made before research logs were saved. Re-run it to capture one.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                HStack(spacing: 10) {
                    Stat(value: "\(tickets.count)", label: tickets.count == 1 ? "ticket read" : "tickets read", icon: "ticket")
                    Stat(value: "\(tools.count)", label: tools.count == 1 ? "lookup" : "lookups", icon: "arrow.down.doc")
                    Stat(value: "\(thoughts)", label: thoughts == 1 ? "thought" : "thoughts", icon: "brain")
                    if let d = saved.researchDuration {
                        Stat(value: Duration.seconds(d).formatted(.units(allowed: [.minutes, .seconds], width: .narrow)),
                             label: "research time", icon: "clock")
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(item.at, format: .dateTime.hour().minute().second())
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 62, alignment: .trailing)
                            FeedRow(item: item)
                        }
                    }
                    Label("Plan ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                        .padding(.leading, 72)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.opacity(0.55), in: .rect(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.separator.opacity(0.5)))
            }
        }
        .environment(\.ticketTracker, saved.tracker)
    }
}

private struct Stat: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.headline.monospacedDigit())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

/// Explains the seal icons under the acceptance criteria.
private struct CriteriaLegend: View {
    let hasUncovered: Bool

    var body: some View {
        HStack(spacing: 14) {
            Label("Click to mark met", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            Label("Tests to do", systemImage: "seal")
            Label("Tests done", systemImage: "checkmark.seal")
            if hasUncovered {
                Label("No test task covers it — verify manually or ask", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }
}

/// One end-to-end journey: role, goal, steps and the end result. Tickable.
private struct ScenarioCard: View {
    let scenario: TestPlan.Scenario
    let isDone: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isDone ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(isDone ? "Mark not run" : "Mark run")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(scenario.title).font(.body.weight(.semibold)).strikethrough(isDone)
                        .foregroundStyle(isDone ? .secondary : .primary)
                    Spacer(minLength: 8)
                    Chip(text: scenario.basis == "tickets" ? "from tickets" : scenario.basis == "codebase" ? "from code" : "tickets + code",
                         tint: scenario.basis == "tickets" ? .blue : .purple)
                }
                Label(scenario.role, systemImage: "person.fill").font(.caption).foregroundStyle(.secondary)
                if !isDone {
                    Text(scenario.goal).font(.callout).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(scenario.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(i + 1).").font(.callout.monospacedDigit()).foregroundStyle(.tertiary)
                                    .frame(width: 20, alignment: .trailing)
                                Text(step).font(.callout)
                            }
                        }
                    }
                    .textSelection(.enabled)
                    Label { Text(scenario.expected).font(.callout) } icon: {
                        Image(systemName: "flag.checkered").foregroundStyle(.purple)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.purple.opacity(0.08), in: .rect(cornerRadius: 10))
                    .textSelection(.enabled)
                    if !scenario.relatedTickets.isEmpty {
                        HStack(spacing: 6) {
                            Text("Based on").font(.caption).foregroundStyle(.tertiary)
                            ForEach(scenario.relatedTickets, id: \.self) { key in
                                TicketKeyButton(key: key, font: .caption.monospaced())
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.background.opacity(isDone ? 0.2 : 0.6), in: .rect(cornerRadius: 14))
    }
}

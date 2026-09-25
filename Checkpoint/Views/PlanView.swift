import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct PlanView: View {
    let saved: SavedPlan
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(TicketInspector.self) private var inspector
    @State private var filter: Filter = .todo
    @State private var pane: Pane = .plan
    /// Quick lenses over the task list (IDEA-001/002).
    @State private var smokeOnly = false
    @State private var p0Only = false
    /// Keyboard-first testing (IDEA-029).
    @State private var selectedTaskID: String?
    @State private var noteTaskID: String?
    @FocusState private var listFocused: Bool

    enum Pane: String, CaseIterable { case plan = "Plan", research = "Research", chat = "Chat" }
    @State private var copied = false

    enum Filter: String, CaseIterable { case todo = "To do", all = "All", failed = "Failed", blocked = "Blocked" }

    private var plan: TestPlan { saved.plan }

    /// Moves the keyboard selection within the currently visible tasks.
    private func moveSelection(_ step: Int) {
        let ids = visibleTasks.map(\.id)
        guard !ids.isEmpty else { return }
        let i = selectedTaskID.flatMap(ids.firstIndex(of:)) ?? (step > 0 ? -1 : 0)
        selectedTaskID = ids[min(max(i + step, 0), ids.count - 1)]
    }

    private var taskListAccessory: some View {
        HStack(spacing: 8) {
            LensToggle(label: "Smoke", icon: "flame", on: $smokeOnly)
                .help("5-minute smoke subset: highest-risk tasks first (IDEA-001)")
            LensToggle(label: "P0", icon: "exclamationmark.triangle", on: $p0Only)
                .help("High-blast-radius tasks only (IDEA-002)")
            RegenMenu(section: .tasks, saved: saved)
            Picker("", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)
        }
    }

    /// Keyboard-focusable task list (IDEA-029).
    private var taskList: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(groupedTasks, id: \.key) { group in
                VStack(alignment: .leading, spacing: 8) {
                    if groupedTasks.count > 1 || group.key != plan.ticket.key {
                        TicketTag(key: group.key, title: title(for: group.key), url: url(for: group.key))
                    }
                    ForEach(group.tasks) { task in
                        TaskRow(task: task, saved: saved,
                                selected: selectedTaskID == task.id,
                                forceNote: noteTaskID == task.id,
                                onNoteDone: { if noteTaskID == task.id { noteTaskID = nil } })
                    }
                }
            }
            Text("Click the list, then j/k move · space tick · f fail · b blocked · n note")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .focusable()
        .focused($listFocused)
        .onKeyPress("j", action: { moveSelection(1); return .handled })
        .onKeyPress("k", action: { moveSelection(-1); return .handled })
        .onKeyPress(.space, action: { toggleSelected(); return .handled })
        .onKeyPress("f", action: { verdictSelected(.fail); return .handled })
        .onKeyPress("b", action: { verdictSelected(.blocked); return .handled })
        .onKeyPress("n", action: {
            if let id = selectedTaskID ?? visibleTasks.first?.id { noteTaskID = id }
            return .handled
        })
    }

    private func toggleSelected() {
        withAnimation(.smooth) { store.toggle(selectedTaskID ?? visibleTasks.first?.id ?? "", in: saved.id) }
    }

    private func verdictSelected(_ v: TaskVerdict) {
        let id = selectedTaskID ?? visibleTasks.first?.id ?? ""
        guard !id.isEmpty else { return }
        let detail = v == .fail ? (saved.failed[id] ?? "") : (saved.blocked[id] ?? "")
        withAnimation(.smooth) { store.setVerdict(v, for: id, in: saved.id, detail: detail) }
    }

    private enum ExportFormat { case markdown, html }

    /// Save panel → writes the file; HTML opens in the browser afterwards.
    private func export(_ format: ExportFormat) {
        let panel = NSSavePanel()
        let ext = format == .html ? "html" : "md"
        panel.nameFieldStringValue = "\(plan.ticket.key) test plan.\(ext)"
        panel.allowedContentTypes = [format == .html ? .html : UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.message = format == .html ? "A styled, self-contained page you can open, share or print." : "Markdown you can paste into Jira, GitHub or docs."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let ctx = PlanExporter.Context(saved: saved, smokeOnly: smokeOnly)
        let text = format == .html ? PlanExporter.html(ctx) : PlanExporter.markdown(ctx)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            if format == .html { NSWorkspace.shared.open(url) } else { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        } catch {
            store.error = "Couldn't save: \(error.localizedDescription)"
        }
    }
    private var detailsOpen: Bool { inspector.currentKey == plan.ticket.key.uppercased() }

    private var visibleTasks: [TestPlan.Task] {
        var list: [TestPlan.Task]
        switch filter {
        case .all: list = plan.tasks
        case .todo: list = plan.tasks.filter { saved.verdict(of: $0.id) == .todo }
        case .failed: list = plan.tasks.filter { saved.verdict(of: $0.id) == .fail }
        case .blocked: list = plan.tasks.filter { saved.verdict(of: $0.id) == .blocked }
        }
        if p0Only { list = list.filter { $0.priority == .high } }
        if smokeOnly {
            let ids = Set(plan.smokeSubset.map(\.id))
            list = list.filter { ids.contains($0.id) }
        }
        return list
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
                    if let diff = store.planDiff, diff.planID == saved.id {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.blue)
                            Text("Updated since last run: \(diff.summary)")
                                .font(.callout)
                            Spacer(minLength: 8)
                            Button("Dismiss") { store.clearDiff() }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    }
                    if !plan.preconditions.isEmpty {
                        Section(title: "Before you start", icon: "wrench.and.screwdriver") {
                            BulletList(items: plan.preconditions)
                        }
                    }

                    if !plan.acceptanceCriteria.isEmpty {
                        Section(title: "Acceptance criteria", icon: "target", accessory: {
                        RegenMenu(section: .ac, saved: saved)
                    }) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(plan.acceptanceCriteria) { ac in
                                    CriterionRow(criterion: ac, state: coverage(of: ac),
                                                 isMet: saved.metCriteria.contains(ac.id), saved: saved) {
                                        withAnimation(.smooth) { store.toggleCriterion(ac.id, in: saved.id) }
                                    }
                                }
                                CriteriaLegend(hasUncovered: plan.acceptanceCriteria.contains { coverage(of: $0) == .uncovered })
                                    .padding(.top, 4)
                            }
                        }
                    }

                    Section(title: "Test tasks", icon: "checklist", accessory: {
                        taskListAccessory
                    }) {
                        if visibleTasks.isEmpty {
                            Label("All done — nice.", systemImage: "party.popper")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }
                        taskList
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
                        Section(title: "Edge cases worth poking", icon: "exclamationmark.triangle", accessory: {
                            HStack(spacing: 8) {
                                RegenMenu(section: .edgeCases, saved: saved)
                                Button("Add more edge cases", systemImage: "plus.circle") {
                                    withAnimation(.smooth) { store.boostEdgeCases(in: saved.id) }
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                                .help("Append curated negative-path tasks, skipping near-duplicates (IDEA-017)")
                            }
                        }) {
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
                } else if pane == .research {
                    ResearchLog(saved: saved)
                } else {
                    ChatView(saved: saved)
                }
            }
            .environment(\.ticketTracker, saved.tracker)
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 140)
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
                    Label("Chat\(saved.chat.isEmpty ? "" : " (\(saved.chat.count))")", systemImage: "bubble.left.and.text.bubble.right")
                        .tag(Pane.chat)
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleOnly)
                .help("Switch between the test plan and the research that produced it")
            }
            ToolbarItemGroup {
                Menu {
                    Button("Copy as Markdown", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(PlanExporter.markdown(.init(saved: saved, smokeOnly: smokeOnly)), forType: .string)
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    }
                    Divider()
                    Button("Copy Playwright skeleton", systemImage: "chevron.left.forwardslash.chevron.right") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(PlanExporter.automation(.init(saved: saved), framework: .playwright), forType: .string)
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    }
                    Button("Copy XCTest skeleton", systemImage: "checkmark.rectangle") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(PlanExporter.automation(.init(saved: saved), framework: .xctest), forType: .string)
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    }
                    Divider()
                    Button("Save as Markdown…", systemImage: "doc.text") { export(.markdown) }
                    Button("Save as HTML Page…", systemImage: "safari") { export(.html) }
                } label: {
                    Label(copied ? "Copied" : "Export", systemImage: copied ? "checkmark" : "square.and.arrow.up")
                }
                .help("Copy or save this plan as Markdown or a styled HTML page")
                Menu {
                    Button(saved.pinned ? "Unpin" : "Pin", systemImage: saved.pinned ? "pin.slash" : "pin") {
                        store.togglePin(saved.id)
                    }
                    Button(saved.archived ? "Restore from archive" : "Archive", systemImage: saved.archived ? "tray.and.arrow.down" : "archivebox") {
                        store.toggleArchive(saved.id)
                    }
                    Divider()
                    if saved.dueDate == nil {
                        Button("Remind me tomorrow", systemImage: "bell") {
                            store.setDueDate(Calendar.current.date(byAdding: .day, value: 1, to: .now), for: saved.id)
                        }
                        Button("Remind me in a week", systemImage: "bell.badge") {
                            store.setDueDate(Calendar.current.date(byAdding: .day, value: 7, to: .now), for: saved.id)
                        }
                    } else {
                        Button("Clear reminder", systemImage: "bell.slash", role: .destructive) {
                            store.setDueDate(nil, for: saved.id)
                        }
                    }
                } label: {
                    Label("Organise", systemImage: "folder.badge.gearshape")
                }
                .help("Pin, archive, tags, reminder")
                Button("Re-run", systemImage: "arrow.clockwise") {
                    if saved.preset == "quick" {
                        let q = PlanStore.quickOverrides(settings: settings)
                        store.analyze(saved.plan.ticket.key, mode: saved.mode, tracker: saved.tracker,
                                      modelOverride: q.model, effortOverride: q.effort, settings: settings)
                    } else {
                        store.analyze(saved.plan.ticket.key, mode: saved.mode, tracker: saved.tracker, settings: settings)
                    }
                }
                if saved.preset == "quick" {
                    Button("Upgrade to deep", systemImage: "arrow.up.circle") {
                        store.analyze(saved.plan.ticket.key, mode: saved.mode, tracker: saved.tracker, settings: settings)
                    }
                    .help("Re-run on your best model and effort")
                }
                Button("Mini checklist", systemImage: "rectangle.on.rectangle") {
                    MiniPanelController.shared.toggle(with: store)
                }
                .help("Floating always-on-top checklist for testing in a browser")
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
                    if saved.template != "auto" { Chip(text: "Template: \(saved.template.capitalized)", tint: .orange) }
                    if saved.preset == "quick" { Chip(text: "Quick", tint: .teal) }
                    if let mins = plan.estimatedMinutes { Chip(text: "⏱ ~\(mins) min") }
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
                if saved.failedCount > 0 || saved.blockedCount > 0 {
                    HStack(spacing: 12) {
                        if saved.failedCount > 0 {
                            Label("\(saved.failedCount) failed", systemImage: "xmark.circle.fill")
                                .font(.callout.weight(.medium)).foregroundStyle(.red)
                        }
                        if saved.blockedCount > 0 {
                            Label("\(saved.blockedCount) blocked", systemImage: "exclamationmark.circle.fill")
                                .font(.callout.weight(.medium)).foregroundStyle(.orange)
                        }
                    }
                }
                OrganiseRow(saved: saved)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 16) {
                    MetricRing(value: saved.progress, label: "tested",
                               text: "\(saved.tasksDone)/\(plan.tasks.count)", tint: .accentColor)
                    if !plan.acceptanceCriteria.isEmpty {
                        MetricRing(value: saved.criteriaProgress, label: "AC met",
                                   text: "\(saved.criteriaMet)/\(plan.acceptanceCriteria.count)", tint: .teal)
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Button {
                        withAnimation(.smooth) { store.toggleTimer(for: saved.id) }
                    } label: {
                        Label("\(PlanStore.formatDuration(store.elapsedTesting(saved))) · \(saved.timerRunningSince != nil ? "stop" : "start")",
                              systemImage: saved.timerRunningSince != nil ? "pause.circle.fill" : "timer")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help("Track time spent testing this plan (IDEA-025)")
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
    let saved: SavedPlan
    var selected = false
    var forceNote = false
    var onNoteDone: () -> Void = {}
    @Environment(PlanStore.self) private var store
    @State private var expanded = true
    @State private var verdictDraft: TaskVerdict?
    @State private var detailText = ""
    @State private var editingNote = false
    @State private var noteText = ""
    @State private var reportingBug = false
    @State private var showingWhy = false

    private var verdict: TaskVerdict { saved.verdict(of: task.id) }
    private var isDone: Bool { verdict == .pass }

    /// Derived rationale from priority, coverage and sources (IDEA-086 V1).
    private var whyExplanation: String {
        var s = ""
        switch task.priority {
        case .high: s += "This is a P0 check — it guards the change's main blast radius. "
        case .medium: s += "This is a P1 check — worth running in a normal pass. "
        case .low: s += "This is a P2 check — run it when time allows. "
        }
        if task.covers.isEmpty {
            s += "It isn't tied to a specific acceptance criterion — it covers the change generally. "
        } else {
            s += "It covers \(task.covers.joined(separator: ", ")). "
        }
        if task.sources.isEmpty {
            s += "Source: \(task.ticketKey)."
        } else {
            s += "Drawn from " + task.sources.map { "\($0.ticketKey) (\($0.kind): \($0.ref))" }.joined(separator: ", ") + "."
        }
        return s
    }

    /// Re-run highlight (IDEA-007): green = new task, orange = changed.
    private var diffMark: Color? {
        guard let d = store.planDiff, d.planID == saved.id else { return nil }
        if d.addedTasks.contains(task.id) { return .green }
        if d.changedTasks.contains(task.id) { return .orange }
        return nil
    }

    /// Image/file picker for evidence (IDEA-022).
    private func attachFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Attach screenshots or files to “\(task.title)”."
        guard panel.runModal() == .OK else { return }
        withAnimation(.smooth) {
            store.attachEvidence(panel.urls, planID: saved.id, taskID: task.id)
        }
    }

    private var verdictColor: AnyShapeStyle {
        switch verdict {
        case .todo: AnyShapeStyle(.secondary)
        case .pass: AnyShapeStyle(.green)
        case .fail: AnyShapeStyle(.red)
        case .blocked: AnyShapeStyle(.orange)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation(.smooth) { store.toggle(task.id, in: saved.id) }
            } label: {
                Image(systemName: verdict.icon)
                    .font(.title2)
                    .foregroundStyle(verdictColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(verdict == .pass ? "Mark untested" : "Mark passed")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .strikethrough(isDone)
                        .foregroundStyle(isDone ? .secondary : .primary)
                    Spacer(minLength: 8)
                    if !task.area.isEmpty { Chip(text: task.area) }
                    RiskChip(risk: task.risk)
                    if let mins = task.estimateMin {
                        Chip(text: "⏱ ~\(mins) min")
                            .help("Rough manual-testing estimate")
                    }
                    PriorityDot(priority: task.priority)
                    Menu {
                        ForEach(TaskVerdict.allCases) { v in
                            Button {
                                if v == .fail || v == .blocked {
                                    detailText = v == .fail ? (saved.failed[task.id] ?? "") : (saved.blocked[task.id] ?? "")
                                    verdictDraft = v
                                } else {
                                    withAnimation(.smooth) { store.setVerdict(v, for: task.id, in: saved.id) }
                                }
                            } label: {
                                Label(v.label, systemImage: v.icon)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.tertiary)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .help("Set outcome: pass, fail, blocked")
                    .fixedSize()
                    Button {
                        showingWhy = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Why this task?")
                    .fixedSize()
                    .popover(isPresented: $showingWhy) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Why this task?").font(.headline)
                            Text(whyExplanation)
                                .font(.callout)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(width: 320)
                    }
                }
                .contentShape(.rect)
                .onTapGesture { withAnimation(.smooth) { expanded.toggle() } }

                if verdict == .fail {
                    Label(saved.failed[task.id]?.isEmpty == false ? saved.failed[task.id]! : "Failed — no detail yet",
                          systemImage: "xmark.octagon.fill")
                        .font(.callout).foregroundStyle(.red)
                        .textSelection(.enabled)
                    Button("Report bug…", systemImage: "ant") { reportingBug = true }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                } else if verdict == .blocked {
                    Label(saved.blocked[task.id]?.isEmpty == false ? saved.blocked[task.id]! : "Blocked — no reason yet",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                        .textSelection(.enabled)
                }

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

                    if !task.testData.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "tablecells").foregroundStyle(.blue)
                            Text(task.testData.joined(separator: "  ·  "))
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                            Spacer(minLength: 4)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(task.testData.joined(separator: "\n"), forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc").font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                            .help("Copy sample data")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.blue.opacity(0.07), in: .rect(cornerRadius: 10))
                    }

                    if !task.covers.isEmpty {
                        Text("Covers " + task.covers.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if !task.sources.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right").font(.caption2).foregroundStyle(.tertiary)
                            ForEach(Array(task.sources.enumerated()), id: \.offset) { _, src in
                                if src.ticketKey == "derived" {
                                    Text("derived").font(.caption).foregroundStyle(.tertiary)
                                } else {
                                    TicketKeyButton(key: src.ticketKey, font: .caption.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .help("\(src.kind): \(src.ref)")
                                }
                            }
                        }
                    }
                    if let note = saved.notes[task.id], !editingNote {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "note.text").foregroundStyle(.yellow)
                            Text(note).font(.callout).textSelection(.enabled)
                            Spacer(minLength: 4)
                            Button("Edit") { noteText = note; editingNote = true }
                                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.yellow.opacity(0.08), in: .rect(cornerRadius: 10))
                    }
                    if editingNote {
                        TextField("Testing note…", text: $noteText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                            .lineLimit(2...5)
                        HStack {
                            Spacer()
                            Button("Cancel") { editingNote = false; onNoteDone() }.buttonStyle(.plain).font(.caption)
                            Button("Save note") {
                                store.setNote(noteText, for: task.id, in: saved.id)
                                editingNote = false
                                onNoteDone()
                            }
                            .buttonStyle(.glassProminent).controlSize(.small)
                        }
                    }
                    let attachments = saved.evidence[task.id] ?? []
                    if !attachments.isEmpty || expanded {
                        HStack(spacing: 8) {
                            Image(systemName: "paperclip").foregroundStyle(.tertiary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(attachments, id: \.self) { name in
                                        EvidenceThumb(name: name, saved: saved, taskID: task.id)
                                    }
                                    Button {
                                        attachFiles()
                                    } label: {
                                        Label("Attach", systemImage: "plus.circle")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .help("Attach screenshots or files (IDEA-022)")
                                }
                            }
                            if saved.notes[task.id] == nil && !editingNote {
                                Spacer(minLength: 4)
                                Button {
                                    noteText = ""
                                    editingNote = true
                                } label: {
                                    Image(systemName: "note.text.badge.plus").font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tertiary)
                                .help("Add a testing note")
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.background.opacity(isDone ? 0.2 : 0.6), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(diffMark ?? (selected ? .accentColor : .clear), lineWidth: selected ? 2 : 1.5)
        }
        .onChange(of: forceNote, perform: { on in
            if on {
                noteText = saved.notes[task.id] ?? ""
                editingNote = true
            }
        })
        .sheet(item: $verdictDraft) { draft in
            VerdictSheet(title: draft == .blocked ? "Why is this blocked?" : "What actually happened?",
                         placeholder: draft == .blocked ? "e.g. waiting on staging deploy" : "e.g. card list was empty",
                         text: $detailText,
                         onSave: {
                             withAnimation(.smooth) { store.setVerdict(draft, for: task.id, in: saved.id, detail: detailText) }
                         })
        }
        .sheet(isPresented: $reportingBug) {
            BugReportSheet(task: task, saved: saved)
        }
    }
}

/// Acceptance criterion with a checkbox: click the seal to mark it met.

/// Acceptance criterion with a checkbox: click the seal to mark it met.
/// While unmet, the seal hints at task coverage (uncovered / pending / ready).
/// Vague criteria get an amber flag with draft questions (IDEA-008); uncovered
/// ones offer one-click gap fill (IDEA-016).
private struct CriterionRow: View {
    enum Coverage { case verified, pending, uncovered }
    let criterion: TestPlan.Criterion
    let state: Coverage
    let isMet: Bool
    let saved: SavedPlan
    let toggle: () -> Void
    @Environment(PlanStore.self) private var store
    @State private var hovering = false
    @State private var showingVague = false

    /// Advisory vagueness flag: very short text or hedged wording.
    static func vagueness(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count < 25 { return "very short" }
        let hedges = ["correctly", "properly", "appropriately", "as expected", "works well", "relevant", "necessary changes"]
        if hedges.contains(where: { t.lowercased().contains($0) }) { return "vague wording" }
        return nil
    }

    private var drafts: [String] {
        [
            "What does “\(criterion.text.prefix(60))” mean concretely — which screen, what observable result?",
            "Are there roles, tenants or data where this doesn't apply?",
            "How do we verify it on the hosted environment, and who confirms sign-off items?",
        ]
    }

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
            if !isMet, let vague = Self.vagueness(criterion.text) {
                Button {
                    showingVague = true
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Possibly ambiguous (\(vague)) — see draft questions")
                .popover(isPresented: $showingVague) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Possibly ambiguous (\(vague))").font(.headline)
                        ForEach(drafts, id: \.self) { q in
                            Text("• " + q).font(.callout).textSelection(.enabled)
                        }
                        Button("Copy questions") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(drafts.joined(separator: "\n"), forType: .string)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    .padding(16)
                    .frame(width: 340)
                }
            }
            if !isMet && state == .uncovered {
                Button {
                    withAnimation(.smooth) { store.suggestTask(for: criterion.id, in: saved.id) }
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Draft the missing task for this criterion")
            }
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

/// Evidence thumbnail with open + remove (IDEA-022).
private struct EvidenceThumb: View {
    let name: String
    let saved: SavedPlan
    let taskID: String
    @Environment(PlanStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            if let data = store.evidenceData(name, planID: saved.id, taskID: taskID),
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 8))
                    .onTapGesture {
                        NSWorkspace.shared.open(store.evidenceDir(planID: saved.id, taskID: taskID).appending(path: name))
                    }
                    .help("Open \(name)")
            } else {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(.quaternary, in: .rect(cornerRadius: 8))
                    .onTapGesture {
                        NSWorkspace.shared.open(store.evidenceDir(planID: saved.id, taskID: taskID).appending(path: name))
                    }
                    .help("Open \(name)")
            }
            Button {
                withAnimation(.smooth) { store.removeEvidence(name, planID: saved.id, taskID: taskID) }
            } label: {
                Image(systemName: "xmark.circle.fill").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Remove")
        }
    }
}

/// Pre-filled bug report from a failed task (IDEA-027): copy, or later create.
private struct BugReportSheet: View {
    let task: TestPlan.Task
    let saved: SavedPlan
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var actual = ""
    @State private var copied = false

    private var report: String {
        var md = "## Bug: \(title.isEmpty ? task.title : title)\n"
        md += "\nFound while testing \(saved.plan.ticket.key) — \(saved.plan.ticket.title).\n"
        md += "\n**Steps:**\n" + task.steps.enumerated().map { "\(1 + $0.offset). \($0.element)" }.joined(separator: "\n") + "\n"
        md += "\n**Expected:** \(task.expected)\n"
        md += "\n**Actual:** \(actual)\n"
        if let files = saved.evidence[task.id], !files.isEmpty {
            md += "\n**Evidence:** \(files.joined(separator: ", "))\n"
        }
        if let note = saved.notes[task.id], !note.isEmpty {
            md += "\n**Testing note:** \(note)\n"
        }
        return md
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report bug").font(.headline)
            TextField("Title", text: $title, prompt: Text(task.title))
                .textFieldStyle(.roundedBorder)
            TextField("What actually happened", text: $actual, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
            Text(report)
                .font(.callout).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxHeight: 220)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            Text("One-click issue creation needs a write connection — for now, copy into Jira/Linear.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(copied ? "Copied" : "Copy report", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    copied = true
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear(perform: {
            actual = saved.failed[task.id] ?? ""
        })
    }
}

/// Actual-result / block-reason prompt for Fail and Blocked verdicts.
private struct VerdictSheet: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
            Text("Empty is fine — you can add detail later from the task menu.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: { onSave(); dismiss() })
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

/// P0/P1/P2 risk badge derived from priority (IDEA-002).
private struct RiskChip: View {
    let risk: String

    private var tint: Color {
        switch risk {
        case "P0": .red
        case "P1": .orange
        default: .gray
        }
    }

    var body: some View {
        Text(risk)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: .capsule)
            .help(risk == "P0" ? "Highest blast radius — run first" : "Blast radius: \(risk)")
    }
}

/// Regenerate-one-section button (IDEA-084). Ticks survive via ID merge.
private struct RegenMenu: View {
    let section: PlanStore.RevisionSection
    let saved: SavedPlan
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings

    private var busy: Bool { store.regenerating?.hasPrefix(saved.id) == true }

    var body: some View {
        Button {
            store.regenerate(section: section, in: saved.id, settings: settings)
        } label: {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Label("Regenerate \(section.label)", systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(busy || store.chatBusyID != nil)
        .help("Redo just \(section.label) — ticks on surviving items are kept")
    }
}

/// Follow-up chat over a finished plan (IDEA-083).
private struct ChatView: View {
    let saved: SavedPlan
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var question = ""

    private var busy: Bool { store.chatBusyID == saved.id || store.regenerating?.hasPrefix(saved.id) == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask follow-ups about this plan — answers stay here, and anything useful can update the plan with ticks intact.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if saved.chat.isEmpty {
                        ContentUnavailableView("No questions yet", systemImage: "bubble.left.and.text.bubble.right",
                                               description: Text("Try “what about admins?” or “add coverage for offline mode”."))
                    }
                    ForEach(saved.chat) { msg in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(msg.role == .user ? "You" : "Checkpoint",
                                  systemImage: msg.role == .user ? "person" : "sparkles")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(msg.text)
                                .font(.callout)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if msg.role == .assistant && !msg.text.hasPrefix("Couldn't answer") {
                                Button("Update plan from this", systemImage: "arrow.triangle.2.circlepath") {
                                    store.applyChatRevision(msg.text, in: saved.id, settings: settings)
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                                .disabled(busy)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.opacity(0.55), in: .rect(cornerRadius: 14))
                    }
                    if busy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(store.chatBusyID == saved.id ? "Thinking…" : "Updating plan…")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack {
                TextField("Ask a follow-up…", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit(ask)
                    .disabled(busy)
                Button("Ask", action: ask)
                    .buttonStyle(.glassProminent)
                    .disabled(busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        question = ""
        store.sendChat(q, in: saved.id, settings: settings)
    }
}

/// Small on/off pill for the Smoke / P0 task-list lenses.
private struct LensToggle: View {
    let label: String
    let icon: String
    @Binding var on: Bool

    var body: some View {
        Button {
            withAnimation(.smooth) { on.toggle() }
        } label: {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(on ? .white : .secondary)
                .background(on ? Color.accentColor.gradient : Color.clear.gradient,
                            in: .capsule)
                .overlay(Capsule().strokeBorder(on ? Color.clear : Color.secondary.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular.tint(tint.opacity(0.2)), in: .capsule)
    }
}

/// Tags + due date row under the plan header (IDEA-102/110).
private struct OrganiseRow: View {
    let saved: SavedPlan
    @Environment(PlanStore.self) private var store
    @State private var editingTags = false
    @State private var tagText = ""

    var body: some View {
        HStack(spacing: 8) {
            if saved.tags.isEmpty && saved.dueDate == nil && !editingTags {
                Button("Add tags or reminder…", systemImage: "tag") { tagText = ""; editingTags = true }
                    .buttonStyle(.link).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(saved.tags.sorted(), id: \.self) { tag in
                    Text(tag).font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: .capsule)
                }
                if let due = saved.dueDate {
                    Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: saved.isOverdue ? "bell.badge.fill" : "bell")
                        .font(.caption).foregroundStyle(saved.isOverdue ? .red : .secondary)
                }
                Button(editingTags ? "Done" : "Edit", systemImage: "tag") {
                    if editingTags {
                        store.setTags(Set(tagText.split(separator: ",").map(String.init)), for: saved.id)
                    } else {
                        tagText = saved.tags.sorted().joined(separator: ", ")
                    }
                    editingTags.toggle()
                }
                .buttonStyle(.link).font(.caption)
            }
        }
        if editingTags {
            TextField("tags, comma separated", text: $tagText, prompt: Text("sprint-12, needs-qa"))
                .textFieldStyle(.roundedBorder).font(.callout)
                .onSubmit {
                    store.setTags(Set(tagText.split(separator: ",").map(String.init)), for: saved.id)
                    editingTags = false
                }
        }
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
                    if let u = saved.usage, !u.isEmpty {
                        Stat(value: u.display(provider: LLMProvider(rawValue: saved.usageProvider) ?? .anthropic,
                                              model: saved.usageModel),
                             label: "model cost", icon: "dollarsign.circle")
                            .help("Tokens + approximate cost for the run that produced this plan")
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

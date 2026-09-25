import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct PlanView: View {
    let saved: SavedPlan
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(TicketInspector.self) private var inspector
    @State private var filter: Filter = .todo
    @State private var pane: Pane = .plan
    /// Task-list lenses: the smoke subset and P0-only.
    @State private var smokeOnly = false
    @State private var p0Only = false
    /// Keyboard-first testing: j/k move, space ticks, f/b/n.
    @State private var selectedTaskID: String?
    @State private var noteTaskID: String?
    @FocusState private var listFocused: Bool
    @State private var copied = false
    @State private var editingTags = false
    @State private var headerWidth: CGFloat = 800
    #if os(iOS)
    @State private var sharing: SharedFile?
    #endif

    enum Pane: String, CaseIterable { case plan = "Plan", research = "Research", chat = "Chat" }
    enum Filter: String, CaseIterable { case todo = "To do", all = "All", failed = "Failed", blocked = "Blocked" }

    private var plan: TestPlan { saved.plan }
    private var detailsOpen: Bool { inspector.currentKey == plan.ticket.key.uppercased() }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                #if os(iOS)
                panePicker
                #endif
                header

                if pane == .plan {
                    if let diff = store.planDiff, diff.planID == saved.id {
                        diffBanner(diff.summary)
                    }

                    if !plan.preconditions.isEmpty {
                        Section(title: "Before you start", icon: "wrench.and.screwdriver") {
                            BulletList(items: plan.preconditions)
                        }
                    }

                    if !plan.acceptanceCriteria.isEmpty {
                        Section(title: "Acceptance criteria", icon: "target", accessory: {
                            SectionMenu(saved: saved, section: .ac)
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

                    Section(title: "Test tasks", icon: "checklist", accessory: { taskListAccessory }) {
                        if smokeOnly || p0Only { lensBar }
                        if visibleTasks.isEmpty {
                            Label(filter == .todo ? "All done — nice." : "Nothing here.",
                                  systemImage: filter == .todo ? "party.popper" : "tray")
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
                            SectionMenu(saved: saved, section: .edgeCases) {
                                Button("Add more edge-case tasks", systemImage: "plus.circle") {
                                    withAnimation(.smooth) { store.boostEdgeCases(in: saved.id) }
                                }
                                .help("Appends curated negative-path tasks, skipping near-duplicates")
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
            .padding(.horizontal, PageLayout.side)
            .padding(.top, PageLayout.top)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .glassScrollIndicator()
        .safeAreaInset(edge: .bottom) {
            if pane == .chat { ChatComposer(saved: saved) }
        }
        #if os(iOS)
        .sheet(item: $sharing) { file in ShareSheet(items: [file.url]).presentationDetents([.medium, .large]) }
        #endif
        .onChange(of: saved.chat.count) {
            guard pane == .chat else { return }
            withAnimation(.smooth) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
        }
        .onChange(of: store.chatBusyID) {
            guard pane == .chat else { return }
            withAnimation(.smooth) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
        }
        }
        .toolbar { toolbar }
    }

    // MARK: Toolbar

    private var panePicker: some View {
        Picker("View", selection: $pane) {
            Label("Plan", systemImage: "checklist").tag(Pane.plan)
            Label("Research (\(saved.research.filter { $0.kind != .status }.count))", systemImage: "magnifyingglass")
                .tag(Pane.research)
            Label(saved.chat.isEmpty ? "Chat" : "Chat (\(saved.chat.count))", systemImage: "bubble.left.and.text.bubble.right")
                .tag(Pane.chat)
        }
        .pickerStyle(.segmented)
        .labelStyle(.titleOnly)
        .labelsHidden()
    }

    #if os(iOS)
    /// iOS: the ticket-details button, and every other action in one menu.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Ticket Details", systemImage: "info.circle") {
                withAnimation(.smooth) { inspector.toggle(plan.ticket.key, tracker: saved.tracker) }
            }
            Menu {
                Menu("Export", systemImage: "square.and.arrow.up") {
                    Button("Share as Markdown…", systemImage: "doc.text") { export(.markdown) }
                    Button("Share as HTML Page…", systemImage: "safari") { export(.html) }
                    Divider()
                    Button("Copy as Markdown", systemImage: "doc.on.doc") {
                        copy(PlanExporter.markdown(.init(saved: saved, smokeOnly: smokeOnly)))
                    }
                    Button("Copy Playwright Skeleton", systemImage: "chevron.left.forwardslash.chevron.right") {
                        copy(PlanExporter.automation(.init(saved: saved), framework: .playwright))
                    }
                    Button("Copy XCTest Skeleton", systemImage: "hammer") {
                        copy(PlanExporter.automation(.init(saved: saved), framework: .xctest))
                    }
                }
                Button("Re-run", systemImage: "arrow.clockwise", action: rerun)
                if saved.preset == "quick" {
                    Button("Upgrade to Deep", systemImage: "arrow.up.circle", action: rerunDeep)
                }
                if let url = URL(string: plan.ticket.url), url.scheme != nil {
                    Button("Open in \(saved.tracker.label)", systemImage: "arrow.up.right.square") { Platform.open(url) }
                }
                Divider()
                Button(saved.pinned ? "Unpin" : "Pin", systemImage: saved.pinned ? "pin.slash" : "pin") {
                    store.togglePin(saved.id)
                }
                Button("Tags…", systemImage: "tag") { editingTags = true }
                Menu("Remind Me", systemImage: "bell") {
                    Button("Tomorrow") { remind(days: 1) }
                    Button("In 3 Days") { remind(days: 3) }
                    Button("Next Week") { remind(days: 7) }
                    if saved.dueDate != nil {
                        Button("Clear Reminder", role: .destructive) { store.setDueDate(nil, for: saved.id) }
                    }
                }
                Button(saved.archived ? "Restore from Archive" : "Archive",
                       systemImage: saved.archived ? "tray.and.arrow.up" : "archivebox") {
                    store.toggleArchive(saved.id)
                }
            } label: {
                Label(copied ? "Copied" : "More", systemImage: copied ? "checkmark" : "ellipsis")
            }
        }
    }
    #else
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $pane) {
                Label("Plan", systemImage: "checklist").tag(Pane.plan)
                Label("Research (\(saved.research.filter { $0.kind != .status }.count))", systemImage: "magnifyingglass")
                    .tag(Pane.research)
                Label(saved.chat.isEmpty ? "Chat" : "Chat (\(saved.chat.count))", systemImage: "bubble.left.and.text.bubble.right")
                    .tag(Pane.chat)
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleOnly)
            .help("The test plan, the research behind it, and follow-up questions")
        }
        ToolbarItemGroup {
            Menu {
                Button("Copy as Markdown", systemImage: "doc.on.doc") {
                    copy(PlanExporter.markdown(.init(saved: saved, smokeOnly: smokeOnly)))
                }
                Divider()
                Button("Save as Markdown…", systemImage: "doc.text") { export(.markdown) }
                Button("Save as HTML Page…", systemImage: "safari") { export(.html) }
                Divider()
                Button("Copy Playwright Skeleton", systemImage: "chevron.left.forwardslash.chevron.right") {
                    copy(PlanExporter.automation(.init(saved: saved), framework: .playwright))
                }
                Button("Copy XCTest Skeleton", systemImage: "hammer") {
                    copy(PlanExporter.automation(.init(saved: saved), framework: .xctest))
                }
            } label: {
                Label(copied ? "Copied" : "Export", systemImage: copied ? "checkmark" : "square.and.arrow.up")
            }
            .help("Copy or save this plan, or start an automation suite from it")

            if saved.preset == "quick" {
                Menu {
                    Button("Upgrade to Deep", systemImage: "arrow.up.circle", action: rerunDeep)
                        .help("Re-run on your best model and effort")
                } label: {
                    Label("Re-run", systemImage: "arrow.clockwise")
                } primaryAction: {
                    rerun()
                }
                .help("Re-run this quick plan, or upgrade it to a deep one")
            } else {
                Button("Re-run", systemImage: "arrow.clockwise", action: rerun)
            }

            if let url = URL(string: plan.ticket.url), url.scheme != nil {
                Button("Open in \(saved.tracker.label)", systemImage: "arrow.up.right.square") {
                    Platform.open(url)
                }
            }

            Menu {
                #if os(macOS)
                Button("Mini Checklist", systemImage: "rectangle.on.rectangle") {
                    MiniPanelController.shared.toggle(with: store)
                }
                .help("A small always-on-top checklist for testing in a browser")
                Divider()
                #endif
                Button(saved.pinned ? "Unpin" : "Pin", systemImage: saved.pinned ? "pin.slash" : "pin") {
                    store.togglePin(saved.id)
                }
                Button("Tags…  ⌘T", systemImage: "tag") { editingTags = true }
                Menu("Remind Me", systemImage: "bell") {
                    Button("Tomorrow") { remind(days: 1) }
                    Button("In 3 Days") { remind(days: 3) }
                    Button("Next Week") { remind(days: 7) }
                    if saved.dueDate != nil {
                        Divider()
                        Button("Clear Reminder", role: .destructive) { store.setDueDate(nil, for: saved.id) }
                    }
                }
                Button(saved.archived ? "Restore from Archive" : "Archive",
                       systemImage: saved.archived ? "tray.and.arrow.up" : "archivebox") {
                    store.toggleArchive(saved.id)
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("Mini checklist, pin, reminders, archive")

            Button(detailsOpen ? "Hide ticket details" : "Show ticket details", systemImage: "sidebar.right") {
                withAnimation(.smooth) { inspector.toggle(plan.ticket.key, tracker: saved.tracker) }
            }
            .keyboardShortcut("i", modifiers: .command)
        }
    }
    #endif

    private func rerun() {
        if saved.preset == "quick" {
            let q = PlanStore.quickOverrides(settings: settings)
            store.analyze(plan.ticket.key, mode: saved.mode, tracker: saved.tracker,
                          modelOverride: q.model, effortOverride: q.effort, settings: settings)
        } else {
            rerunDeep()
        }
    }

    private func rerunDeep() {
        store.analyze(plan.ticket.key, mode: saved.mode, tracker: saved.tracker, settings: settings)
    }

    private func remind(days: Int) {
        store.setDueDate(Calendar.current.date(byAdding: .day, value: days, to: .now), for: saved.id)
    }

    private func copy(_ text: String) {
        Platform.copy(text)
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
    }

    // MARK: Header

    /// Narrow (iPhone, or a squeezed window): rings move under the title.
    private var narrowHeader: Bool { headerWidth < 520 }

    private var header: some View {
        let chips = Group {
            TicketKeyButton(key: plan.ticket.key, font: .headline.monospaced())
            ModeBadge(mode: saved.mode)
            if saved.tracker == .linear { Chip(text: "Linear", tint: .purple) }
            if saved.preset == "quick" { Chip(text: "Quick", tint: .teal) }
            if saved.template != "auto" { Chip(text: saved.template.capitalized, tint: .orange) }
        }
        let detailsButton = Button {
            withAnimation(.smooth) { inspector.toggle(plan.ticket.key, tracker: saved.tracker) }
        } label: {
            Label(detailsOpen ? "Hide details" : "Ticket details", systemImage: "sidebar.right")
                .labelStyle(headerWidth < 600 ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .lineLimit(1)
                .font(.callout.weight(.medium))
        }
        .buttonStyle(.glass)
        .help("Show everything on the ticket (⌘I)")
        let rings = HStack(spacing: 16) {
            MetricRing(value: saved.progress, label: "tested",
                       text: "\(saved.tasksDone)/\(plan.tasks.count)", tint: .accentColor)
            if !plan.acceptanceCriteria.isEmpty {
                MetricRing(value: saved.criteriaProgress, label: "AC met",
                           text: "\(saved.criteriaMet)/\(plan.acceptanceCriteria.count)", tint: .teal)
            }
        }
        let text = Group {
            Text(plan.ticket.title)
                .font(narrowHeader ? .title2.weight(.semibold) : .title.weight(.semibold))
                .textSelection(.enabled)
            Text(plan.summary)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }

        return Group {
            if narrowHeader {
                VStack(alignment: .leading, spacing: 12) {
                    FlowLayout(spacing: 8) {
                        chips
                        Chip(text: plan.ticket.type)
                        Chip(text: plan.ticket.status, tint: .blue)
                    }
                    text
                    HStack(alignment: .center) {
                        rings
                        Spacer(minLength: 8)
                        // iPhone has ⓘ in the toolbar already.
                        if Platform.isMac { detailsButton }
                    }
                    HeaderMeta(saved: saved) { editingTags = true }
                }
            } else {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            chips
                            Spacer(minLength: 8)
                            detailsButton
                            Chip(text: plan.ticket.type)
                            Chip(text: plan.ticket.status, tint: .blue)
                        }
                        text
                        HeaderMeta(saved: saved) { editingTags = true }
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    rings
                }
            }
        }
        .padding(narrowHeader ? 18 : 24)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { headerWidth = $0 }
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .popover(isPresented: $editingTags, arrowEdge: .bottom) {
            TagEditor(saved: saved)
                .presentationCompactAdaptation(.popover)
        }
        .background {
            Button("") { editingTags = true }
                .keyboardShortcut("t", modifiers: .command)
                .hidden()
        }
    }

    private func diffBanner(_ summary: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
            Text("Updated since the last run: \(summary)").font(.callout)
            Spacer(minLength: 8)
            Text("New and changed tasks are outlined.").font(.caption).foregroundStyle(.secondary)
            Button {
                withAnimation(.smooth) { store.clearDiff() }
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(.blue.opacity(0.12)), in: .rect(cornerRadius: 16))
    }

    // MARK: Tasks

    private func count(_ f: Filter) -> Int {
        switch f {
        case .all: plan.tasks.count
        case .todo: plan.tasks.filter { saved.verdict(of: $0.id) == .todo }.count
        case .failed: saved.failedCount
        case .blocked: saved.blockedCount
        }
    }

    /// One glass pill: which tasks to show, the Smoke/P0 lenses and regenerate.
    private var taskListAccessory: some View {
        let lensOn = smokeOnly || p0Only
        return Menu {
            Picker("Show", selection: $filter.animation(.smooth)) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Text("\(f.rawValue)  \(count(f))").tag(f)
                }
            }
            .pickerStyle(.inline)
            SwiftUI.Section("Narrow to") {
                Toggle(isOn: $smokeOnly.animation(.smooth)) {
                    Label("Smoke Subset — top risks, about 5 min", systemImage: "flame")
                }
                Toggle(isOn: $p0Only.animation(.smooth)) {
                    Label("P0 Only", systemImage: "exclamationmark.triangle")
                }
            }
            Divider()
            Button("Regenerate Tasks", systemImage: "arrow.triangle.2.circlepath") {
                store.regenerate(section: .tasks, in: saved.id, settings: settings)
            }
            .disabled(store.regenerating != nil || store.chatBusyID != nil)
            #if os(macOS)
            Divider()
            Text("Keys: j/k move · space pass · f fail · b blocked · n note")
            #endif
        } label: {
            HStack(spacing: 6) {
                if store.regenerating == saved.id + ":tasks" {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: lensOn ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                        .foregroundStyle(lensOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                Text(filter.rawValue).font(.callout.weight(.medium))
                Text("\(count(filter))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(.capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: .capsule)
        .help("Show to do, all, failed or blocked tasks; Smoke and P0 lenses")
    }

    /// Shown only while a lens narrows the list, so it's obvious why tasks are missing.
    private var lensBar: some View {
        HStack(spacing: 8) {
            if smokeOnly { LensChip(label: "Smoke subset", icon: "flame") { smokeOnly = false } }
            if p0Only { LensChip(label: "P0 only", icon: "exclamationmark.triangle") { p0Only = false } }
            let mins = visibleTasks.compactMap(\.estimateMin).reduce(0, +)
            if mins > 0 {
                Text("about \(mins) min").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(groupedTasks, id: \.key) { group in
                VStack(alignment: .leading, spacing: 8) {
                    if groupedTasks.count > 1 || group.key != plan.ticket.key {
                        TicketTag(key: group.key, title: title(for: group.key), url: url(for: group.key))
                    }
                    ForEach(group.tasks) { task in
                        TaskRow(task: task, saved: saved,
                                selected: listFocused && selectedTaskID == task.id,
                                forceNote: noteTaskID == task.id,
                                onNoteDone: { if noteTaskID == task.id { noteTaskID = nil } })
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onKeyPress("j") { moveSelection(1); return .handled }
        .onKeyPress("k") { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.space) { toggleSelected(); return .handled }
        .onKeyPress("f") { verdictSelected(.fail); return .handled }
        .onKeyPress("b") { verdictSelected(.blocked); return .handled }
        .onKeyPress("n") {
            if let id = selectedTaskID ?? visibleTasks.first?.id { noteTaskID = id }
            return .handled
        }
    }

    private func moveSelection(_ step: Int) {
        let ids = visibleTasks.map(\.id)
        guard !ids.isEmpty else { return }
        let i = selectedTaskID.flatMap(ids.firstIndex(of:)) ?? (step > 0 ? -1 : 0)
        selectedTaskID = ids[min(max(i + step, 0), ids.count - 1)]
    }

    private func toggleSelected() {
        guard let id = selectedTaskID ?? visibleTasks.first?.id else { return }
        withAnimation(.smooth) { store.toggle(id, in: saved.id) }
    }

    private func verdictSelected(_ v: TaskVerdict) {
        guard let id = selectedTaskID ?? visibleTasks.first?.id else { return }
        let detail = v == .fail ? (saved.failed[id] ?? "") : (saved.blocked[id] ?? "")
        withAnimation(.smooth) { store.setVerdict(v, for: id, in: saved.id, detail: detail) }
    }

    private var visibleTasks: [TestPlan.Task] {
        var list: [TestPlan.Task]
        switch filter {
        case .all: list = plan.tasks
        case .todo: list = plan.tasks.filter { saved.verdict(of: $0.id) == .todo }
        case .failed: list = plan.tasks.filter { saved.verdict(of: $0.id) == .fail }
        case .blocked: list = plan.tasks.filter { saved.verdict(of: $0.id) == .blocked }
        }
        if p0Only { list = list.filter { $0.risk == "P0" } }
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

    // MARK: Export

    private enum ExportFormat { case markdown, html }

    /// Mac: save panel, then HTML opens in the browser. iOS: share sheet.
    private func export(_ format: ExportFormat) {
        let ctx = PlanExporter.Context(saved: saved, smokeOnly: smokeOnly)
        let text = format == .html ? PlanExporter.html(ctx) : PlanExporter.markdown(ctx)
        #if os(macOS)
        let panel = NSSavePanel()
        let ext = format == .html ? "html" : "md"
        panel.nameFieldStringValue = "\(plan.ticket.key) test plan.\(ext)"
        panel.allowedContentTypes = [format == .html ? .html : UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.message = format == .html ? "A styled, self-contained page you can open, share or print." : "Markdown you can paste into Jira, GitHub or docs."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            if format == .html { Platform.open(url) } else { Platform.reveal(url) }
        } catch {
            store.error = "Couldn't save: \(error.localizedDescription)"
        }
        #else
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(plan.ticket.key) test plan.\(format == .html ? "html" : "md")")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            sharing = SharedFile(url: url)
        } catch {
            store.error = "Couldn't export: \(error.localizedDescription)"
        }
        #endif
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

/// Quiet `⋯` menu in a section header: regenerate that section, plus any extras.
/// Ticks on items that survive a regenerate are kept.
private struct SectionMenu<Extra: View>: View {
    let saved: SavedPlan
    let section: PlanStore.RevisionSection
    @ViewBuilder var extra: Extra
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings

    init(saved: SavedPlan, section: PlanStore.RevisionSection, @ViewBuilder extra: () -> Extra = { EmptyView() }) {
        self.saved = saved
        self.section = section
        self.extra = extra()
    }

    private var busy: Bool { store.regenerating == saved.id + ":\(section.rawValue)" }

    var body: some View {
        if busy {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Regenerating…").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Menu {
                Button("Regenerate \(section.label.capitalized)", systemImage: "arrow.triangle.2.circlepath") {
                    store.regenerate(section: section, in: saved.id, settings: settings)
                }
                .disabled(store.regenerating != nil || store.chatBusyID != nil)
                extra
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Regenerate just the \(section.label) — ticks on surviving items are kept")
        }
    }
}

/// One quiet line under the summary: estimate, timer, verdict counts, tags and reminder.
private struct HeaderMeta: View {
    let saved: SavedPlan
    let editTags: () -> Void
    @Environment(PlanStore.self) private var store

    var body: some View {
        FlowLayout(spacing: 12) {
            if let mins = saved.plan.estimatedMinutes {
                Label("about \(mins) min", systemImage: "clock")
                    .help("Rough manual-testing estimate for the whole plan")
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let running = saved.timerRunningSince != nil
                Button {
                    withAnimation(.smooth) { store.toggleTimer(for: saved.id) }
                } label: {
                    Label(PlanStore.formatDuration(store.elapsedTesting(saved)),
                          systemImage: running ? "pause.circle.fill" : "stopwatch")
                        .monospacedDigit()
                        .foregroundStyle(running ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background { if running { Capsule().fill(.tint.opacity(0.12)) } }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help(running ? "Pause the testing timer" : "Time how long testing this plan takes")
            }
            if saved.failedCount > 0 {
                Label("\(saved.failedCount) failed", systemImage: "xmark.circle.fill").foregroundStyle(.red)
            }
            if saved.blockedCount > 0 {
                Label("\(saved.blockedCount) blocked", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
            if let due = saved.dueDate {
                Label(due.formatted(.relative(presentation: .named)), systemImage: saved.isOverdue ? "bell.badge.fill" : "bell")
                    .foregroundStyle(saved.isOverdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .help("Reminder: \(due.formatted(date: .abbreviated, time: .shortened))")
            }
            Button(action: editTags) {
                HStack(spacing: 6) {
                    if saved.tags.isEmpty {
                        Label("Add tags", systemImage: "tag")
                    } else {
                        Image(systemName: "tag")
                        ForEach(saved.tags.sorted(), id: \.self) { tag in
                            Text(tag)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(.quaternary, in: .capsule)
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Edit tags (⌘T)")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// Tags for one plan: current ones as removable chips, a field to add more,
/// and your other tags as one-click suggestions. Changes save immediately.
struct TagEditor: View {
    let saved: SavedPlan
    @Environment(PlanStore.self) private var store
    @State private var text = ""
    @FocusState private var focused: Bool

    private var current: SavedPlan { store.plans.first { $0.id == saved.id } ?? saved }
    private var suggestions: [String] { store.allTags.filter { !current.tags.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tags", systemImage: "tag").font(.headline)
            if !current.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(current.tags.sorted(), id: \.self) { tag in
                        Button { set(current.tags.subtracting([tag])) } label: {
                            HStack(spacing: 4) {
                                Text(tag)
                                Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                            }
                            .font(.callout)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .glassEffect(.regular.tint(Color.accentColor.opacity(0.2)).interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(tag)")
                    }
                }
            }
            TextField("Add a tag", text: $text, prompt: Text("sprint-12, needs-qa…"))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(add)
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your tags").font(.caption).foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(suggestions.prefix(16), id: \.self) { tag in
                            Button { set(current.tags.union([tag])) } label: {
                                Label(tag, systemImage: "plus")
                                    .font(.callout)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .glassEffect(.regular.interactive(), in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Text("Press Return to add. Filter by tag from the sidebar's filter menu.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { focused = true }
    }

    private func add() {
        let new = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !new.isEmpty else { return }
        set(current.tags.union(new))
        text = ""
    }

    private func set(_ tags: Set<String>) {
        withAnimation(.smooth) { store.setTags(tags, for: saved.id) }
    }
}

/// Removable pill showing an active task-list lens.
private struct LensChip: View {
    let label: String
    let icon: String
    let remove: () -> Void

    var body: some View {
        Button {
            withAnimation(.smooth, remove)
        } label: {
            HStack(spacing: 5) {
                Label(label, systemImage: icon)
                Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(Color.accentColor.opacity(0.2)).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .help("Turn off")
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
    @State private var dropTargeted = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// iPhone: area and risk chips sit under the title so it gets the width.
    private var compactRow: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }
    #if os(iOS)
    @State private var choosingEvidence = false
    @State private var showingPhotos = false
    @State private var showingCamera = false
    @State private var showingFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    #endif

    private var verdict: TaskVerdict { saved.verdict(of: task.id) }
    private var isDone: Bool { verdict == .pass }
    private var note: String? { saved.notes[task.id].flatMap { $0.isEmpty ? nil : $0 } }
    private var attachments: [String] { saved.evidence[task.id] ?? [] }

    /// Why the plan includes this task, from its risk, coverage and sources.
    private var whyExplanation: String {
        var s: String
        switch task.risk {
        case "P0": s = "P0: it guards the change's main blast radius, so run it first. "
        case "P1": s = "P1: worth running in a normal pass. "
        default: s = "P2: run it when time allows. "
        }
        s += task.covers.isEmpty
            ? "It isn't tied to one acceptance criterion; it covers the change generally. "
            : "It covers \(task.covers.joined(separator: ", ")). "
        s += task.sources.isEmpty
            ? "Source: \(task.ticketKey)."
            : "Drawn from " + task.sources.map { "\($0.ticketKey) (\($0.kind): \($0.ref))" }.joined(separator: ", ") + "."
        return s
    }

    /// After a re-run: green outline = new task, orange = changed.
    private var diffMark: Color? {
        guard let d = store.planDiff, d.planID == saved.id else { return nil }
        if d.addedTasks.contains(task.id) { return .green }
        if d.changedTasks.contains(task.id) { return .orange }
        return nil
    }

    private var stroke: Color {
        if dropTargeted { return .accentColor }
        return diffMark ?? (selected ? .accentColor : .clear)
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
            .help(verdict == .todo ? "Mark passed" : "Mark untested")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .strikethrough(isDone)
                        .foregroundStyle(isDone ? .secondary : .primary)
                    Spacer(minLength: 8)
                    if !compactRow {
                        if !task.area.isEmpty { Chip(text: task.area) }
                        RiskChip(risk: task.risk)
                    }
                    actionsMenu
                }
                .contentShape(.rect)
                .onTapGesture { withAnimation(.smooth) { expanded.toggle() } }
                if compactRow {
                    HStack(spacing: 6) {
                        if !task.area.isEmpty { Chip(text: task.area) }
                        RiskChip(risk: task.risk)
                    }
                }

                if verdict == .fail || verdict == .blocked { outcomeCallout }

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

                    if !task.testData.isEmpty { testData }
                }

                if editingNote {
                    noteEditor
                } else if let note {
                    Callout(icon: "note.text", tint: .yellow) {
                        Text(note).font(.callout).textSelection(.enabled)
                    } trailing: {
                        Button("Edit") { noteText = note; editingNote = true }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(attachments, id: \.self) { name in
                                EvidenceThumb(name: name, saved: saved, taskID: task.id)
                            }
                        }
                    }
                }

                if expanded && !isDone { metaLine }
            }
        }
        .padding(12)
        .background(.background.opacity(isDone ? 0.2 : 0.6), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(stroke, lineWidth: selected || dropTargeted ? 2 : 1.5)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            withAnimation(.smooth) { store.attachEvidence(files, planID: saved.id, taskID: task.id) }
            return true
        } isTargeted: { dropTargeted = $0 }
        .onChange(of: forceNote) { _, on in
            if on {
                noteText = saved.notes[task.id] ?? ""
                editingNote = true
            }
        }
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
        #if os(iOS)
        .confirmationDialog("Attach evidence", isPresented: $choosingEvidence, titleVisibility: .visible) {
            if CameraPicker.isAvailable {
                Button("Take Photo") { showingCamera = true }
            }
            Button("Photo Library") { showingPhotos = true }
            Button("Files") { showingFiles = true }
        }
        .photosPicker(isPresented: $showingPhotos, selection: $photoItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: photoItems) {
            let items = photoItems
            photoItems = []
            Task {
                for (i, item) in items.enumerated() {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    withAnimation(.smooth) {
                        _ = store.attachEvidence(data: data, name: "photo-\(Int(Date.now.timeIntervalSince1970))-\(i).\(ext)",
                                                 planID: saved.id, taskID: task.id)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { data in
                withAnimation(.smooth) {
                    _ = store.attachEvidence(data: data, name: "photo-\(Int(Date.now.timeIntervalSince1970)).jpg",
                                             planID: saved.id, taskID: task.id)
                }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                withAnimation(.smooth) { _ = store.attachEvidence(urls, planID: saved.id, taskID: task.id) }
            }
        }
        #endif
    }

    /// Everything you can do to a task, in one place.
    private var actionsMenu: some View {
        Menu {
            Button("Pass", systemImage: TaskVerdict.pass.icon) { set(.pass) }
            Button("Fail…", systemImage: TaskVerdict.fail.icon) { set(.fail) }
            Button("Blocked…", systemImage: TaskVerdict.blocked.icon) { set(.blocked) }
            if verdict != .todo {
                Button("Reset to To Do", systemImage: TaskVerdict.todo.icon) { set(.todo) }
            }
            Divider()
            Button(note == nil ? "Add Note" : "Edit Note", systemImage: "note.text") {
                noteText = note ?? ""
                editingNote = true
            }
            Button("Attach Evidence…", systemImage: "paperclip", action: attachFiles)
            if verdict == .fail {
                Button("Report Bug…", systemImage: "ant") { reportingBug = true }
            }
            Divider()
            Button("Why This Task?", systemImage: "questionmark.circle") { showingWhy = true }
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(.tertiary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Outcome, note, evidence — or drop files on the task")
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
            .presentationCompactAdaptation(.popover)
        }
    }

    private func set(_ v: TaskVerdict) {
        if v == .fail || v == .blocked {
            detailText = v == .fail ? (saved.failed[task.id] ?? "") : (saved.blocked[task.id] ?? "")
            verdictDraft = v
        } else {
            withAnimation(.smooth) { store.setVerdict(v, for: task.id, in: saved.id) }
        }
    }

    private var outcomeCallout: some View {
        let failed = verdict == .fail
        let detail = (failed ? saved.failed[task.id] : saved.blocked[task.id]) ?? ""
        return Callout(icon: failed ? "xmark.octagon.fill" : "exclamationmark.triangle.fill",
                       tint: failed ? .red : .orange) {
            Text(detail.isEmpty ? (failed ? "Failed — no detail yet" : "Blocked — no reason yet") : detail)
                .font(.callout)
                .foregroundStyle(detail.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
        } trailing: {
            if failed {
                Button("Report bug…") { reportingBug = true }
                    .buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(.red)
            }
        }
    }

    private var testData: some View {
        Callout(icon: "tablecells", tint: .blue) {
            Text(task.testData.joined(separator: "  ·  "))
                .font(.callout.monospaced())
                .textSelection(.enabled)
        } trailing: {
            Button {
                Platform.copy(task.testData.joined(separator: "\n"))
            } label: {
                Image(systemName: "doc.on.doc").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy sample data")
        }
    }

    private var noteEditor: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextField("Testing note…", text: $noteText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .lineLimit(2...5)
            HStack {
                Button("Cancel") { editingNote = false; onNoteDone() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                Button("Save note") {
                    store.setNote(noteText, for: task.id, in: saved.id)
                    editingNote = false
                    onNoteDone()
                }
                .buttonStyle(.glassProminent).controlSize(.small)
            }
        }
    }

    /// Covers · sources · estimate, on one caption line.
    private var metaLine: some View {
        let hasSources = task.sources.contains { $0.ticketKey != "derived" }
        return HStack(spacing: 6) {
            if !task.covers.isEmpty {
                Text("Covers " + task.covers.joined(separator: ", "))
            }
            if hasSources {
                if !task.covers.isEmpty { Text("·") }
                Text("From")
                ForEach(Array(task.sources.filter { $0.ticketKey != "derived" }.enumerated()), id: \.offset) { _, src in
                    TicketKeyButton(key: src.ticketKey, font: .caption.monospaced())
                        .help("\(src.kind): \(src.ref)")
                }
            }
            if let mins = task.estimateMin {
                if !task.covers.isEmpty || hasSources { Text("·") }
                Text("about \(mins) min").help("Rough manual-testing estimate")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    private func attachFiles() {
        #if os(iOS)
        choosingEvidence = true
        #else
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Attach screenshots or files to “\(task.title)”."
        guard panel.runModal() == .OK else { return }
        withAnimation(.smooth) { store.attachEvidence(panel.urls, planID: saved.id, taskID: task.id) }
        #endif
    }
}

/// Tinted inline box used for expected results, notes, test data and outcomes.
private struct Callout<Content: View, Trailing: View>: View {
    let icon: String
    let tint: Color
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    init(icon: String, tint: Color, @ViewBuilder content: () -> Content,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.icon = icon
        self.tint = tint
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            content.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 10))
    }
}

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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var hovering = false
    @State private var showingVague = false

    /// iPhone: the flag, gap-fill button and source sit under the text instead of beside it.
    private var stackMeta: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

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
            if stackMeta {
                VStack(alignment: .leading, spacing: 6) {
                    Text(criterion.text)
                        .strikethrough(isMet, color: .secondary)
                        .foregroundStyle(isMet ? .secondary : .primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) { meta }
                        .font(.caption)
                }
            } else {
                Text(criterion.text)
                    .strikethrough(isMet, color: .secondary)
                    .foregroundStyle(isMet ? .secondary : .primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                meta
            }
        }
        .animation(.smooth(duration: 0.15), value: hovering)
    }

    @ViewBuilder
    private var meta: some View {
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
                        Platform.copy(drafts.joined(separator: "\n"))
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
                .padding(16)
                .frame(width: 340)
                .presentationCompactAdaptation(.popover)
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
               let image = PlatformImage(data: data) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 8))
                    .onTapGesture {
                        Platform.open(store.evidenceDir(planID: saved.id, taskID: taskID).appending(path: name))
                    }
                    .help("Open \(name)")
            } else {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(.quaternary, in: .rect(cornerRadius: 8))
                    .onTapGesture {
                        Platform.open(store.evidenceDir(planID: saved.id, taskID: taskID).appending(path: name))
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
                    Platform.copy(report)
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


/// Follow-up chat over a finished plan. The composer lives in PlanView's
/// bottom inset so it stays put while the thread scrolls.
private struct ChatView: View {
    let saved: SavedPlan
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings

    private var busy: Bool { store.chatBusyID == saved.id || store.regenerating?.hasPrefix(saved.id) == true }

    private var suggestions: [String] {
        var out = ["What's the riskiest part of this change?", "Which tasks can I skip for a quick smoke test?"]
        if saved.mode == .qa { out.append("What should I check as an admin?") } else { out.append("What should I unit test instead?") }
        out.append("Add coverage for slow or offline networks")
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if saved.chat.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 30))
                        .foregroundStyle(.tint)
                    Text("Ask anything about this plan").font(.title3.weight(.semibold))
                    Text("Answers stay with the plan, and any useful one can update it — your ticks stay put.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    FlowLayout(spacing: 8) {
                        ForEach(suggestions, id: \.self) { q in
                            Button { store.sendChat(q, in: saved.id, settings: settings) } label: {
                                Text(q)
                                    .font(.callout)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .glassEffect(.regular.interactive(), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: 520)
                .padding(28)
                .frame(maxWidth: .infinity)
                .background(.background.opacity(0.55), in: .rect(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.separator.opacity(0.5)))
            }

            ForEach(saved.chat) { msg in
                if msg.role == .user {
                    HStack {
                        Spacer(minLength: 80)
                        Text(msg.text)
                            .font(.callout)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .glassEffect(.regular.tint(Color.accentColor.opacity(0.35)), in: .rect(cornerRadius: 18))
                    }
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        ChatAvatar()
                        VStack(alignment: .leading, spacing: 10) {
                            Text(msg.text)
                                .font(.callout)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if !msg.text.hasPrefix("Couldn't answer") {
                                Button("Update Plan from This", systemImage: "arrow.triangle.2.circlepath") {
                                    store.applyChatRevision(msg.text, in: saved.id, settings: settings)
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                                .disabled(busy)
                                .help("Folds this answer into the plan; ticks on surviving tasks are kept")
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.opacity(0.6), in: .rect(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.separator.opacity(0.4)))
                        Spacer(minLength: 40)
                    }
                }
            }

            if busy {
                HStack(spacing: 10) {
                    ChatAvatar()
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(store.chatBusyID == saved.id ? "Thinking…" : "Updating the plan…")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.background.opacity(0.6), in: .rect(cornerRadius: 18))
                }
            }
            Color.clear.frame(height: 1).id("chat-bottom")
        }
    }
}

private struct ChatAvatar: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Color.accentColor.gradient, in: .circle)
    }
}

/// Glass composer pinned under the chat thread, styled like the ticket bar.
private struct ChatComposer: View {
    let saved: SavedPlan
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var question = ""
    @FocusState private var focused: Bool

    private var busy: Bool { store.chatBusyID == saved.id || store.regenerating?.hasPrefix(saved.id) == true }
    private var canSend: Bool { !busy && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("", text: $question, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...5)
                .focused($focused)
                .onSubmit(ask)
                .background(alignment: .leading) {
                    if question.isEmpty {
                        Text("Ask a follow-up…").foregroundStyle(.tertiary).allowsHitTesting(false)
                    }
                }
                .padding(.vertical, 4)
            Button(action: ask) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Send (Return)")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .frame(maxWidth: 820)
        .padding(.horizontal, PageLayout.side)
        .padding(.bottom, 16)
        .onAppear { focused = true }
    }

    private func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        question = ""
        store.sendChat(q, in: saved.id, settings: settings)
    }
}

struct Chip: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular.tint(tint.opacity(0.2)), in: .capsule)
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
                FlowLayout(spacing: 10) {
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
            .lineLimit(1)
            .fixedSize()
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
        FlowLayout(spacing: 14) {
            Label(Platform.isMac ? "Click to mark met" : "Tap to mark met", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            Label("Tests to do", systemImage: "seal")
            Label("Tests done", systemImage: "checkmark.seal")
            if hasUncovered {
                Label("No test task covers it", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                    .help("Verify it manually, or ask for a task from the ⊕ next to it")
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

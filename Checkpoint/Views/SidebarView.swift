import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(PlanStore.self) private var store
    @Environment(TicketInspector.self) private var inspector
    @Environment(AppSettings.self) private var settings
    @State private var editingFolder: UUID?
    @State private var rootDropTargeted = false
    @State private var query = ""
    @State private var modeFilter: TestMode?
    @State private var trackerFilter: Tracker?
    @State private var progressFilter: PlanStore.SidebarProgressFilter = .all
    @State private var tagFilter: String?
    @State private var showArchived = false
    @State private var showingBatch = false
    @State private var editingSmartFolder: UUID?

    private var isFiltering: Bool {
        !query.isEmpty || modeFilter != nil || trackerFilter != nil || progressFilter != .all || tagFilter != nil
    }

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selection) {
            Label {
                Text("Dashboard")
            } icon: {
                Image(systemName: "chart.bar.fill").foregroundStyle(.indigo.gradient)
            }
            .tag(PlanStore.dashboardTag)
            if let key = store.runningKey {
                Section("Analyzing") {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(key).font(.body.monospaced())
                        ModeBadge(mode: store.runningMode, compact: true)
                    }
                }
            }
            if !store.pinnedPlans.isEmpty && !isFiltering {
                Section("Pinned") {
                    ForEach(store.pinnedPlans) { saved in
                        PlanRow(saved: saved)
                    }
                }
            }
            if store.batchRunning {
                Section("Batch") {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("\(store.batchLabel) · \(store.runningKey ?? "")")
                            .font(.body.monospaced())
                        Spacer(minLength: 4)
                        Button("Cancel", role: .destructive) { store.cancelBatch() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                    }
                }
            }
            if !store.smartFolders.isEmpty {
                Section {
                    ForEach(store.smartFolders) { smart in
                        SmartFolderRow(smart: smart, editingSmartFolder: $editingSmartFolder)
                    }
                } header: {
                    Text("Smart folders")
                }
            }
            Section {
                ForEach(visibleFolders(nil)) { folder in
                    FolderTreeRow(folder: folder, editingFolder: $editingFolder,
                                  query: query, modeFilter: modeFilter, trackerFilter: trackerFilter,
                                  progressFilter: progressFilter, tagFilter: tagFilter, showArchived: showArchived)
                }
                ForEach(visiblePlans(nil)) { saved in
                    PlanRow(saved: saved)
                }
                if isFiltering && visiblePlans(nil).isEmpty && visibleFolders(nil).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            } header: {
                HStack {
                    Text("Test plans")
                    Spacer()
                    filterMenu
                    Menu {
                        Button("New Folder", systemImage: "folder.badge.plus") {
                            let f = store.createFolder(in: nil)
                            editingFolder = f.id
                        }
                        Button("New Smart Folder", systemImage: "folder.badge.gearshape") {
                            let f = store.createSmartFolder()
                            editingSmartFolder = f.id
                        }
                        Divider()
                        Button("Plan Several Tickets…", systemImage: "square.stack.3d.down.right") {
                            showingBatch = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("New folder, smart folder, or plan a whole sprint")
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(rootDropTargeted ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 6))
                // Drop on the header to move things back to the top level.
                .onDrop(of: [.plainText], isTargeted: $rootDropTargeted) { providers in
                    loadDropPayloads(providers) { store.handleDrop($0, onto: nil) }
                }
            }
        }
        .glassScrollIndicator()
        .searchable(text: $query, prompt: "Search plans")
        .sheet(isPresented: $showingBatch) {
            BatchSheet()
                .environment(store)
                .environment(settings)
        }
        .overlay {
            if store.plans.isEmpty && store.folders.isEmpty && !store.isRunning {
                ContentUnavailableView("No plans yet", systemImage: "tray", description: Text("Analyze a ticket to start."))
            }
        }
    }

    /// Sort + filters in one header menu; the icon fills while a filter is on.
    private var filterMenu: some View {
        @Bindable var store = store
        return Menu {
            Picker("Sort By", selection: $store.sidebarSort) {
                ForEach(PlanStore.SidebarSort.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Ascending", isOn: $store.sidebarSortAscending)
            Divider()
            Picker("Mode", selection: $modeFilter) {
                Text("All Modes").tag(nil as TestMode?)
                ForEach(TestMode.allCases) { Text($0.label).tag($0 as TestMode?) }
            }
            Picker("Tracker", selection: $trackerFilter) {
                Text("All Trackers").tag(nil as Tracker?)
                ForEach(Tracker.allCases) { Text($0.label).tag($0 as Tracker?) }
            }
            Picker("Progress", selection: $progressFilter) {
                ForEach(PlanStore.SidebarProgressFilter.allCases) { Text($0.label).tag($0) }
            }
            if !store.allTags.isEmpty {
                Picker("Tag", selection: $tagFilter) {
                    Text("All Tags").tag(nil as String?)
                    ForEach(store.allTags, id: \.self) { Text($0).tag($0 as String?) }
                }
            }
            Toggle("Show Archived", isOn: $showArchived)
            if isFiltering {
                Divider()
                Button("Clear Filters", systemImage: "xmark.circle") {
                    query = ""; modeFilter = nil; trackerFilter = nil
                    progressFilter = .all; tagFilter = nil
                }
            }
        } label: {
            Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .foregroundStyle(isFiltering ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort and filter plans")
    }

    private func visiblePlans(_ folder: UUID?) -> [SavedPlan] {
        store.sortPlans(store.plans(in: folder).filter {
            store.matches($0, query: query, mode: modeFilter, tracker: trackerFilter,
                          progress: progressFilter, tag: tagFilter, showArchived: showArchived)
        })
    }

    private func visibleFolders(_ parent: UUID?) -> [PlanFolder] {
        store.childFolders(of: parent).filter { folder in
            if !isFiltering { return true }
            // Keep a folder if it or any descendant matches.
            if visiblePlans(folder.id).count > 0 { return true }
            return visibleFolders(folder.id).count > 0
        }
    }
}

// MARK: - Folder tree

/// One folder and, when expanded, its subfolders and plans — recursing to any depth.
private struct FolderTreeRow: View {
    let folder: PlanFolder
    @Binding var editingFolder: UUID?
    var query = ""
    var modeFilter: TestMode?
    var trackerFilter: Tracker?
    var progressFilter: PlanStore.SidebarProgressFilter = .all
    var tagFilter: String?
    var showArchived = false
    @Environment(PlanStore.self) private var store
    @State private var dropTargeted = false

    private var expanded: Binding<Bool> {
        Binding(
            get: { store.expandedFolders.contains(folder.id) },
            set: { open in
                if open { store.expandedFolders.insert(folder.id) } else { store.expandedFolders.remove(folder.id) }
            }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: expanded) {
            ForEach(visibleChildren) { child in
                FolderTreeRow(folder: child, editingFolder: $editingFolder,
                              query: query, modeFilter: modeFilter, trackerFilter: trackerFilter,
                              progressFilter: progressFilter, tagFilter: tagFilter, showArchived: showArchived)
            }
            ForEach(visiblePlans) { saved in
                PlanRow(saved: saved)
            }
        } label: {
            label
        }
    }

    private var visiblePlans: [SavedPlan] {
        store.sortPlans(store.plans(in: folder.id).filter {
            store.matches($0, query: query, mode: modeFilter, tracker: trackerFilter,
                          progress: progressFilter, tag: tagFilter, showArchived: showArchived)
        })
    }

    private var visibleChildren: [PlanFolder] {
        store.childFolders(of: folder.id).filter { child in
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty && modeFilter == nil && trackerFilter == nil && progressFilter == .all && tagFilter == nil { return true }
            if visiblePlansInTree(child) { return true }
            return false
        }
    }

    private func visiblePlansInTree(_ folder: PlanFolder) -> Bool {
        if !store.sortPlans(store.plans(in: folder.id).filter {
            store.matches($0, query: query, mode: modeFilter, tracker: trackerFilter,
                          progress: progressFilter, tag: tagFilter, showArchived: showArchived)
        }).isEmpty { return true }
        return store.childFolders(of: folder.id).contains { visiblePlansInTree($0) }
    }

    private var label: some View {
        let all = store.allPlans(under: folder.id)
        let done = all.reduce(0) { $0 + $1.tasksDone }
        let total = all.reduce(0) { $0 + $1.plan.tasks.count }
        return HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(folder.color.color.gradient)
            Text(folder.name).lineLimit(1)
            Spacer(minLength: 4)
            if total > 0 {
                Text("\(done)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(done == total ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            }
        }
        .padding(.vertical, 1)
        .contentShape(.rect)
        .background(dropTargeted ? folder.color.color.opacity(0.22) : .clear, in: .rect(cornerRadius: 6))
        .tag(PlanStore.folderTag(folder.id))
        // `.itemProvider` (not `.draggable`): List routes drags of *selected* rows through
        // its own selection drag, which ignores `.draggable` on the row content.
        .itemProvider { NSItemProvider(object: "folder:\(folder.id.uuidString)" as NSString) }
        .onDrop(of: [.plainText], isTargeted: $dropTargeted) { providers in
            loadDropPayloads(providers) { store.handleDrop($0, onto: folder.id) }
        }
        .popover(isPresented: Binding(
            get: { editingFolder == folder.id },
            set: { if !$0 { editingFolder = nil } }
        ), arrowEdge: .trailing) {
            FolderEditor(folder: folder) { editingFolder = nil }
        }
        .contextMenu {
            Button("New Subfolder", systemImage: "folder.badge.plus") {
                let f = store.createFolder(in: folder.id, color: folder.color)
                editingFolder = f.id
            }
            Button("Edit Folder…", systemImage: "pencil") { editingFolder = folder.id }
            MoveMenu(title: "Move Folder To", excluding: folder.id) { store.moveFolder(folder.id, to: $0) }
            Divider()
            Button("Delete Folder", systemImage: "trash", role: .destructive) { store.deleteFolder(folder.id) }
        }
    }
}

/// Name + colour editor shown in a popover.
private struct FolderEditor: View {
    let folder: PlanFolder
    let dismiss: () -> Void
    @Environment(PlanStore.self) private var store
    @State private var name = ""
    @State private var color: FolderColor = .indigo
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Folder").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
            VStack(alignment: .leading, spacing: 8) {
                Text("Colour").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(FolderColor.allCases) { c in
                        Button { color = c } label: {
                            Circle()
                                .fill(c.color.gradient)
                                .frame(width: 20, height: 20)
                                .overlay {
                                    if c == color {
                                        Circle().strokeBorder(.white, lineWidth: 2).padding(2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(c.rawValue.capitalized)
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Cancel", action: dismiss)
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("Save Folder", action: save)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .frame(width: 320)
        .onAppear {
            name = folder.name
            color = folder.color
            focused = true
        }
    }

    private func save() {
        store.updateFolder(folder.id, name: name, color: color)
        dismiss()
    }
}

/// Hierarchical "Move to" menu: Top Level, then every folder as nested submenus.
struct MoveMenu: View {
    let title: String
    var excluding: UUID? = nil
    let move: (UUID?) -> Void

    var body: some View {
        Menu(title) {
            Button("Top Level", systemImage: "tray") { move(nil) }
            Divider()
            MoveMenuItems(parent: nil, excluding: excluding, move: move)
        }
    }
}

private struct MoveMenuItems: View {
    let parent: UUID?
    let excluding: UUID?
    let move: (UUID?) -> Void
    @Environment(PlanStore.self) private var store

    var body: some View {
        ForEach(store.childFolders(of: parent).filter { $0.id != excluding }) { f in
            let children = store.childFolders(of: f.id).filter { $0.id != excluding }
            if children.isEmpty {
                Button(f.name, systemImage: "folder") { move(f.id) }
            } else {
                Menu {
                    Button("Move Here", systemImage: "arrow.down.to.line") { move(f.id) }
                    Divider()
                    MoveMenuItems(parent: f.id, excluding: excluding, move: move)
                } label: {
                    Label(f.name, systemImage: "folder")
                }
            }
        }
    }
}

// MARK: - Smart folders (IDEA-101)

private struct SmartFolderRow: View {
    let smart: SmartFolder
    @Binding var editingSmartFolder: UUID?
    @Environment(PlanStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill.badge.gearshape")
                .foregroundStyle(.teal.gradient)
            Text(smart.name).lineLimit(1)
            Spacer(minLength: 4)
            let n = store.plans(matching: smart).count
            if n > 0 {
                Text("\(n)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
        .contentShape(.rect)
        .tag(PlanStore.smartFolderTag(smart.id))
        .popover(isPresented: Binding(
            get: { editingSmartFolder == smart.id },
            set: { if !$0 { editingSmartFolder = nil } }
        ), arrowEdge: .trailing) {
            SmartFolderEditor(smart: smart) { editingSmartFolder = nil }
        }
        .contextMenu {
            Button("Edit Smart Folder…", systemImage: "pencil") { editingSmartFolder = smart.id }
            Button("Convert to Static Folder", systemImage: "folder") { store.convertSmartFolder(smart.id) }
            Divider()
            Button("Delete Smart Folder", systemImage: "trash", role: .destructive) { store.deleteSmartFolder(smart.id) }
        }
    }
}

/// Rule editor: kind + value with suggestions from known ticket metadata.
private struct SmartFolderEditor: View {
    let smart: SmartFolder
    let dismiss: () -> Void
    @Environment(PlanStore.self) private var store
    @State private var name = ""
    @State private var kind: SmartFolder.Kind = .label
    @State private var value = ""
    @FocusState private var focused: Bool

    private var suggestions: [String] {
        switch kind {
        case .label: store.allLabels
        case .component: store.allComponents
        case .fixVersion: store.allFixVersions
        case .epic: store.plans.map { $0.plan.ticket.key }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Smart folder").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
            Picker("Rule", selection: $kind) {
                ForEach(SmartFolder.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField(kind.valuePrompt, text: $value)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .onSubmit(save)
            if !suggestions.isEmpty {
                Text("Known values: \(suggestions.prefix(8).joined(separator: ", "))\(suggestions.count > 8 ? "…" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Membership updates live as new plans arrive. Old plans have no ticket metadata — re-run them to fill it in.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Cancel", action: dismiss)
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("Save", action: save)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .frame(width: 340)
        .onAppear(perform: {
            name = smart.name
            kind = smart.kind
            value = smart.value
            focused = true
        })
    }

    private func save() {
        store.updateSmartFolder(smart.id, name: name, kind: kind, value: value)
        dismiss()
    }
}

/// Contents of a smart folder: the live rule, rolled-up progress and matching plans.
struct SmartFolderOverview: View {
    let smart: SmartFolder
    @Environment(PlanStore.self) private var store
    @State private var editing = false

    var body: some View {
        let plans = store.plans(matching: smart)
        let tasksDone = plans.reduce(0) { $0 + $1.tasksDone }
        let tasksTotal = plans.reduce(0) { $0 + $1.plan.tasks.count }
        let acMet = plans.reduce(0) { $0 + $1.criteriaMet }
        let acTotal = plans.reduce(0) { $0 + $1.plan.acceptanceCriteria.count }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text(smart.name).font(.largeTitle.weight(.semibold))
                        } icon: {
                            Image(systemName: "folder.fill.badge.gearshape").foregroundStyle(.teal.gradient)
                        }
                        Text("\(smart.kind.label) is “\(smart.value)” · \(plans.count) plan\(plans.count == 1 ? "" : "s") · updates live")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("Edit Rule…", systemImage: "slider.horizontal.3") { editing = true }
                            Button("Convert to Folder", systemImage: "folder") { store.convertSmartFolder(smart.id) }
                                .help("Freeze the current matches into a normal folder")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 16) {
                        MetricRing(value: tasksTotal == 0 ? 0 : Double(tasksDone) / Double(tasksTotal),
                                   label: "tested", text: "\(tasksDone)/\(tasksTotal)")
                        MetricRing(value: acTotal == 0 ? 0 : Double(acMet) / Double(acTotal),
                                   label: "AC met", text: "\(acMet)/\(acTotal)", tint: .teal)
                    }
                }
                .padding(24)
                .glassEffect(.regular.tint(.teal.opacity(0.08)), in: .rect(cornerRadius: 28))

                VStack(alignment: .leading, spacing: 10) {
                    Label("Plans", systemImage: "checklist").font(.headline)
                    if plans.isEmpty {
                        Text("Plans whose ticket has \(smart.kind.label.lowercased()) “\(smart.value)” appear here. Plans made before ticket metadata was saved need a re-run.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(plans) { saved in
                        Button { store.selection = saved.id } label: {
                            SidebarRow(saved: saved)
                                .padding(12)
                                .background(.background.opacity(0.55), in: .rect(cornerRadius: 14))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 92)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .glassScrollIndicator()
        .sheet(isPresented: $editing) {
            SmartFolderEditor(smart: smart) { editing = false }
                .environment(store)
        }
    }
}

// MARK: - Plan rows

private struct PlanRow: View {
    let saved: SavedPlan
    @Environment(PlanStore.self) private var store
    @Environment(TicketInspector.self) private var inspector
    @Environment(AppSettings.self) private var settings

    var body: some View {
        SidebarRow(saved: saved)
            .tag(saved.id)
            .itemProvider { NSItemProvider(object: "plan:\(saved.id)" as NSString) }
            .contextMenu {
                Button("Show ticket details", systemImage: "sidebar.right") {
                    inspector.open(saved.plan.ticket.key, tracker: saved.tracker)
                }
                Button("Run in \(saved.mode == .dev ? "QA" : "Dev") mode", systemImage: TestMode.qa.icon) {
                    store.analyze(saved.plan.ticket.key, mode: saved.mode == .dev ? .qa : .dev,
                                  tracker: saved.tracker, settings: settings)
                }
                Button("Re-run", systemImage: "arrow.clockwise") {
                    if saved.preset == "quick" {
                        let q = PlanStore.quickOverrides(settings: settings)
                        store.analyze(saved.plan.ticket.key, mode: saved.mode, tracker: saved.tracker,
                                      modelOverride: q.model, effortOverride: q.effort, settings: settings)
                    } else {
                        store.analyze(saved.plan.ticket.key, mode: saved.mode, tracker: saved.tracker, settings: settings)
                    }
                }
                if let url = URL(string: saved.plan.ticket.url) {
                    Link("Open in \(saved.tracker.label)", destination: url)
                }
                MoveMenu(title: "Move To") { store.movePlan(saved.id, to: $0) }
                Divider()
                Button(saved.pinned ? "Unpin" : "Pin", systemImage: saved.pinned ? "pin.slash" : "pin") {
                    store.togglePin(saved.id)
                }
                Button(saved.archived ? "Restore from archive" : "Archive", systemImage: saved.archived ? "tray.and.arrow.down" : "archivebox") {
                    store.toggleArchive(saved.id)
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { store.delete(saved.id) }
            }
    }
}

struct SidebarRow: View {
    let saved: SavedPlan

    var body: some View {
        HStack(spacing: 10) {
            ProgressRing(value: saved.progress, lineWidth: 3)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if saved.pinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                    }
                    Text(saved.plan.ticket.key)
                        .font(.body.monospaced().weight(.medium))
                    ModeBadge(mode: saved.mode, compact: true)
                    if saved.tracker == .linear {
                        Image(systemName: Tracker.linear.icon).font(.caption2).foregroundStyle(.purple)
                            .help("Linear")
                    }
                    if saved.isOverdue {
                        Image(systemName: "bell.badge.fill").font(.caption2).foregroundStyle(.red)
                            .help("Overdue")
                    } else if saved.dueDate != nil {
                        Image(systemName: "bell").font(.caption2).foregroundStyle(.tertiary)
                            .help("Reminder set")
                    }
                }
                Text(saved.plan.ticket.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            CriteriaCount(saved: saved)
        }
        .padding(.vertical, 2)
        .opacity(saved.archived ? 0.55 : 1)
    }
}

/// "seal 2/3" — acceptance criteria met.
struct CriteriaCount: View {
    let saved: SavedPlan

    var body: some View {
        let total = saved.plan.acceptanceCriteria.count
        if total > 0 {
            let all = saved.criteriaMet == total
            HStack(spacing: 2) {
                Image(systemName: all ? "checkmark.seal.fill" : "seal")
                Text("\(saved.criteriaMet)/\(total)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(all ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
            .help("Acceptance criteria met")
        }
    }
}

// MARK: - Shared

struct ProgressRing: View {
    let value: Double
    var lineWidth: CGFloat = 6
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: value)
                .stroke(value >= 1 ? Color.green : tint,
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

/// Reads the "plan:<id>" / "folder:<uuid>" strings from a sidebar drop and hands them to `apply` on the main actor.
func loadDropPayloads(_ providers: [NSItemProvider], apply: @escaping @MainActor ([String]) -> Void) -> Bool {
    let relevant = providers.filter { $0.canLoadObject(ofClass: NSString.self) }
    guard !relevant.isEmpty else { return false }
    Task {
        var items: [String] = []
        for provider in relevant {
            let value: String? = await withCheckedContinuation { cont in
                _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                    cont.resume(returning: (obj as? NSString) as String?)
                }
            }
            if let value, value.hasPrefix("plan:") || value.hasPrefix("folder:") { items.append(value) }
        }
        if !items.isEmpty { await MainActor.run { apply(items) } }
    }
    return true
}

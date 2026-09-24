import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(PlanStore.self) private var store
    @Environment(TicketInspector.self) private var inspector
    @Environment(AppSettings.self) private var settings
    @State private var editingFolder: UUID?
    @State private var rootDropTargeted = false

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
            Section {
                ForEach(store.childFolders(of: nil)) { folder in
                    FolderTreeRow(folder: folder, editingFolder: $editingFolder)
                }
                ForEach(store.plans(in: nil)) { saved in
                    PlanRow(saved: saved)
                }
            } header: {
                HStack {
                    Text("Test plans")
                    Spacer()
                    Button {
                        let f = store.createFolder(in: nil)
                        editingFolder = f.id
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .help("New folder")
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
        .overlay {
            if store.plans.isEmpty && store.folders.isEmpty && !store.isRunning {
                ContentUnavailableView("No plans yet", systemImage: "tray", description: Text("Analyze a ticket to start."))
            }
        }
    }
}

// MARK: - Folder tree

/// One folder and, when expanded, its subfolders and plans — recursing to any depth.
private struct FolderTreeRow: View {
    let folder: PlanFolder
    @Binding var editingFolder: UUID?
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
            ForEach(store.childFolders(of: folder.id)) { child in
                FolderTreeRow(folder: child, editingFolder: $editingFolder)
            }
            ForEach(store.plans(in: folder.id)) { saved in
                PlanRow(saved: saved)
            }
        } label: {
            label
        }
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
                    store.analyze(saved.plan.ticket.key, mode: saved.mode, tracker: saved.tracker, settings: settings)
                }
                if let url = URL(string: saved.plan.ticket.url) {
                    Link("Open in \(saved.tracker.label)", destination: url)
                }
                MoveMenu(title: "Move To") { store.movePlan(saved.id, to: $0) }
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
                    Text(saved.plan.ticket.key)
                        .font(.body.monospaced().weight(.medium))
                    ModeBadge(mode: saved.mode, compact: true)
                    if saved.tracker == .linear {
                        Image(systemName: Tracker.linear.icon).font(.caption2).foregroundStyle(.purple)
                            .help("Linear")
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

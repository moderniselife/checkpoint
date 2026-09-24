import Foundation
import Observation

nonisolated struct SavedPlan: Codable, Sendable, Identifiable, Hashable {
    /// Dev and QA plans for the same ticket are kept side by side.
    var id: String { Self.id(plan.ticket.key, mode, tracker) }
    var plan: TestPlan
    var mode: TestMode
    var tracker: Tracker
    var createdAt: Date
    var done: Set<String>
    /// Acceptance criteria the tester has marked as met.
    var metCriteria: Set<String> = []
    var folderID: UUID?

    /// Jira ids stay "KEY:mode" so plans saved before Linear support keep their identity.
    static func id(_ key: String, _ mode: TestMode, _ tracker: Tracker) -> String {
        (tracker == .jira ? "" : "linear:") + "\(key):\(mode.rawValue)"
    }

    init(plan: TestPlan, mode: TestMode, tracker: Tracker, createdAt: Date, done: Set<String>) {
        self.plan = plan
        self.mode = mode
        self.tracker = tracker
        self.createdAt = createdAt
        self.done = done
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decode(TestPlan.self, forKey: .plan)
        // Plans saved before modes existed were dev plans.
        mode = try c.decodeIfPresent(TestMode.self, forKey: .mode) ?? .dev
        tracker = try c.decodeIfPresent(Tracker.self, forKey: .tracker) ?? .jira
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        done = try c.decode(Set<String>.self, forKey: .done)
        metCriteria = try c.decodeIfPresent(Set<String>.self, forKey: .metCriteria) ?? []
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
    }

    var tasksDone: Int { plan.tasks.filter { done.contains($0.id) }.count }
    var criteriaMet: Int { plan.acceptanceCriteria.filter { metCriteria.contains($0.id) }.count }

    var progress: Double {
        plan.tasks.isEmpty ? 0 : Double(tasksDone) / Double(plan.tasks.count)
    }

    var criteriaProgress: Double {
        plan.acceptanceCriteria.isEmpty ? 0 : Double(criteriaMet) / Double(plan.acceptanceCriteria.count)
    }
}

struct FeedItem: Identifiable, Hashable {
    enum Kind { case status, thinking, tool }
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
}

@Observable
final class PlanStore {
    private(set) var plans: [SavedPlan] = []
    private(set) var folders: [PlanFolder] = []
    /// A plan id, or `folder:<uuid>` for a folder overview.
    var selection: String?
    var expandedFolders: Set<UUID> = [] {
        didSet { UserDefaults.standard.set(expandedFolders.map(\.uuidString), forKey: "expandedFolders") }
    }

    private(set) var runningKey: String?
    private(set) var feed: [FeedItem] = []
    var error: String?
    private var task: Task<Void, Never>?

    private let fileURL: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Checkpoint", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "plans.json")
    }()

    private var foldersURL: URL { fileURL.deletingLastPathComponent().appending(path: "folders.json") }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([SavedPlan].self, from: data) {
            plans = saved
        }
        if let data = try? Data(contentsOf: foldersURL),
           let saved = try? JSONDecoder().decode([PlanFolder].self, from: data) {
            folders = saved
        }
        expandedFolders = Set((UserDefaults.standard.stringArray(forKey: "expandedFolders") ?? []).compactMap(UUID.init))
    }

    var selected: SavedPlan? { plans.first { $0.id == selection } }

    // MARK: - Folders

    static func folderTag(_ id: UUID) -> String { "folder:\(id.uuidString)" }

    var selectedFolder: PlanFolder? {
        guard let sel = selection, sel.hasPrefix("folder:"), let id = UUID(uuidString: String(sel.dropFirst(7))) else { return nil }
        return folders.first { $0.id == id }
    }

    func folder(_ id: UUID?) -> PlanFolder? { id.flatMap { id in folders.first { $0.id == id } } }

    func childFolders(of parent: UUID?) -> [PlanFolder] {
        folders.filter { $0.parentID == parent }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func plans(in folder: UUID?) -> [SavedPlan] { plans.filter { $0.folderID == folder } }

    /// Plans in a folder and all of its descendants.
    func allPlans(under folder: UUID) -> [SavedPlan] {
        plans(in: folder) + childFolders(of: folder).flatMap { allPlans(under: $0.id) }
    }

    /// Breadcrumb from the root down to `id`.
    func path(to id: UUID?) -> [PlanFolder] {
        var out: [PlanFolder] = []
        var cursor = folder(id)
        while let f = cursor { out.insert(f, at: 0); cursor = folder(f.parentID) }
        return out
    }

    private func isDescendant(_ candidate: UUID?, of ancestor: UUID) -> Bool {
        var cursor = candidate
        while let c = cursor {
            if c == ancestor { return true }
            cursor = folder(c)?.parentID
        }
        return false
    }

    @discardableResult
    func createFolder(named name: String = "New Folder", in parent: UUID?, color: FolderColor = .indigo) -> PlanFolder {
        let f = PlanFolder(name: name, color: color, parentID: parent)
        folders.append(f)
        if let parent { expandedFolders.insert(parent) }
        saveFolders()
        return f
    }

    func updateFolder(_ id: UUID, name: String, color: FolderColor) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : name
        folders[i].color = color
        saveFolders()
    }

    /// Deletes a folder; its plans and subfolders move up to its parent.
    func deleteFolder(_ id: UUID) {
        guard let f = folder(id) else { return }
        for i in folders.indices where folders[i].parentID == id { folders[i].parentID = f.parentID }
        for i in plans.indices where plans[i].folderID == id { plans[i].folderID = f.parentID }
        folders.removeAll { $0.id == id }
        if selection == Self.folderTag(id) { selection = nil }
        saveFolders()
        save()
    }

    /// Moves a folder under another (nil = top level). Refuses moves into its own subtree.
    func moveFolder(_ id: UUID, to parent: UUID?) {
        guard id != parent, !isDescendant(parent, of: id),
              let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].parentID = parent
        if let parent { expandedFolders.insert(parent) }
        saveFolders()
    }

    func movePlan(_ planID: String, to folder: UUID?) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        plans[i].folderID = folder
        if let folder { expandedFolders.insert(folder) }
        save()
    }

    /// Handles a sidebar drop payload ("plan:<id>" or "folder:<uuid>") onto a folder.
    func handleDrop(_ items: [String], onto folder: UUID?) -> Bool {
        var moved = false
        for item in items {
            if item.hasPrefix("folder:"), let id = UUID(uuidString: String(item.dropFirst(7))) {
                moveFolder(id, to: folder); moved = true
            } else if item.hasPrefix("plan:") {
                movePlan(String(item.dropFirst(5)), to: folder); moved = true
            }
        }
        return moved
    }

    private func saveFolders() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        try? data.write(to: foldersURL, options: .atomic)
    }
    var isRunning: Bool { runningKey != nil }

    /// Accepts "PROJ-123", "proj-123" or a pasted Jira URL.
    static func extractKey(_ input: String) -> String? {
        let upper = input.uppercased()
        guard let match = upper.firstMatch(of: /[A-Z][A-Z0-9]+-\d+/) else { return nil }
        return String(match.output)
    }

    private(set) var runningMode: TestMode = .dev
    private(set) var runningTracker: Tracker = .jira

    /// `mode`/`tracker` default to the toggle and link detection; re-runs pass the plan's own.
    func analyze(_ input: String, mode: TestMode? = nil, tracker: Tracker? = nil, settings: AppSettings) {
        let mode = mode ?? settings.mode
        let tracker = tracker ?? settings.tracker(for: input)
        guard let key = Self.extractKey(input) else {
            error = "That doesn't look like a Jira key (e.g. PROJ-1234)."
            return
        }
        guard !settings.anthropicKey.isEmpty else {
            error = "Add your Anthropic API key in Settings (⌘,)."
            return
        }
        guard settings.isConfigured(tracker) else {
            error = "Connect \(tracker.label) in Settings (⌘,) to analyze \(tracker.label) issues."
            return
        }
        task?.cancel()
        error = nil
        feed = []
        runningKey = key
        runningMode = mode
        runningTracker = tracker
        // New plans land in the folder you're looking at.
        let targetFolder = selectedFolder?.id ?? selected?.folderID
        selection = nil

        let generator = PlanGenerator(
            claude: ClaudeClient(apiKey: settings.anthropicKey),
            mcp: settings.makeMCPClient(for: tracker),
            model: settings.model,
            effort: settings.effort,
            site: settings.siteHost,
            mode: mode,
            tracker: tracker,
            environment: settings.qaEnvironment
        )
        task = Task {
            do {
                let plan = try await generator.run(ticketKey: key) { event in
                    await MainActor.run { self.record(event) }
                }
                let id = SavedPlan.id(plan.ticket.key, mode, tracker)
                let previous = plans.first { $0.id == id }
                // Keep ticks for tasks that survived a re-run.
                let kept = previous?.done.intersection(plan.tasks.map(\.id)) ?? []
                var saved = SavedPlan(plan: plan, mode: mode, tracker: tracker, createdAt: .now, done: kept)
                saved.metCriteria = previous?.metCriteria.intersection(plan.acceptanceCriteria.map(\.id)) ?? []
                saved.folderID = previous?.folderID ?? targetFolder
                plans.removeAll { $0.id == id }
                plans.insert(saved, at: 0)
                save()
                selection = id
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            runningKey = nil
        }
    }

    func cancel() {
        task?.cancel()
        runningKey = nil
    }

    func toggle(_ taskID: String, in planID: String) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        if plans[i].done.contains(taskID) { plans[i].done.remove(taskID) } else { plans[i].done.insert(taskID) }
        save()
    }

    func toggleCriterion(_ criterionID: String, in planID: String) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        if plans[i].metCriteria.contains(criterionID) { plans[i].metCriteria.remove(criterionID) }
        else { plans[i].metCriteria.insert(criterionID) }
        save()
    }

    func delete(_ planID: String) {
        plans.removeAll { $0.id == planID }
        if selection == planID { selection = nil }
        save()
    }

    private func record(_ event: PlanGenerator.Event) {
        switch event {
        case .status(let s):
            feed.append(FeedItem(kind: .status, title: s, detail: ""))
        case .thinking(let t):
            let firstLine = t.split(separator: "\n").first.map(String.init) ?? t
            feed.append(FeedItem(kind: .thinking, title: firstLine, detail: t))
        case .toolCall(let name, let detail):
            feed.append(FeedItem(kind: .tool, title: Self.friendly(name), detail: detail))
        }
    }

    private static func friendly(_ tool: String) -> String {
        switch tool {
        case "getJiraIssue": "Opened ticket"
        case "searchJiraIssuesUsingJql": "Searched Jira"
        case "getJiraIssueRemoteIssueLinks": "Checked remote links"
        case "getConfluencePage": "Read Confluence page"
        case "searchConfluenceUsingCql", "search": "Searched Confluence"
        case "getAccessibleAtlassianResources": "Found your Atlassian site"
        case "fetch": "Fetched"
        case "get_issue": "Opened issue"
        case "list_comments": "Read comments"
        case "list_issues", "search_issues": "Searched issues"
        case "get_project": "Read project"
        case "get_document", "list_documents": "Read document"
        case "search_documentation": "Searched Linear docs"
        default: tool
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(plans) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

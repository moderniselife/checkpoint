import Foundation
import Observation

nonisolated struct SavedPlan: Codable, Sendable, Identifiable, Hashable {    /// Dev and QA plans for the same ticket are kept side by side.
    var id: String { Self.id(plan.ticket.key, mode, tracker) }
    var plan: TestPlan
    var mode: TestMode
    var tracker: Tracker
    var createdAt: Date
    var done: Set<String>
    /// Failed tasks: task id → what actually happened (IDEA-020).
    var failed: [String: String] = [:]
    /// Blocked tasks: task id → why it can't be tested (IDEA-020).
    var blocked: [String: String] = [:]
    /// Acceptance criteria the tester has marked as met.
    var metCriteria: Set<String> = []
    var folderID: UUID?
    /// Everything the research step did, kept so it can be reviewed later.
    var research: [FeedItem] = []
    var researchDuration: TimeInterval?
    /// Organisation (IDEA-102/103/104/110): freeform tags, pinned, archived, due date.
    var tags: Set<String> = []
    var pinned: Bool = false
    var archived: Bool = false
    var dueDate: Date?
    /// Last user-visible change (created, ticked, re-run, moved). Used for sort + dashboard.
    var updatedAt: Date
    /// Quick ("quick") vs full ("deep") preset used for this run (IDEA-082).
    var preset: String = "deep"
    /// Follow-up chat thread (IDEA-083).
    var chat: [ChatMsg] = []
    /// Plan shape used for this run (IDEA-010), "auto" unless overridden.
    var template: String = "auto"
    /// Token usage + rough cost for the run that produced this plan (IDEA-080).
    var usage: LLMUsage? = nil
    /// Provider/model that produced the usage above.
    var usageProvider: String = "anthropic"
    var usageModel: String = ""
    /// Freeform notes per task (IDEA-021).
    var notes: [String: String] = [:]
    /// Evidence attachments per task: filenames under evidence/<planID>/<taskID>/ (IDEA-022).
    var evidence: [String: [String]] = [:]
    /// Manual testing timer (IDEA-025): accumulated seconds + start mark when running.
    var testingSeconds: TimeInterval = 0
    var timerRunningSince: Date? = nil

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
        self.updatedAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decode(TestPlan.self, forKey: .plan)
        // Plans saved before modes existed were dev plans.
        mode = try c.decodeIfPresent(TestMode.self, forKey: .mode) ?? .dev
        tracker = try c.decodeIfPresent(Tracker.self, forKey: .tracker) ?? .jira
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        done = try c.decode(Set<String>.self, forKey: .done)
        failed = try c.decodeIfPresent([String: String].self, forKey: .failed) ?? [:]
        blocked = try c.decodeIfPresent([String: String].self, forKey: .blocked) ?? [:]
        metCriteria = try c.decodeIfPresent(Set<String>.self, forKey: .metCriteria) ?? []
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        research = try c.decodeIfPresent([FeedItem].self, forKey: .research) ?? []
        researchDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .researchDuration)
        tags = try c.decodeIfPresent(Set<String>.self, forKey: .tags) ?? []
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        template = try c.decodeIfPresent(String.self, forKey: .template) ?? "auto"
        usage = try c.decodeIfPresent(LLMUsage.self, forKey: .usage)
        usageProvider = try c.decodeIfPresent(String.self, forKey: .usageProvider) ?? "anthropic"
        usageModel = try c.decodeIfPresent(String.self, forKey: .usageModel) ?? ""
        preset = try c.decodeIfPresent(String.self, forKey: .preset) ?? "deep"
        chat = try c.decodeIfPresent([ChatMsg].self, forKey: .chat) ?? []
        notes = try c.decodeIfPresent([String: String].self, forKey: .notes) ?? [:]
        evidence = try c.decodeIfPresent([String: [String]].self, forKey: .evidence) ?? [:]
        testingSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .testingSeconds) ?? 0
        timerRunningSince = try c.decodeIfPresent(Date.self, forKey: .timerRunningSince)
    }

    var isOverdue: Bool { dueDate.map { $0 < .now && progress < 1 } ?? false }

    var tasksDone: Int { plan.tasks.filter { done.contains($0.id) }.count }
    var criteriaMet: Int { plan.acceptanceCriteria.filter { metCriteria.contains($0.id) }.count }

    var progress: Double {
        plan.tasks.isEmpty ? 0 : Double(tasksDone) / Double(plan.tasks.count)
    }

    var criteriaProgress: Double {
        plan.acceptanceCriteria.isEmpty ? 0 : Double(criteriaMet) / Double(plan.acceptanceCriteria.count)
    }

    // MARK: Verdicts (IDEA-020)

    /// A task is in at most one of done/failed/blocked; absent from all three = todo.
    /// `done` keeps its old meaning (passed), so pre-020 plans migrate with zero changes.
    func verdict(of taskID: String) -> TaskVerdict {
        if done.contains(taskID) { return .pass }
        if failed[taskID] != nil { return .fail }
        if blocked[taskID] != nil { return .blocked }
        return .todo
    }

    var failedCount: Int { plan.tasks.filter { failed[$0.id] != nil }.count }
    var blockedCount: Int { plan.tasks.filter { blocked[$0.id] != nil }.count }
    /// Pass + fail + blocked: everything with a recorded outcome.
    var resolvedCount: Int { tasksDone + failedCount + blockedCount }
}

/// Per-task outcome (IDEA-020). Todo = no recorded outcome.
nonisolated enum TaskVerdict: String, Codable, Sendable, CaseIterable, Identifiable {
    case todo, pass, fail, blocked

    var id: Self { self }

    var label: String {
        switch self {
        case .todo: "To do"
        case .pass: "Pass"
        case .fail: "Fail"
        case .blocked: "Blocked"
        }
    }

    var icon: String {
        switch self {
        case .todo: "circle"
        case .pass: "checkmark.circle.fill"
        case .fail: "xmark.circle.fill"
        case .blocked: "exclamationmark.circle.fill"
        }
    }
}

/// One step of the research log: a status line, a thought, or a tool call.
nonisolated struct FeedItem: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable { case status, thinking, tool }
    enum State: String, Codable, Sendable { case pending, done, failed }
    var id = UUID()
    var kind: Kind
    var title: String
    var detail: String
    var at: Date = .now
    /// Tool calls: pending until their result comes back.
    var state: State?
    /// Matches tool results / streamed thinking back to this row.
    var ref: String?
}

/// What the research run is doing right now, for the live progress header.
enum LivePhase: Equatable {
    case connecting
    case thinking(turn: Int)
    case reading(done: Int, total: Int)
    case writing(characters: Int)
}

@Observable
final class PlanStore {
    private(set) var plans: [SavedPlan] = []
    private(set) var folders: [PlanFolder] = []
    /// Rule-based virtual folders (IDEA-101).
    private(set) var smartFolders: [SmartFolder] = []
    /// A plan id, or `folder:<uuid>` for a folder overview.
    var selection: String?
    var expandedFolders: Set<UUID> = [] {
        didSet { UserDefaults.standard.set(expandedFolders.map(\.uuidString), forKey: "expandedFolders") }
    }

    private(set) var runningKey: String?
    private(set) var feed: [FeedItem] = []
    private(set) var phase: LivePhase = .connecting
    private(set) var startedAt: Date?
    private var currentTurn = 0
    var error: String?
    private var task: Task<Void, Never>?

    private let fileURL: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Checkpoint", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "plans.json")
    }()

    private var foldersURL: URL { fileURL.deletingLastPathComponent().appending(path: "folders.json") }

    // MARK: Sync hooks

    /// Called after each save with what changed locally; the sync coordinator listens.
    @ObservationIgnored var onLocalChange: ((StoreChanges) -> Void)?
    /// Last state handed to (or received from) sync, used to work out what changed.
    @ObservationIgnored private var syncedPlans: [String: SavedPlan] = [:]
    @ObservationIgnored private var syncedFolders: [UUID: PlanFolder] = [:]
    @ObservationIgnored private var syncedSmart: [UUID: SmartFolder] = [:]

    var snapshot: StoreSnapshot { StoreSnapshot(plans: plans, folders: folders, smartFolders: smartFolders) }

    /// Where evidence files live, for backends that mirror them.
    var evidenceRootURL: URL { evidenceRoot }

    private func markSynced() {
        syncedPlans = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        syncedFolders = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        syncedSmart = Dictionary(smartFolders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func emitPlanChanges() {
        guard let onLocalChange else { syncedPlans = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }); return }
        var c = StoreChanges()
        let now = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        c.plans = plans.filter { syncedPlans[$0.id] != $0 }
        c.deletedPlans = syncedPlans.keys.filter { now[$0] == nil }
        syncedPlans = now
        if !c.isEmpty { onLocalChange(c) }
    }

    private func emitFolderChanges() {
        let now = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        defer { syncedFolders = now }
        guard let onLocalChange else { return }
        var c = StoreChanges()
        c.folders = folders.filter { syncedFolders[$0.id] != $0 }
        c.deletedFolders = syncedFolders.keys.filter { now[$0] == nil }
        if !c.isEmpty { onLocalChange(c) }
    }

    private func emitSmartChanges() {
        let now = Dictionary(smartFolders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        defer { syncedSmart = now }
        guard let onLocalChange else { return }
        var c = StoreChanges()
        c.smartFolders = smartFolders.filter { syncedSmart[$0.id] != $0 }
        c.deletedSmartFolders = syncedSmart.keys.filter { now[$0] == nil }
        if !c.isEmpty { onLocalChange(c) }
    }

    /// Applies changes that came from another device. Nothing is echoed back.
    func applyRemote(_ c: StoreChanges) {
        guard !c.isEmpty else { return }
        for p in c.plans {
            if let i = plans.firstIndex(where: { $0.id == p.id }) {
                // A timer running here keeps running; everything else takes the newer copy.
                var incoming = p
                if incoming.timerRunningSince == nil, plans[i].timerRunningSince != nil,
                   incoming.testingSeconds <= plans[i].testingSeconds {
                    incoming.timerRunningSince = plans[i].timerRunningSince
                }
                plans[i] = incoming
            } else {
                plans.insert(p, at: 0)
            }
            Reminders.sync(p)
        }
        for id in c.deletedPlans {
            plans.removeAll { $0.id == id }
            if selection == id { selection = nil }
        }
        for f in c.folders {
            if let i = folders.firstIndex(where: { $0.id == f.id }) { folders[i] = f } else { folders.append(f) }
        }
        for id in c.deletedFolders {
            folders.removeAll { $0.id == id }
            for i in plans.indices where plans[i].folderID == id { plans[i].folderID = nil }
        }
        for f in c.smartFolders {
            if let i = smartFolders.firstIndex(where: { $0.id == f.id }) { smartFolders[i] = f } else { smartFolders.append(f) }
        }
        for id in c.deletedSmartFolders { smartFolders.removeAll { $0.id == id } }
        writeAll()
        markSynced()
    }

    /// Replaces a plan's evidence file list after a backend copied files in.
    func noteRemoteEvidence(planID: String) {
        // Evidence lists travel inside the plan, so the files just need to exist; nudge views.
        if let i = plans.firstIndex(where: { $0.id == planID }) { plans[i] = plans[i] }
    }

    private func writeAll() {
        if let data = try? JSONEncoder().encode(plans) { try? data.write(to: fileURL, options: .atomic) }
        if let data = try? JSONEncoder().encode(folders) { try? data.write(to: foldersURL, options: .atomic) }
        if let data = try? JSONEncoder().encode(smartFolders) { try? data.write(to: smartFoldersURL, options: .atomic) }
    }
    private var smartFoldersURL: URL { fileURL.deletingLastPathComponent().appending(path: "smartFolders.json") }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([SavedPlan].self, from: data) {
            plans = saved
        }
        if let data = try? Data(contentsOf: foldersURL),
           let saved = try? JSONDecoder().decode([PlanFolder].self, from: data) {
            folders = saved
        }
        if let data = try? Data(contentsOf: smartFoldersURL),
           let saved = try? JSONDecoder().decode([SmartFolder].self, from: data) {
            smartFolders = saved
        }
        expandedFolders = Set((UserDefaults.standard.stringArray(forKey: "expandedFolders") ?? []).compactMap(UUID.init))
        // Auto-pause testing timers left running at quit (IDEA-025).
        for i in plans.indices where plans[i].timerRunningSince != nil {
            if let since = plans[i].timerRunningSince {
                plans[i].testingSeconds += Date().timeIntervalSince(since)
                plans[i].timerRunningSince = nil
            }
        }
        if plans.contains(where: { $0.testingSeconds > 0 }) { save() }
        // Re-arm due-date banners after relaunch (system keeps them, but this
        // heals any missed cancel/finish races).
        for saved in plans { Reminders.sync(saved) }
        markSynced()
    }

    var selected: SavedPlan? { plans.first { $0.id == selection } }

    // MARK: - Folders

    static func folderTag(_ id: UUID) -> String { "folder:\(id.uuidString)" }
    static func smartFolderTag(_ id: UUID) -> String { "smart:\(id.uuidString)" }
    /// Pseudo-selection for the testing dashboard (IDEA-109).
    static let dashboardTag = "dashboard"

    var showingDashboard: Bool { selection == Self.dashboardTag }

    var selectedSmartFolder: SmartFolder? {
        guard let sel = selection, sel.hasPrefix("smart:"),
              let id = UUID(uuidString: String(sel.dropFirst(6))) else { return nil }
        return smartFolders.first { $0.id == id }
    }

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

    // MARK: - Organisation (IDEA-100/102/103/104/105)

    /// Sidebar sort order, persisted. Folders stay alphabetical; this orders plans.
    enum SidebarSort: String, CaseIterable, Identifiable {
        case updated, progress, key, acMet
        var id: Self { self }
        var label: String {
            switch self {
            case .updated: "Recently updated"
            case .progress: "Progress"
            case .key: "Ticket key"
            case .acMet: "AC met"
            }
        }
        var icon: String {
            switch self {
            case .updated: "clock"
            case .progress: "chart.pie"
            case .key: "key"
            case .acMet: "seal"
            }
        }
    }

    var sidebarSort: SidebarSort {
        get { SidebarSort(rawValue: UserDefaults.standard.string(forKey: "sidebarSort") ?? "") ?? .updated }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "sidebarSort") }
    }

    var sidebarSortAscending: Bool {
        get { UserDefaults.standard.bool(forKey: "sidebarSortAsc") }
        set { UserDefaults.standard.set(newValue, forKey: "sidebarSortAsc") }
    }

    /// All tags in use, for autocomplete + filters.
    var allTags: [String] {
        Array(Set(plans.flatMap(\.tags))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func sortPlans(_ list: [SavedPlan]) -> [SavedPlan] {
        let asc = sidebarSortAscending
        switch sidebarSort {
        case .updated: return list.sorted { asc ? $0.updatedAt < $1.updatedAt : $0.updatedAt > $1.updatedAt }
        case .progress: return list.sorted { asc ? $0.progress < $1.progress : $0.progress > $1.progress }
        case .key: return list.sorted { asc ? $0.plan.ticket.key < $1.plan.ticket.key : $0.plan.ticket.key > $1.plan.ticket.key }
        case .acMet: return list.sorted { asc ? $0.criteriaProgress < $1.criteriaProgress : $0.criteriaProgress > $1.criteriaProgress }
        }
    }

    /// Search/filter predicate for the sidebar (IDEA-100). Empty query matches all.
    func matches(_ saved: SavedPlan, query: String, mode: TestMode?, tracker: Tracker?, progress: SidebarProgressFilter, tag: String?, showArchived: Bool) -> Bool {
        if saved.archived && !showArchived { return false }
        if let mode, saved.mode != mode { return false }
        if let tracker, saved.tracker != tracker { return false }
        if let tag, !tag.isEmpty, !saved.tags.contains(tag) { return false }
        switch progress {
        case .all: break
        case .inProgress: guard saved.progress > 0 && saved.progress < 1 else { return false }
        case .done: guard saved.progress >= 1 else { return false }
        case .notStarted: guard saved.progress == 0 else { return false }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        let folderName = saved.folderID.flatMap { folder($0)?.name.lowercased() } ?? ""
        return saved.plan.ticket.key.lowercased().contains(q)
            || saved.plan.ticket.title.lowercased().contains(q)
            || folderName.contains(q)
            || saved.tags.contains { $0.lowercased().contains(q) }
    }

    enum SidebarProgressFilter: String, CaseIterable, Identifiable {
        case all, notStarted, inProgress, done
        var id: Self { self }
        var label: String {
            switch self {
            case .all: "All"
            case .notStarted: "Not started"
            case .inProgress: "In progress"
            case .done: "Done"
            }
        }
    }

    // MARK: Plan organisation actions
    func togglePin(_ planID: String) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        plans[i].pinned.toggle()
        plans[i].updatedAt = .now
        save()
    }

    func toggleArchive(_ planID: String) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        plans[i].archived.toggle()
        if plans[i].archived && selection == planID { selection = nil }
        plans[i].updatedAt = .now
        save()
    }

    func setTags(_ tags: Set<String>, for planID: String) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        plans[i].tags = Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }.prefix(20))
        plans[i].updatedAt = .now
        save()
    }

    func setDueDate(_ date: Date?, for planID: String) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        plans[i].dueDate = date
        plans[i].updatedAt = .now
        save()
        if date == nil { Reminders.cancel(planID: planID) } else { Reminders.sync(plans[i], askPermission: true) }
    }

    // MARK: - Re-run diff (IDEA-007)

    /// Transient diff of the most recent re-run; cleared when viewed or on next run.
    var planDiff: PlanDiff?

    func clearDiff() { planDiff = nil }

    // MARK: - Chat + revision (IDEA-083/084)

    private(set) var chatBusyID: String?
    private(set) var regenerating: String?

    /// Asks a follow-up grounded in the plan; appends both sides to the thread.
    func sendChat(_ question: String, in planID: String, settings: AppSettings) {
        guard let saved = plans.first(where: { $0.id == planID }),
              !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              chatBusyID == nil else { return }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        appendChat(planID: planID, role: .user, text: q)
        chatBusyID = planID
        let plan = saved.plan
        let config = settings.llmConfig
        Task {
            do {
                let reply = try await PlanChat.answer(plan: plan, question: q, config: config)
                appendChat(planID: planID, role: .assistant, text: reply)
            } catch {
                appendChat(planID: planID, role: .assistant, text: "Couldn't answer that: \(error.localizedDescription)")
            }
            chatBusyID = nil
        }
    }

    private func appendChat(planID: String, role: ChatMsg.Role, text: String) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        plans[i].chat.append(ChatMsg(role: role, text: text))
        plans[i].updatedAt = .now
        save()
    }

    /// Revises the whole plan from an instruction, merging by ID (IDEA-083 apply).
    func applyChatRevision(_ instruction: String, in planID: String, settings: AppSettings) {
        revise(planID: planID, instruction: instruction, section: nil, settings: settings)
    }

    /// Regenerates one section (IDEA-084): tasks, ac or edgeCases.
    func regenerate(section: RevisionSection, in planID: String, settings: AppSettings) {
        let instruction: String
        switch section {
        case .tasks:
            instruction = "Rewrite ONLY the tasks array — sharper steps, better coverage, same ticket scope. Keep acceptanceCriteria, edgeCases, summary and preconditions exactly as they are."
        case .ac:
            instruction = "Rewrite ONLY the acceptanceCriteria array — faithful to the tickets, each with its source. Keep tasks (updating their covers ids to match), edgeCases, summary and preconditions as they are."
        case .edgeCases:
            instruction = "Rewrite ONLY the edgeCases array — 5-7 sharp negative paths for this change. Keep everything else exactly as it is."
        }
        revise(planID: planID, instruction: instruction, section: section, settings: settings)
    }

    nonisolated enum RevisionSection: String, Sendable {
        case tasks, ac, edgeCases
        var label: String {
            switch self {
            case .tasks: "tasks"
            case .ac: "acceptance criteria"
            case .edgeCases: "edge cases"
            }
        }
    }

    private func revise(planID: String, instruction: String, section: RevisionSection?, settings: AppSettings) {
        guard let saved = plans.first(where: { $0.id == planID }),
              regenerating == nil, chatBusyID == nil else { return }
        regenerating = planID + (section.map { ":\($0.rawValue)" } ?? ":full")
        let plan = saved.plan
        let config = settings.llmConfig
        Task {
            do {
                let revised = try await PlanChat.revise(plan: plan, instruction: instruction, config: config)
                await MainActor.run { self.mergeRevision(revised, into: planID, section: section) }
            } catch {
                self.error = "Revision failed: \(error.localizedDescription)"
            }
            regenerating = nil
        }
    }

    /// Merges a revision, preserving outcomes/notes/evidence by surviving ID.
    private func mergeRevision(_ revised: TestPlan, into planID: String, section: RevisionSection?) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        var plan = plans[i].plan
        switch section {
        case nil:
            plan = revised
        case .tasks:
            plan.tasks = revised.tasks
        case .ac:
            plan.acceptanceCriteria = revised.acceptanceCriteria
        case .edgeCases:
            plan.edgeCases = revised.edgeCases
        }
        plans[i].plan = plan
        let keepable = Set(plan.tasks.map(\.id) + plan.scenarios.map { "scenario:" + $0.id })
        plans[i].done = plans[i].done.intersection(keepable)
        plans[i].metCriteria = plans[i].metCriteria.intersection(plan.acceptanceCriteria.map(\.id))
        plans[i].failed = plans[i].failed.filter { keepable.contains($0.key) }
        plans[i].blocked = plans[i].blocked.filter { keepable.contains($0.key) }
        plans[i].notes = plans[i].notes.filter { keepable.contains($0.key) }
        plans[i].evidence = plans[i].evidence.filter { keepable.contains($0.key) }
        plans[i].updatedAt = .now
        save()
    }
    // MARK: - Draft tasks (IDEA-016/017)

    /// One-click starter task covering an uncovered criterion (IDEA-016).
    func suggestTask(for criterionID: String, in planID: String) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        let plan = plans[i].plan
        guard let ac = plan.acceptanceCriteria.first(where: { $0.id == criterionID }) else { return }
        let id = "gap-\(criterionID)"
        guard !plan.tasks.contains(where: { $0.id == id }) else { return }
        plans[i].plan.tasks.append(TestPlan.Task(
            id: id, title: "Verify \(criterionID): \(ac.text.prefix(80))",
            ticketKey: plan.ticket.key, area: "", priority: .medium,
            steps: ["Open the area described in \(criterionID).", "Check the behaviour matches the criterion."],
            expected: ac.text, covers: [criterionID]))
        plans[i].updatedAt = .now
        save()
    }

    /// Curated negative-path tasks, skipping near-duplicates (IDEA-017).
    func boostEdgeCases(in planID: String) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        let existing = plans[i].plan.tasks.map { $0.title.lowercased() }
        func dup(_ title: String) -> Bool {
            let stem = title.lowercased().prefix(24)
            return existing.contains { $0.contains(stem) || stem.contains($0.prefix(24)) }
        }
        let key = plans[i].plan.ticket.key
        let candidates: [(String, [String], String)] = [
            ("Invalid input is rejected cleanly",
             ["Enter clearly invalid data in each field.", "Submit."],
             "A helpful inline error appears; nothing is saved."),
            ("Empty states behave",
             ["Clear the relevant data or start fresh.", "Open the screen."],
             "A sensible empty state shows instead of an error or blank page."),
            ("Wrong role is refused",
             ["Log in as a role that should not have access.", "Try the change."],
             "Access is denied with a clear message."),
            ("Refresh and back navigation keep state sane",
             ["Get halfway through the flow.", "Refresh, then go back and forward."],
             "No duplicate actions and no lost input."),
            ("Long input doesn't break layout",
             ["Paste a very long string into text fields.", "Save and view."],
             "Text truncates or wraps; layout holds."),
        ]
        var added = 0
        for (title, steps, expected) in candidates where !dup(title) {
            plans[i].plan.tasks.append(TestPlan.Task(
                id: "edge-\(UUID().uuidString.prefix(8))", title: title, ticketKey: key,
                area: "edge", priority: .medium, steps: steps, expected: expected, covers: []))
            added += 1
            if added >= 5 { break }
        }
        if added > 0 {
            plans[i].updatedAt = .now
            save()
        }
    }

    var pinnedPlans: [SavedPlan] { sortPlans(plans.filter { $0.pinned && !$0.archived }) }

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
        plans[i].updatedAt = .now
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
        emitFolderChanges()
    }

    // MARK: - Smart folders (IDEA-101)

    func plans(matching smart: SmartFolder) -> [SavedPlan] {
        sortPlans(plans.filter { smart.matches($0) })
    }

    var allLabels: [String] {
        Array(Set(plans.flatMap { $0.plan.ticket.labels })).sorted()
    }

    var allComponents: [String] {
        Array(Set(plans.flatMap { $0.plan.ticket.components })).sorted()
    }

    var allFixVersions: [String] {
        Array(Set(plans.flatMap { $0.plan.ticket.fixVersions })).sorted()
    }

    @discardableResult
    func createSmartFolder(name: String = "New Smart Folder", kind: SmartFolder.Kind = .label, value: String = "") -> SmartFolder {
        let f = SmartFolder(name: name, kind: kind, value: value)
        smartFolders.append(f)
        saveSmartFolders()
        return f
    }

    func updateSmartFolder(_ id: UUID, name: String, kind: SmartFolder.Kind, value: String) {
        guard let i = smartFolders.firstIndex(where: { $0.id == id }) else { return }
        smartFolders[i].name = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : name
        smartFolders[i].kind = kind
        smartFolders[i].value = value
        saveSmartFolders()
    }

    func deleteSmartFolder(_ id: UUID) {
        smartFolders.removeAll { $0.id == id }
        if selection == Self.smartFolderTag(id) { selection = nil }
        saveSmartFolders()
    }

    /// Freezes the current membership into a static folder.
    func convertSmartFolder(_ id: UUID) {
        guard let smart = smartFolders.first(where: { $0.id == id }) else { return }
        let folder = createFolder(named: smart.name, in: nil)
        for plan in plans where smart.matches(plan) {
            if let i = plans.firstIndex(where: { $0.id == plan.id }) {
                plans[i].folderID = folder.id
                plans[i].updatedAt = .now
            }
        }
        save()
        deleteSmartFolder(id)
        selection = Self.folderTag(folder.id)
    }

    private func saveSmartFolders() {
        guard let data = try? JSONEncoder().encode(smartFolders) else { return }
        try? data.write(to: smartFoldersURL, options: .atomic)
        emitSmartChanges()
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

    /// Quick preset = optional cheaper model at low effort (IDEA-082).
    static func quickOverrides(settings: AppSettings) -> (model: String?, effort: String?) {
        (settings.quickModel.isEmpty ? nil : settings.quickModel, "low")
    }

    /// `mode`/`tracker` default to the toggle and link detection; re-runs pass the plan's own.
    func analyze(_ input: String, mode: TestMode? = nil, tracker: Tracker? = nil,
                 template: PlanGenerator.PlanTemplate? = nil,
                 modelOverride: String? = nil, effortOverride: String? = nil,
                 settings: AppSettings) {
        let mode = mode ?? settings.mode
        let tracker = tracker ?? settings.tracker(for: input)
        guard let key = Self.extractKey(input) else {
            error = "That doesn't look like a Jira key (e.g. PROJ-1234)."
            return
        }
        guard settings.isLLMConfigured else {
            error = "Set up an AI provider in \(Platform.settingsName) — \(settings.provider.label) needs \(settings.provider.requiresKey ? "an API key and " : "")a model."
            return
        }
        guard settings.isConfigured(tracker) else {
            error = "Connect \(tracker.label) in \(Platform.settingsName) to analyze \(tracker.label) issues."
            return
        }
        task?.cancel()
        error = nil
        feed = []
        phase = .connecting
        let startedAt = Date()
        self.startedAt = startedAt
        runningKey = key
        runningMode = mode
        runningTracker = tracker
        // New plans land in the folder you're looking at.
        let targetFolder = selectedFolder?.id ?? selected?.folderID
        selection = nil

        task = Task {
            do {
                let saved = try await self.runSingle(key: key, mode: mode, tracker: tracker,
                                                     settings: settings, targetFolder: targetFolder, startedAt: startedAt,
                                                     template: template,
                                                     modelOverride: modelOverride, effortOverride: effortOverride)
                selection = saved.id
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            runningKey = nil
        }
    }

    /// Shared single-plan runner: research via the generator, then merge with
    /// any previous run (ticks, verdicts, tags, folder survive). Used by both
    /// `analyze()` and the batch queue. Reports progress into the shared feed.
    private func runSingle(key: String, mode: TestMode, tracker: Tracker, settings: AppSettings,
                           targetFolder: UUID?, startedAt: Date,
                           template: PlanGenerator.PlanTemplate? = nil,
                           modelOverride: String? = nil, effortOverride: String? = nil) async throws -> SavedPlan {
        var cfg = settings.llmConfig
        if let modelOverride, !modelOverride.isEmpty { cfg.model = modelOverride }
        if let effortOverride { cfg.effort = effortOverride }
        let generator = PlanGenerator(
            llm: cfg,
            mcp: settings.makeMCPClient(for: tracker),
            site: settings.siteHost,
            mode: mode,
            tracker: tracker,
            environment: settings.qaEnvironment
        )
        // Codebase access (read-only, security-scoped) only for "tickets + codebase" scenarios.
        var generatorWithScenarios = generator
        generatorWithScenarios.scenarios = settings.scenarioMode
        generatorWithScenarios.houseRules = settings.houseRules
        generatorWithScenarios.templateOverride = template
        generatorWithScenarios.researchSources = settings.customTrackers
            .filter(\.useForResearch)
            .compactMap { t in settings.makeMCPClient(forCustom: t).map { (t.displayName, $0) } }
        let codebaseURL = settings.scenarioMode == .ticketsAndCode ? settings.openCodebase() : nil
        if let codebaseURL { generatorWithScenarios.codebase = CodebaseTools(root: codebaseURL) }
        let runGenerator = generatorWithScenarios
        defer { codebaseURL?.stopAccessingSecurityScopedResource() }
        let (plan, usage) = try await runGenerator.run(ticketKey: key) { event in
            await MainActor.run { self.record(event) }
        }
        let id = SavedPlan.id(plan.ticket.key, mode, tracker)
        let previous = plans.first { $0.id == id }
        // Keep ticks for tasks that survived a re-run.
        let keepable = Set(plan.tasks.map(\.id) + plan.scenarios.map { "scenario:" + $0.id })
        let kept = previous?.done.intersection(keepable) ?? []
        var saved = SavedPlan(plan: plan, mode: mode, tracker: tracker, createdAt: .now, done: kept)
        saved.metCriteria = previous?.metCriteria.intersection(plan.acceptanceCriteria.map(\.id)) ?? []
        saved.failed = (previous?.failed ?? [:]).filter { keepable.contains($0.key) }
        saved.blocked = (previous?.blocked ?? [:]).filter { keepable.contains($0.key) }
        saved.folderID = previous?.folderID ?? targetFolder
        saved.tags = previous?.tags ?? []
        saved.pinned = previous?.pinned ?? false
        saved.archived = previous?.archived ?? false
        saved.dueDate = previous?.dueDate
        saved.template = template?.rawValue ?? previous?.template ?? "auto"
        saved.notes = (previous?.notes ?? [:]).filter { keepable.contains($0.key) }
        saved.evidence = (previous?.evidence ?? [:]).filter { keepable.contains($0.key) }
        saved.chat = previous?.chat ?? []
        saved.testingSeconds = previous?.testingSeconds ?? 0
        saved.usage = usage.isEmpty ? previous?.usage : usage
        if !usage.isEmpty {
            saved.usageProvider = settings.llmConfig.provider.rawValue
            saved.usageModel = cfg.model
        } else if previous?.usage != nil {
            saved.usageProvider = previous?.usageProvider ?? "anthropic"
            saved.usageModel = previous?.usageModel ?? ""
        }
        saved.preset = modelOverride != nil || effortOverride != nil ? "quick" : (previous?.preset ?? "deep")
        saved.updatedAt = .now
        saved.research = feed
        saved.researchDuration = Date().timeIntervalSince(startedAt)
        planDiff = previous.map { PlanDiff.compare(old: $0.plan, new: plan, planID: id) } ?? nil
        plans.removeAll { $0.id == id }
        plans.insert(saved, at: 0)
        save()
        return saved
    }

    // MARK: - Batch queue (IDEA-106/108)

    private(set) var batchRunning = false
    private(set) var batchDone = 0
    private(set) var batchTotal = 0
    private(set) var batchErrors: [String: String] = [:]
    private var batchTask: Task<Void, Never>?

    var batchLabel: String {
        batchRunning ? "\(min(batchDone + 1, max(batchTotal, 1)))/\(batchTotal)" : ""
    }

    /// Runs `inputs` one at a time into a new folder. Invalid keys are skipped
    /// up front; per-plan failures are collected and summarized at the end.
    func startBatch(inputs: [String], mode: TestMode, tracker: Tracker, settings: AppSettings,
                    folderName: String, template: PlanGenerator.PlanTemplate? = nil) {
        cancelBatch(silent: true)
        let keys = inputs.compactMap(Self.extractKey)
        guard !keys.isEmpty else {
            error = "No ticket keys found in that input."
            return
        }
        guard settings.isLLMConfigured, settings.isConfigured(tracker) else {
            error = "Connect an AI provider and \(tracker.label) in \(Platform.settingsName) first."
            return
        }
        let folder = createFolder(named: folderName, in: selectedFolder?.id ?? selected?.folderID)
        expandedFolders.insert(folder.id)
        batchRunning = true
        batchDone = 0
        batchTotal = keys.count
        batchErrors = [:]
        error = nil
        batchTask = Task {
            for key in keys {
                if Task.isCancelled { break }
                feed = []
                phase = .connecting
                let startedAt = Date()
                self.startedAt = startedAt
                runningKey = key
                runningMode = mode
                runningTracker = tracker
                do {
                    _ = try await self.runSingle(key: key, mode: mode, tracker: tracker,
                                                 settings: settings, targetFolder: folder.id, startedAt: startedAt,
                                                 template: template)
                } catch is CancellationError {
                    break
                } catch {
                    batchErrors[key] = error.localizedDescription
                }
                batchDone += 1
            }
            runningKey = nil
            batchRunning = false
            if Task.isCancelled {
                error = "Batch cancelled after \(batchDone)/\(batchTotal) plans."
            } else if !batchErrors.isEmpty {
                error = "Batch finished with \(batchErrors.count) failure(s): " +
                    batchErrors.sorted(by: { $0.key < $1.key }).prefix(3)
                        .map { "\($0.key): \($0.value.prefix(90))" }.joined(separator: " · ")
            }
            selection = Self.folderTag(folder.id)
            batchTask = nil
        }
    }

    func cancelBatch(silent: Bool = false) {
        batchTask?.cancel()
        batchTask = nil
        batchRunning = false
        runningKey = nil
        if !silent { error = "Batch cancelled." }
    }

    func cancel() {
        task?.cancel()
        if batchRunning {
            cancelBatch()
        } else {
            runningKey = nil
        }
    }

    func toggle(_ taskID: String, in planID: String) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        if plans[i].done.contains(taskID) {
            plans[i].done.remove(taskID)
        } else {
            // Tapping a failed/blocked task's checkbox marks it passed.
            plans[i].done.insert(taskID)
            plans[i].failed.removeValue(forKey: taskID)
            plans[i].blocked.removeValue(forKey: taskID)
        }
        plans[i].updatedAt = .now
        save()
        // Finishing the plan retires its reminder.
        Reminders.sync(plans[i])
    }

    /// Sets a task's verdict, enforcing the single-state invariant.
    /// Fail wants an `actual`, blocked wants a `reason` (may be empty).
    func setVerdict(_ verdict: TaskVerdict, for taskID: String, in planID: String, detail: String = "") {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        plans[i].done.remove(taskID)
        plans[i].failed.removeValue(forKey: taskID)
        plans[i].blocked.removeValue(forKey: taskID)
        switch verdict {
        case .todo: break
        case .pass: plans[i].done.insert(taskID)
        case .fail: plans[i].failed[taskID] = detail
        case .blocked: plans[i].blocked[taskID] = detail
        }
        plans[i].updatedAt = .now
        save()
        Reminders.sync(plans[i])
    }

    // MARK: - Notes (IDEA-021)

    func setNote(_ text: String, for taskID: String, in planID: String) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            plans[i].notes.removeValue(forKey: taskID)
        } else {
            plans[i].notes[taskID] = text
        }
        plans[i].updatedAt = .now
        save()
    }

    // MARK: - Testing timer (IDEA-025)

    /// Live total including a running session.
    func elapsedTesting(_ saved: SavedPlan) -> TimeInterval {
        saved.testingSeconds + (saved.timerRunningSince.map { Date().timeIntervalSince($0) } ?? 0)
    }

    func toggleTimer(for planID: String) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        if let since = plans[i].timerRunningSince {
            plans[i].testingSeconds += Date().timeIntervalSince(since)
            plans[i].timerRunningSince = nil
        } else {
            plans[i].timerRunningSince = .now
        }
        plans[i].updatedAt = .now
        save()
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    // MARK: - Evidence (IDEA-022)

    private var evidenceRoot: URL {
        fileURL.deletingLastPathComponent().appending(path: "evidence", directoryHint: .isDirectory)
    }

    func evidenceDir(planID: String, taskID: String) -> URL {
        evidenceRoot.appending(path: planID, directoryHint: .isDirectory)
            .appending(path: taskID, directoryHint: .isDirectory)
    }

    /// Saves in-memory evidence (a photo from the camera or library) as a file.
    @discardableResult
    func attachEvidence(data: Data, name: String, planID: String, taskID: String) -> [String] {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let file = tmp.appending(path: name)
        guard (try? data.write(to: file)) != nil else { return [] }
        defer { try? FileManager.default.removeItem(at: tmp) }
        return attachEvidence([file], planID: planID, taskID: taskID)
    }

    /// Copies user-picked files into the plan's evidence folder. Returns saved names.
    @discardableResult
    func attachEvidence(_ urls: [URL], planID: String, taskID: String) -> [String] {
        guard plans.contains(where: { $0.id == planID }) else { return [] }
        let dir = evidenceDir(planID: planID, taskID: taskID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var names: [String] = []
        for url in urls.prefix(10) {
            // Picked/dropped files may be security-scoped; temp files (photos) aren't.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var name = url.lastPathComponent
            if FileManager.default.fileExists(atPath: dir.appending(path: name).path) {
                name = UUID().uuidString.prefix(8) + "-" + name
            }
            let dest = dir.appending(path: name)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                // 10 MB per file cap.
                if let size = try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > 10 * 1024 * 1024 {
                    try? FileManager.default.removeItem(at: dest)
                } else {
                    names.append(name)
                }
            }
        }
        guard !names.isEmpty, let i = plans.firstIndex(where: { $0.id == planID }) else { return names }
        plans[i].evidence[taskID, default: []].append(contentsOf: names)
        plans[i].updatedAt = .now
        save()
        return names
    }

    func removeEvidence(_ name: String, planID: String, taskID: String) {
        try? FileManager.default.removeItem(at: evidenceDir(planID: planID, taskID: taskID).appending(path: name))
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        plans[i].evidence[taskID]?.removeAll { $0 == name }
        if plans[i].evidence[taskID]?.isEmpty == true { plans[i].evidence.removeValue(forKey: taskID) }
        plans[i].updatedAt = .now
        save()
    }

    func evidenceData(_ name: String, planID: String, taskID: String, maxBytes: Int = 2 * 1024 * 1024) -> Data? {
        let url = evidenceDir(planID: planID, taskID: taskID).appending(path: name)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? .max) <= maxBytes else { return nil }
        return try? Data(contentsOf: url)
    }

    func toggleCriterion(_ criterionID: String, in planID: String) {
        guard let i = plans.firstIndex(where: { $0.id == planID }) else { return }
        if plans[i].metCriteria.contains(criterionID) { plans[i].metCriteria.remove(criterionID) }
        else { plans[i].metCriteria.insert(criterionID) }
        plans[i].updatedAt = .now
        save()
    }

    func delete(_ planID: String) {
        plans.removeAll { $0.id == planID }
        if selection == planID { selection = nil }
        Reminders.cancel(planID: planID)
        try? FileManager.default.removeItem(at: evidenceRoot.appending(path: planID))
        save()
    }

    private func record(_ event: PlanGenerator.Event) {
        switch event {
        case .status(let s):
            feed.append(FeedItem(kind: .status, title: s, detail: ""))
        case .waiting(let turn):
            currentTurn = turn
            phase = .thinking(turn: turn)
        case .thinking(let turn, let index, let text):
            let ref = "t\(turn)-\(index)"
            let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
            if let i = feed.lastIndex(where: { $0.ref == ref }) {
                feed[i].title = firstLine
                feed[i].detail = text
            } else {
                feed.append(FeedItem(kind: .thinking, title: firstLine, detail: text, ref: ref))
            }
        case .writing(let n):
            phase = .writing(characters: n)
        case .toolCall(let id, let name, let detail):
            feed.append(FeedItem(kind: .tool, title: Self.friendly(name), detail: detail, state: .pending, ref: id))
            updateReadingPhase()
        case .toolDone(let id, let ok):
            if let i = feed.lastIndex(where: { $0.ref == id }) { feed[i].state = ok ? .done : .failed }
            updateReadingPhase()
        }
    }

    /// Progress across the current batch of tool calls; once all return, Claude is thinking again.
    private func updateReadingPhase() {
        let batchStart = feed.lastIndex { $0.kind != .tool }.map { $0 + 1 } ?? 0
        let batch = feed[batchStart...]
        let done = batch.filter { $0.state != .pending }.count
        phase = done < batch.count ? .reading(done: done, total: batch.count) : .thinking(turn: currentTurn)
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
        case "code_search": "Searched code"
        case "code_read": "Read file"
        case "code_list": "Listed folder"
        default: tool
        }
    }

    private func save() {
        // Any content change counts as an edit, so "newest wins" across devices is reliable
        // even for mutations that don't bump updatedAt themselves.
        for i in plans.indices {
            if let old = syncedPlans[plans[i].id], old != plans[i], plans[i].updatedAt <= old.updatedAt {
                plans[i].updatedAt = .now
            }
        }
        guard let data = try? JSONEncoder().encode(plans) else { return }
        try? data.write(to: fileURL, options: .atomic)
        emitPlanChanges()
    }
}

/// What changed between two runs of the same plan (IDEA-007). Transient.
nonisolated struct PlanDiff: Sendable {
    var planID: String
    var addedTasks: Set<String> = []
    var changedTasks: Set<String> = []
    var removedTasks: Int = 0
    var addedAC: Set<String> = []
    var removedAC: Int = 0

    var isEmpty: Bool {
        addedTasks.isEmpty && changedTasks.isEmpty && removedTasks == 0 && addedAC.isEmpty && removedAC == 0
    }

    var summary: String {
        var parts: [String] = []
        if !addedTasks.isEmpty { parts.append("\(addedTasks.count) added") }
        if !changedTasks.isEmpty { parts.append("\(changedTasks.count) changed") }
        if removedTasks > 0 { parts.append("\(removedTasks) removed") }
        if !addedAC.isEmpty || removedAC > 0 { parts.append("AC updated") }
        return parts.joined(separator: " · ")
    }

    static func compare(old: TestPlan, new: TestPlan, planID: String) -> PlanDiff? {
        let oldTasks = Dictionary(uniqueKeysWithValues: old.tasks.map { ($0.id, $0) })
        let newTasks = Dictionary(uniqueKeysWithValues: new.tasks.map { ($0.id, $0) })
        func sig(_ t: TestPlan.Task) -> String { t.title + "\n" + t.steps.joined(separator: "\n") + "\n" + t.expected }
        var diff = PlanDiff(planID: planID)
        for (id, t) in newTasks {
            if oldTasks[id] == nil { diff.addedTasks.insert(id) }
            else if sig(oldTasks[id]!) != sig(t) { diff.changedTasks.insert(id) }
        }
        diff.removedTasks = oldTasks.keys.filter { newTasks[$0] == nil }.count
        let oldAC = Set(old.acceptanceCriteria.map(\.id))
        let newAC = Set(new.acceptanceCriteria.map(\.id))
        diff.addedAC = newAC.subtracting(oldAC)
        diff.removedAC = oldAC.subtracting(newAC).count
        return diff.isEmpty ? nil : diff
    }
}


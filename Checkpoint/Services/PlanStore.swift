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
    }

    var progress: Double {
        plan.tasks.isEmpty ? 0 : Double(plan.tasks.filter { done.contains($0.id) }.count) / Double(plan.tasks.count)
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
    var selection: String?

    private(set) var runningKey: String?
    private(set) var feed: [FeedItem] = []
    var error: String?
    private var task: Task<Void, Never>?

    private let fileURL: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Checkpoint", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "plans.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([SavedPlan].self, from: data) {
            plans = saved
        }
    }

    var selected: SavedPlan? { plans.first { $0.id == selection } }
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
                plans.removeAll { $0.id == id }
                plans.insert(SavedPlan(plan: plan, mode: mode, tracker: tracker, createdAt: .now, done: kept), at: 0)
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

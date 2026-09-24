import Foundation
import Observation

nonisolated struct SavedPlan: Codable, Sendable, Identifiable, Hashable {
    /// Dev and QA plans for the same ticket are kept side by side.
    var id: String { Self.id(plan.ticket.key, mode) }
    var plan: TestPlan
    var mode: TestMode
    var createdAt: Date
    var done: Set<String>

    static func id(_ key: String, _ mode: TestMode) -> String { "\(key):\(mode.rawValue)" }

    init(plan: TestPlan, mode: TestMode, createdAt: Date, done: Set<String>) {
        self.plan = plan
        self.mode = mode
        self.createdAt = createdAt
        self.done = done
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decode(TestPlan.self, forKey: .plan)
        // Plans saved before modes existed were dev plans.
        mode = try c.decodeIfPresent(TestMode.self, forKey: .mode) ?? .dev
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

    /// `mode` defaults to the current toolbar toggle; re-runs pass the plan's own mode.
    func analyze(_ input: String, mode: TestMode? = nil, settings: AppSettings) {
        let mode = mode ?? settings.mode
        guard let key = Self.extractKey(input) else {
            error = "That doesn't look like a Jira key (e.g. PROJ-1234)."
            return
        }
        guard settings.isConfigured else {
            error = "Add your Anthropic key and connect Atlassian in Settings (⌘,)."
            return
        }
        task?.cancel()
        error = nil
        feed = []
        runningKey = key
        runningMode = mode
        selection = nil

        let generator = PlanGenerator(
            claude: ClaudeClient(apiKey: settings.anthropicKey),
            mcp: settings.makeMCPClient(),
            model: settings.model,
            effort: settings.effort,
            site: settings.siteHost,
            mode: mode,
            environment: settings.qaEnvironment
        )
        task = Task {
            do {
                let plan = try await generator.run(ticketKey: key) { event in
                    await MainActor.run { self.record(event) }
                }
                let id = SavedPlan.id(plan.ticket.key, mode)
                let previous = plans.first { $0.id == id }
                // Keep ticks for tasks that survived a re-run.
                let kept = previous?.done.intersection(plan.tasks.map(\.id)) ?? []
                plans.removeAll { $0.id == id }
                plans.insert(SavedPlan(plan: plan, mode: mode, createdAt: .now, done: kept), at: 0)
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
        default: tool
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(plans) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

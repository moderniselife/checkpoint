import Foundation
import Observation

nonisolated struct SavedPlan: Codable, Sendable, Identifiable, Hashable {
    var id: String { plan.ticket.key }
    var plan: TestPlan
    var createdAt: Date
    var done: Set<String>

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

    func analyze(_ input: String, settings: AppSettings) {
        guard let key = Self.extractKey(input) else {
            error = "That doesn't look like a Jira key (e.g. PROJ-1234)."
            return
        }
        guard settings.isConfigured else {
            error = "Add your Anthropic key and Atlassian email + API token in Settings (⌘,)."
            return
        }
        task?.cancel()
        error = nil
        feed = []
        runningKey = key
        selection = nil

        let generator = PlanGenerator(
            claude: ClaudeClient(apiKey: settings.anthropicKey),
            mcp: MCPClient(authHeader: settings.atlassianAuthHeader),
            model: settings.model,
            effort: settings.effort,
            site: settings.siteHost
        )
        task = Task {
            do {
                let plan = try await generator.run(ticketKey: key) { event in
                    await MainActor.run { self.record(event) }
                }
                let previous = plans.first { $0.id == plan.ticket.key }
                // Keep ticks for tasks that survived a re-run.
                let kept = previous?.done.intersection(plan.tasks.map(\.id)) ?? []
                plans.removeAll { $0.id == plan.ticket.key }
                plans.insert(SavedPlan(plan: plan, createdAt: .now, done: kept), at: 0)
                save()
                selection = plan.ticket.key
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

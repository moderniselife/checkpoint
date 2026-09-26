import Foundation

/// Where a ticket lives.
nonisolated enum Tracker: String, Codable, Sendable, CaseIterable, Identifiable {
    case jira, linear
    /// A user-added MCP server; which one is stored alongside (e.g. `SavedPlan.customTrackerID`).
    case custom

    var id: Self { self }
    /// Jira and Linear: the trackers with dedicated sign-in, ticket panel and prompts.
    static let builtIn: [Tracker] = [.jira, .linear]

    var label: String {
        switch self {
        case .jira: "Jira"
        case .linear: "Linear"
        case .custom: "Custom tracker"
        }
    }

    var icon: String {
        switch self {
        case .jira: "square.stack.3d.up"
        case .linear: "line.3.horizontal.decrease.circle"
        case .custom: "server.rack"
        }
    }

    /// Pasted links decide the tracker; bare keys (PROJ-12 / ENG-12) look identical in both.
    static func detect(in input: String) -> Tracker? {
        let s = input.lowercased()
        if s.contains("linear.app") { return .linear }
        if s.contains("atlassian.net") || s.contains("jira") { return .jira }
        return nil
    }
}

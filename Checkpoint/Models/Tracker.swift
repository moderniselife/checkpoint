import Foundation

/// Where a ticket lives.
nonisolated enum Tracker: String, Codable, Sendable, CaseIterable, Identifiable {
    case jira, linear

    var id: Self { self }
    var label: String { self == .jira ? "Jira" : "Linear" }
    var icon: String { self == .jira ? "square.stack.3d.up" : "line.3.horizontal.decrease.circle" }

    /// Pasted links decide the tracker; bare keys (PROJ-12 / ENG-12) look identical in both.
    static func detect(in input: String) -> Tracker? {
        let s = input.lowercased()
        if s.contains("linear.app") { return .linear }
        if s.contains("atlassian.net") || s.contains("jira") { return .jira }
        return nil
    }
}

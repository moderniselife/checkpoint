import SwiftUI

/// Sidebar destinations, grouped like macOS System Settings.
///
/// Adding a new settings area = add a case here + its pane in
/// `SettingsView.detail(for:)`. Built-in trackers (Jira/Linear) each get a case;
/// user-added endpoints are covered by the single `.customMCP` case which
/// lists every `CustomMCPTracker`.
enum SettingsSection: Hashable, Identifiable {
    case aiProvider
    case jira
    case linear
    case customMCP(id: UUID?)   // nil = list, UUID = detail for one tracker
    case researchTools(id: UUID?)
    case testing
    case scenarios
    case sync
    case advanced

    var id: String {
        switch self {
        case .aiProvider: "ai"
        case .jira: "jira"
        case .linear: "linear"
        case .customMCP(let id): "custom-\(id?.uuidString ?? "list")"
        case .researchTools(let id): "research-\(id?.uuidString ?? "list")"
        case .testing: "testing"
        case .scenarios: "scenarios"
        case .sync: "sync"
        case .advanced: "advanced"
        }
    }

    var title: String {
        switch self {
        case .aiProvider: "AI Provider"
        case .jira: "Jira"
        case .linear: "Linear"
        case .customMCP: "Custom Servers"
        case .researchTools: "Research Tools"
        case .testing: "Testing"
        case .scenarios: "Scenarios"
        case .sync: "Sync"
        case .advanced: "Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .aiProvider: "Model, key and effort used to write plans"
        case .jira: "Atlassian Rovo MCP — issues, comments, specs"
        case .linear: "Linear read-only MCP — issues and comments"
        case .customMCP: "Any MCP server that holds tickets — Asana, your own tracker"
        case .researchTools: "MCP tools for research and test setup — Obsidian, Corellium"
        case .testing: "Default mode and hosted environment"
        case .scenarios: "End-to-end journeys from tickets and code"
        case .sync: "Your plans on every device"
        case .advanced: "Routing, connections and storage"
        }
    }

    var icon: String {
        switch self {
        case .aiProvider: "brain.head.profile"
        case .jira: "square.stack.3d.up"
        case .linear: "line.3.horizontal.decrease.circle"
        case .customMCP: "server.rack"
        case .researchTools: "wand.and.stars"
        case .testing: "checkmark.shield"
        case .scenarios: "map"
        case .sync: "arrow.triangle.2.circlepath.icloud"
        case .advanced: "gearshape"
        }
    }

    /// Brand tile shown instead of a symbol, for built-in trackers.
    var logo: Tracker? {
        switch self {
        case .jira: .jira
        case .linear: .linear
        default: nil
        }
    }

    var tint: Color {
        switch self {
        case .aiProvider: .purple
        case .jira: .blue
        case .linear: .indigo
        case .customMCP: .teal
        case .researchTools: .pink
        case .testing: .green
        case .scenarios: .orange
        case .sync: .cyan
        case .advanced: .gray
        }
    }

    /// Keywords for sidebar search.
    var keywords: [String] {
        switch self {
        case .aiProvider: ["ai", "provider", "model", "key", "claude", "openai", "ollama", "effort", "llm"]
        case .jira: ["jira", "atlassian", "rovo", "mcp", "oauth", "token", "site"]
        case .linear: ["linear", "oauth", "api key", "mcp"]
        case .customMCP: ["custom", "mcp", "endpoint", "server", "self-hosted", "tracker"]
        case .researchTools: ["research", "tools", "mcp", "obsidian", "corellium", "notes", "device", "simulator", "wiki"]
        case .testing: ["testing", "mode", "dev", "qa", "environment", "hosted"]
        case .scenarios: ["scenarios", "journeys", "codebase", "repo", "e2e"]
        case .sync: ["sync", "icloud", "drive", "folder", "devices", "iphone", "ipad", "backup"]
        case .advanced: ["advanced", "default", "tracker", "keychain", "storage", "reset"]
        }
    }

    enum Group: String, CaseIterable {
        case intelligence = "Intelligence"
        case trackers = "Trackers"
        case workspace = "Workspace"
        case app = "App"

        var sections: [SettingsSection] {
            switch self {
            case .intelligence: [.aiProvider, .researchTools(id: nil)]
            case .trackers: [.jira, .linear, .customMCP(id: nil)]
            case .workspace: [.testing, .scenarios]
            case .app: [.sync, .advanced]
            }
        }
    }

    var group: Group {
        switch self {
        case .aiProvider, .researchTools: .intelligence
        case .jira, .linear, .customMCP: .trackers
        case .testing, .scenarios: .workspace
        case .sync, .advanced: .app
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        guard !q.isEmpty else { return true }
        return title.lowercased().contains(q)
            || subtitle.lowercased().contains(q)
            || keywords.contains { $0.contains(q) }
    }
}

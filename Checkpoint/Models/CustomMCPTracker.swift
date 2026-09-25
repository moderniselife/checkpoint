import Foundation

/// A user-added MCP tracker endpoint.
///
/// Modularity contract: any MCP server speaking Streamable HTTP with
/// `tools/list` + `tools/call` works. Checkpoint lists its tools, keeps the
/// read-only ones for planning (see `PlanGenerator.isReadOnly`), and routes
/// tickets to it when the input matches `matchHint`.
///
/// To add a built-in tracker (like Jira/Linear):
/// 1. Add a case to `Tracker`
/// 2. Add a client factory to `AppSettings.makeMCPClient(for:)`
/// 3. Add a `SettingsSection` case + detail pane in `Views/Settings/`
/// For one-off servers, users don't need code changes — they add a
/// CustomMCPTracker in Settings → Trackers → Custom.
struct CustomMCPTracker: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// MCP endpoint, e.g. https://mcp.example.com/mcp
    var endpoint: String
    /// Substring matched against ticket input to route to this tracker (optional).
    var matchHint: String
    /// Also offer this server's read-only tools during plan research (IDEA-065).
    var useForResearch: Bool = false

    init(id: UUID = UUID(), name: String = "", endpoint: String = "", matchHint: String = "", useForResearch: Bool = false) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.matchHint = matchHint
        self.useForResearch = useForResearch
    }

    var displayName: String { name.isEmpty ? (URL(string: endpoint)?.host ?? "Custom tracker") : name }

    /// Keychain account for this tracker's bearer token.
    var keychainAccount: String { "custom-mcp-\(id.uuidString)" }
}

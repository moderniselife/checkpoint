import Foundation

/// A user-added MCP server: either a **tracker** (tickets live there, analyzed like Jira
/// or Linear) or a **research tool** (Obsidian, Corellium, a wiki… the planner may use
/// it while researching). Any server speaking Streamable HTTP with `tools/list` +
/// `tools/call` works.
///
/// Trackers are always read-only. Research tools default to read-only too, but can
/// allow chosen action tools (e.g. "create a virtual iPhone") so a plan can set up its
/// own test environment.
struct CustomMCPTracker: Codable, Identifiable, Hashable, Sendable {
    enum Role: String, Codable, Sendable, CaseIterable { case tracker, research }
    enum ToolAccess: String, Codable, Sendable { case readOnly, chosen }

    var id: UUID
    var name: String
    /// MCP endpoint, e.g. https://mcp.example.com/mcp
    var endpoint: String
    /// Substring matched against ticket input to route to this tracker (optional).
    var matchHint: String
    /// Trackers: also offer read-only tools during research of other tickets.
    /// Research tools: whether they're switched on.
    var useForResearch: Bool = false
    var role: Role = .tracker
    /// What it is and when to use it, told to the AI ("Our test notes vault", "Virtual iPhones").
    var notes: String = ""
    var toolAccess: ToolAccess = .readOnly
    /// With `.chosen`: every tool the planner may call, read or not.
    var allowedTools: Set<String> = []

    init(id: UUID = UUID(), name: String = "", endpoint: String = "", matchHint: String = "",
         useForResearch: Bool = false, role: Role = .tracker, notes: String = "") {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.matchHint = matchHint
        self.useForResearch = useForResearch
        self.role = role
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id, name, endpoint, matchHint, useForResearch, role, notes, toolAccess, allowedTools
    }

    // Servers saved before roles existed were trackers.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        matchHint = try c.decodeIfPresent(String.self, forKey: .matchHint) ?? ""
        useForResearch = try c.decodeIfPresent(Bool.self, forKey: .useForResearch) ?? false
        role = try c.decodeIfPresent(Role.self, forKey: .role) ?? .tracker
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        toolAccess = try c.decodeIfPresent(ToolAccess.self, forKey: .toolAccess) ?? .readOnly
        allowedTools = try c.decodeIfPresent(Set<String>.self, forKey: .allowedTools) ?? []
    }

    var displayName: String {
        name.isEmpty ? (URL(string: endpoint)?.host ?? (role == .research ? "Research tool" : "Custom tracker")) : name
    }

    /// Keychain account for this server's bearer token.
    var keychainAccount: String { "custom-mcp-\(id.uuidString)" }

    /// Whether the planner may call `tool` on this server.
    nonisolated func allows(_ tool: String) -> Bool {
        if role == .research, toolAccess == .chosen { return allowedTools.contains(tool) }
        return PlanGenerator.isReadOnly(tool)
    }
}

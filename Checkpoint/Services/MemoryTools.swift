import Foundation

/// The planner's memory during research: look up corrections and facts saved from earlier
/// plans, and save new lasting facts it confirms. Local tools, offered to both engines like
/// the codebase tools; the store behind them is `AppSettings.memories`.
nonisolated struct MemoryTools: Sendable {
    static let toolNames: Set<String> = ["memory_search", "memory_save"]
    /// A plan may add at most this many memories, so a chatty model can't flood the list.
    static let maxSavesPerRun = 5

    let ticketKey: String
    let canSave: Bool
    let search: @Sendable (String) async -> [PlanMemory]
    let save: @Sendable (_ text: String, _ projectOnly: Bool) async -> PlanMemory?
    private let budget = SaveBudget(left: maxSavesPerRun)

    init(ticketKey: String, canSave: Bool,
         search: @escaping @Sendable (String) async -> [PlanMemory],
         save: @escaping @Sendable (String, Bool) async -> PlanMemory?) {
        self.ticketKey = ticketKey
        self.canSave = canSave
        self.search = search
        self.save = save
    }

    var tools: [MCPClient.Tool] {
        var out: [MCPClient.Tool] = [
            .init(name: "memory_search",
                  description: "Search Checkpoint's memory: corrections and facts saved from earlier test plans (roles and permissions that do or don't exist, environments, test accounts, how features really behave). The ones for this ticket's project are already in your instructions; use this to look further, e.g. by feature or role name.",
                  inputSchema: ["type": "object", "properties": [
                      "query": ["type": "string", "description": "Words to look for. Empty lists everything."],
                  ], "required": []]),
        ]
        if canSave {
            out.append(.init(
                name: "memory_save",
                description: "Save a lasting fact for future test plans, one you confirmed in the tickets or sources: e.g. \"There is no assurance performer role; perform assurance tasks as a Company Admin.\" Never save guesses, details that only matter to this ticket, personal data or secrets. Use sparingly: a few per plan at most.",
                inputSchema: ["type": "object", "properties": [
                    "text": ["type": "string", "description": "The fact, as one or two plain sentences an engineer would write."],
                    "scope": ["type": "string", "enum": ["project", "all"],
                              "description": "project: only this ticket's project. all: every ticket."],
                ], "required": ["text", "scope"]]))
        }
        return out
    }

    func call(_ name: String, _ input: JSONValue) async -> (text: String, isError: Bool) {
        switch name {
        case "memory_search":
            let found = await search(input["query"]?.stringValue ?? "")
            guard !found.isEmpty else { return ("No saved memories match.", false) }
            return (found.prefix(40).map { "- [\($0.scopeLabel)] \($0.text)" }.joined(separator: "\n"), false)
        case "memory_save":
            guard canSave else { return ("Saving memories is turned off.", true) }
            let text = (input["text"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 10 else { return ("Give the fact as a full sentence.", true) }
            guard await budget.take() else { return ("Memory limit for this plan reached; nothing saved.", true) }
            let projectOnly = input["scope"]?.stringValue != "all"
            guard let saved = await save(String(text.prefix(500)), projectOnly) else {
                return ("Already remembered.", false)
            }
            return ("Saved for \(saved.scopeLabel.lowercased()).", false)
        default:
            return ("Unknown memory tool \(name).", true)
        }
    }
}

private actor SaveBudget {
    var left: Int
    init(left: Int) { self.left = left }
    func take() -> Bool {
        guard left > 0 else { return false }
        left -= 1
        return true
    }
}

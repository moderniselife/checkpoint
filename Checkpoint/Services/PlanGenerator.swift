import Foundation

/// Runs the agent loop: Claude decides which Atlassian MCP tools to call,
/// the app executes them against the MCP server, and the final turn is a
/// schema-constrained `TestPlan`.
nonisolated struct PlanGenerator: Sendable {
    enum Event: Sendable {
        case status(String)
        case thinking(String)
        case toolCall(name: String, detail: String)
    }

    enum GeneratorError: LocalizedError {
        case refused(String)
        case truncated
        case tooManyTurns
        case badOutput(String)

        var errorDescription: String? {
            switch self {
            case .refused(let why): return "Claude declined this request. \(why)"
            case .truncated: return "The plan was cut off (max tokens). Try again, or lower effort."
            case .tooManyTurns: return "Gave up after too many research steps. Try a narrower ticket."
            case .badOutput(let why): return "Couldn't read the plan Claude returned: \(why)"
            }
        }
    }

    let claude: ClaudeClient
    let mcp: MCPClient
    let model: String
    let effort: String
    let site: String
    let mode: TestMode
    /// Hosted app URL/name QA tests against (optional).
    let environment: String

    private static let maxTurns = 30
    private static let maxToolResultChars = 120_000

    /// Only read-only Atlassian tools are exposed — Claude can never edit tickets from this app.
    static func isReadOnly(_ name: String) -> Bool {
        let n = name.lowercased()
        return ["get", "search", "fetch", "lookup", "atlassianuserinfo"].contains { n.hasPrefix($0) }
    }

    func run(ticketKey: String, onEvent: @Sendable (Event) async -> Void) async throws -> TestPlan {
        await onEvent(.status("Connecting to Atlassian…"))
        let tools = try await mcp.authenticatedTools()
            .filter { Self.isReadOnly($0.name) }
            .sorted { $0.name < $1.name }
        let toolDefs: [JSONValue] = tools.map {
            var schema = $0.inputSchema
            if case .object(var o) = schema { o["$schema"] = nil; schema = .object(o) }
            return ["name": .string($0.name), "description": .string($0.description), "input_schema": schema]
        }

        let siteLine = site.isEmpty
            ? "The Jira site is unknown — call getAccessibleAtlassianResources first to find the cloudId."
            : "Jira site / cloudId: \(site)"
        var request = "Build the \(mode == .qa ? "QA" : "developer") test brief for Jira ticket \(ticketKey).\n\(siteLine)"
        if mode == .qa, !environment.isEmpty {
            request += "\nHosted environment under test: \(environment). Unless the tickets say otherwise, write the plan for this environment."
        }
        var messages: [JSONValue] = [["role": "user", "content": .string(request)]]

        let usesFallbacks = model.hasPrefix("claude-opus") || model.hasPrefix("claude-fable")
        await onEvent(.status("Reading \(ticketKey)…"))

        for _ in 0..<Self.maxTurns {
            try Task.checkCancellation()
            var body: JSONValue = [
                "model": .string(model),
                "max_tokens": 32000,
                "system": .string(Self.systemPrompt(for: mode)),
                "thinking": ["type": "adaptive", "display": "summarized"],
                "output_config": [
                    "effort": .string(effort),
                    "format": ["type": "json_schema", "schema": TestPlan.jsonSchema],
                ],
                "tools": .array(toolDefs),
                "cache_control": ["type": "ephemeral"],
                "messages": .array(messages),
            ]
            if usesFallbacks, case .object(var o) = body {
                o["fallbacks"] = "default"
                body = .object(o)
            }

            let response = try await claude.createMessage(
                body, betas: usesFallbacks ? ["server-side-fallback-2026-07-01"] : []
            )
            let content = response["content"]?.arrayValue ?? []
            let stopReason = response["stop_reason"]?.stringValue ?? ""

            for block in content where block["type"]?.stringValue == "thinking" {
                if let t = block["thinking"]?.stringValue, !t.isEmpty { await onEvent(.thinking(t)) }
            }

            switch stopReason {
            case "refusal":
                throw GeneratorError.refused(response["stop_details"]?["explanation"]?.stringValue ?? "")
            case "max_tokens":
                throw GeneratorError.truncated
            case "tool_use":
                messages.append(["role": "assistant", "content": .array(content)])
                let calls = content.filter { $0["type"]?.stringValue == "tool_use" }
                for call in calls {
                    await onEvent(.toolCall(name: call["name"]?.stringValue ?? "?", detail: Self.describe(call["input"])))
                }
                let results = await executeAll(calls)
                messages.append(["role": "user", "content": .array(results)])
            default:
                await onEvent(.status("Writing your test plan…"))
                let text = content
                    .filter { $0["type"]?.stringValue == "text" }
                    .compactMap { $0["text"]?.stringValue }
                    .joined()
                do {
                    return try JSONCoding.decoder.decode(TestPlan.self, from: Data(text.utf8))
                } catch {
                    throw GeneratorError.badOutput(error.localizedDescription)
                }
            }
        }
        throw GeneratorError.tooManyTurns
    }

    /// Runs every tool call from one assistant turn concurrently and returns
    /// all results together (one user message keeps parallel tool use working).
    private func executeAll(_ calls: [JSONValue]) async -> [JSONValue] {
        await withTaskGroup(of: (Int, JSONValue).self) { group in
            for (i, call) in calls.enumerated() {
                group.addTask {
                    let id = call["id"]?.stringValue ?? ""
                    let name = call["name"]?.stringValue ?? ""
                    guard Self.isReadOnly(name) else {
                        return (i, Self.toolResult(id, "Tool \(name) is not available (read-only app).", isError: true))
                    }
                    do {
                        let r = try await mcp.callTool(name, arguments: call["input"] ?? [:])
                        var text = r.text
                        if text.count > Self.maxToolResultChars {
                            text = String(text.prefix(Self.maxToolResultChars))
                                + "\n\n[Result truncated at \(Self.maxToolResultChars) characters — request fewer fields or narrower results if more is needed.]"
                        }
                        return (i, Self.toolResult(id, text.isEmpty ? "(empty result)" : text, isError: r.isError))
                    } catch {
                        return (i, Self.toolResult(id, error.localizedDescription, isError: true))
                    }
                }
            }
            var out = [(Int, JSONValue)]()
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func toolResult(_ id: String, _ text: String, isError: Bool) -> JSONValue {
        ["type": "tool_result", "tool_use_id": .string(id), "content": .string(text), "is_error": .bool(isError)]
    }

    /// Short human label for the progress feed, e.g. "PROJ-123" or a JQL / CQL query.
    private static func describe(_ input: JSONValue?) -> String {
        for key in ["issueIdOrKey", "jql", "cql", "query", "pageId", "id", "url"] {
            if let v = input?[key]?.stringValue { return v }
        }
        return ""
    }

    static func systemPrompt(for mode: TestMode) -> String {
        research + (mode == .dev ? devPlan : qaPlan) + shared
    }

    private static let research = """
    You prepare manual test briefs for someone about to verify a Jira ticket. They hate flipping \
    between tabs, so your brief must be the only thing they need open: what changed, what "done" \
    means, and exactly what to do to prove it.

    Research with the Atlassian tools before writing anything:
    - Fetch the ticket with description, comments, issue links, subtasks, parent, labels, components, \
    status and fix versions. Ask for markdown content where the tool supports it.
    - Comments matter. They often hold revised acceptance criteria, triage notes, notes on what was \
    actually changed and where it was deployed, and QA feedback. Later comments override earlier ones.
    - If the ticket is an epic or has subtasks/children (JQL `parent = KEY`), fetch every active child \
    and cover each one — skip children that are closed as superseded or duplicate.
    - Follow the parent epic, linked issues (relates, blocks, replaces, duplicates) and any Confluence \
    pages or specs linked from the ticket, but only as far as they change what needs testing. Don't crawl \
    the whole graph.
    - Batch independent fetches into one turn so they run in parallel.


    """

    private static let devPlan = """
    The reader is the DEVELOPER verifying their own change. Technical detail is welcome: they may \
    check behaviour locally or on a dev deploy, and can look at code, logs, APIs and data.

    Then write the plan:
    - tasks: concrete checks — mostly what to do in the product, plus technical verifications where \
    the tickets call for them (API responses, logs, data, unit/integration tests mentioned by the dev). \
    Order them the way you'd actually run them: setup, happy path, edge cases, then regression checks \
    on adjacent features mentioned in the tickets.
    - preconditions: environment, tenancy/account, roles and permissions, feature flags, test data, and \
    which build/branch/commit/deploy to verify on — whatever the tickets say.
    - summary: two to four plain sentences on what changed technically and why it matters.

    """

    private static let qaPlan = """
    The reader is a QA TESTER doing black-box testing of the HOSTED application in a browser. They \
    have no access to code, repositories, branches, terminals, logs or databases, and they don't run \
    anything locally. Write only what they can see and do in the app.

    Then write the plan:
    - Translate developer language into what a user sees. Refer to screens, menus, buttons, fields, \
    modals and messages by the names shown in the UI, never by component, file, function, endpoint, \
    table or class names. Omit commit hashes, branches, PR numbers and unit tests entirely.
    - tasks: concrete checks performed only through the UI, as a real user of the given role would. \
    Start with a task that confirms the fix is actually on the hosted environment (e.g. the ticket's \
    status, fix version or a deploy comment, or a visible change) before spending time on the rest. \
    Then happy path, negative and edge cases (invalid input, empty states, permissions/roles, \
    refresh and back navigation, long text), then regression checks on nearby features a user would \
    touch in the same flow. Expected results must be observable on screen.
    - preconditions: which hosted environment and tenancy/account to use, which user role(s) to log in \
    as, feature flags that must be on (say who to ask if the tester can't toggle them), and test data \
    to prepare *through the UI* first. If the tickets say the change is not yet deployed to a hosted \
    environment, say so plainly as the first precondition.
    - summary: two to four plain sentences on what changed from a user's point of view and why it matters.
    - Anything that can only be verified technically (database state, API payloads, background jobs, \
    logs) is not a task: put it in openQuestions as something to confirm with the developer.

    """

    private static let shared = """
    For every plan:
    - acceptanceCriteria: quote explicit criteria faithfully (ids like AC1, AC2…) and set source to the \
    ticket key they came from. If a ticket has none, derive them from the description and set source to "derived".
    - Each task has numbered steps, a single observable expected result, the AC ids it covers, and the \
    ticket it belongs to. Every AC should be covered by at least one task.
    - sources: every ticket and page you actually used, with how it relates (this ticket, parent, child, \
    linked, confluence).
    - Never invent product behaviour you didn't read. When something needed for testing is unclear or \
    contradictory, put it in openQuestions instead.
    """
}

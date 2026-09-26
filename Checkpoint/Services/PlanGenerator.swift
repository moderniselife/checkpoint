import Foundation

/// Runs the agent loop: the model decides which tracker MCP tools to call, the
/// app executes them against the MCP server, and the final turn is a `TestPlan`.
/// Two engines share everything but the wire format: Anthropic Messages
/// (Claude + Anthropic-compatible) and OpenAI Chat Completions (OpenAI, Gemini,
/// Grok, OpenRouter, local OpenAI-compatible servers).
nonisolated struct PlanGenerator: Sendable {
    enum Event: Sendable {
        case status(String)
        /// A request to the model started (turn is 1-based).
        case waiting(turn: Int)
        /// Live reasoning / thinking summary for one block of a turn.
        case thinking(turn: Int, index: Int, text: String)
        /// Characters of the final answer (the plan JSON) streamed so far.
        case writing(characters: Int)
        case toolCall(id: String, name: String, detail: String)
        case toolDone(id: String, ok: Bool)
    }

    enum GeneratorError: LocalizedError {
        case refused(String)
        case truncated
        case tooManyTurns
        case badOutput(String)

        var errorDescription: String? {
            switch self {
            case .refused(let why): return "The model declined this request. \(why)"
            case .truncated: return "The plan was cut off (max tokens). Try again, or lower effort."
            case .tooManyTurns: return "Gave up after too many research steps. Try a narrower ticket."
            case .badOutput(let why): return "Couldn't read the plan the model returned: \(why)"
            }
        }
    }

    let llm: LLMConfig
    let mcp: MCPClient
    let site: String
    let mode: TestMode
    let tracker: Tracker
    /// Hosted app URL/name QA tests against (optional).
    let environment: String
    /// Extra MCP servers for research: docs, wikis, vaults, device farms. Each says what it's
    /// for and which of its tools the planner may call.
    var researchSources: [ResearchSource] = []
    /// Display name of the custom tracker when `tracker == .custom`.
    var trackerName: String = ""

    struct ResearchSource: Sendable {
        var name: String
        var notes: String
        var client: MCPClient
        var allows: @Sendable (String) -> Bool
    }
    /// Tool name → owning client, built in run().
    // Internal (not private) so the memberwise initializer stays usable from PlanStore.
    var toolOwners: [String: MCPClient] = [:]
    /// Tool name → the rule for calling it, for research-source tools.
    var toolRules: [String: @Sendable (String) -> Bool] = [:]
    /// Team-wide extra instructions appended to the prompt (IDEA-009).
    var houseRules: String = ""
    /// Forced plan shape (IDEA-010); nil = let the ticket type decide.
    var templateOverride: PlanTemplate? = nil
    /// Optional end-to-end scenarios; `.ticketsAndCode` needs `codebase`.
    var scenarios: ScenarioMode = .off
    /// Read-only local codebase for scenario research.
    var codebase: CodebaseTools? = nil

    /// Scenario mode actually used (falls back to tickets when no codebase is available).
    private var effectiveScenarios: ScenarioMode {
        scenarios == .ticketsAndCode && codebase == nil ? .tickets : scenarios
    }

    private var prompt: String {
        var p = Self.systemPrompt(for: mode, tracker: tracker, template: templateOverride)
            + Self.scenarioPrompt(effectiveScenarios, mode: mode)
        let rules = houseRules.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rules.isEmpty {
            p += "\n\nTeam house rules (always follow):\n\(rules)"
        }
        return p
    }

    private static let maxTurns = 30
    private static let maxToolResultChars = 120_000

    /// Only read-only Atlassian tools are exposed — the model can never edit tickets from this app.
    static func isReadOnly(_ name: String) -> Bool {
        let n = name.lowercased()
        return ["get", "search", "fetch", "lookup", "list", "atlassianuserinfo"].contains { n.hasPrefix($0) }
    }

    /// A tool call in engine-neutral form.
    struct Call: Sendable {
        let id: String
        let name: String
        let input: JSONValue
    }

    struct CallResult: Sendable {
        let id: String
        let text: String
        let isError: Bool
    }

    func run(ticketKey: String, onEvent: @Sendable (Event) async -> Void) async throws -> (plan: TestPlan, usage: LLMUsage) {
        await onEvent(.status("Connecting to \(trackerDisplayName)…"))
        let listed = tracker == .jira ? try await mcp.authenticatedTools() : try await mcp.listTools()
        // Jira and custom trackers: only read tools. Linear: the /mcp/readonly endpoint only
        // lists read tools and the server rejects writes, so keep everything it offers.
        var tools = listed
            .filter { tracker == .linear || Self.isReadOnly($0.name) }
            .sorted { $0.name < $1.name }
        // Research sources: whatever each one allows (read-only unless tools were chosen), failures skipped.
        var owners: [String: MCPClient] = [:]
        var rules: [String: @Sendable (String) -> Bool] = [:]
        for source in researchSources {
            guard let extra = try? await source.client.listTools() else {
                await onEvent(.status("Couldn't reach \(source.name) — researching without it."))
                continue
            }
            for tool in extra where source.allows(tool.name) && !tools.contains(where: { $0.name == tool.name }) {
                tools.append(tool)
                owners[tool.name] = source.client
                rules[tool.name] = source.allows
            }
        }
        var runner = self
        runner.toolOwners = owners
        runner.toolRules = rules
        if effectiveScenarios == .ticketsAndCode { tools += CodebaseTools.tools }
        if scenarios == .ticketsAndCode && codebase == nil {
            await onEvent(.status("No codebase folder set — building scenarios from tickets only."))
        }

        let siteLine: String
        switch tracker {
        case .jira:
            siteLine = site.isEmpty
                ? "The Jira site is unknown — call getAccessibleAtlassianResources first to find the cloudId."
                : "Jira site / cloudId: \(site)"
        case .linear:
            siteLine = "The issue is in Linear."
        case .custom:
            siteLine = "The issue is in \(trackerDisplayName), reached through its MCP tools. Find it by the id or link given (search or list tools if there's no direct get), then read everything linked to it."
        }
        var request = "Build the \(mode == .qa ? "QA" : "developer") test brief for \(trackerDisplayName) issue \(ticketKey).\n\(siteLine)"
        if mode == .qa, !environment.isEmpty {
            request += "\nHosted environment under test: \(environment). Unless the tickets say otherwise, write the plan for this environment."
        }
        if !researchSources.isEmpty {
            request += "\n\nResearch tools you can use as well, beside the tracker:"
            for source in researchSources {
                request += "\n- \(source.name)" + (source.notes.isEmpty ? "" : ": \(source.notes)")
            }
            request += "\nUse them where they help (specs, notes, docs, test devices or environments) and cite what you found in task sources. If any of them can act (create devices, install builds, set up data), only do what this plan's testing needs, and list what you set up under preconditions."
        }

        await onEvent(.status("Reading \(ticketKey) with \(llm.provider.shortLabel)…"))
        switch llm.provider.style {
        case .anthropic: return try await runner.runAnthropic(tools: tools, request: request, onEvent: onEvent)
        case .openAIChat: return try await runner.runOpenAI(tools: tools, request: request, onEvent: onEvent)
        }
    }

    // MARK: - Anthropic Messages engine

    private func runAnthropic(tools: [MCPClient.Tool], request: String,
                              onEvent: @Sendable (Event) async -> Void) async throws -> (TestPlan, LLMUsage) {
        let native = llm.provider == .anthropic
        let claude = ClaudeClient(apiKey: llm.apiKey, baseURL: llm.baseURL, sendBearer: !native)
        var usage = LLMUsage()
        let toolDefs: [JSONValue] = tools.map {
            ["name": .string($0.name), "description": .string($0.description), "input_schema": Self.cleanSchema($0.inputSchema, strict: false)]
        }
        // Compatible servers may not support Claude-only features, so ask for JSON in the prompt instead.
        let system = prompt + (native ? "" : Self.jsonInstruction)
        var messages: [JSONValue] = [["role": "user", "content": .string(request)]]
        let usesFallbacks = native && (llm.model.hasPrefix("claude-opus") || llm.model.hasPrefix("claude-fable"))
        var retriedFinal = false

        for turn in 1...Self.maxTurns {
            try Task.checkCancellation()
            await onEvent(.waiting(turn: turn))
            var body: [String: JSONValue] = [
                "model": .string(llm.model),
                "max_tokens": 32000,
                "system": .string(system),
                "tools": .array(toolDefs),
                "messages": .array(messages),
            ]
            if native {
                body["thinking"] = ["type": "adaptive", "display": "summarized"]
                body["output_config"] = [
                    "effort": .string(llm.effort),
                    "format": ["type": "json_schema", "schema": TestPlan.jsonSchema],
                ]
                body["cache_control"] = ["type": "ephemeral"]
                if usesFallbacks { body["fallbacks"] = "default" }
            }

            // Streamed so thinking and plan-writing progress show live on long epics.
            let (response, thinkingBudgetHit) = try await claude.streamMessage(
                .object(body), betas: usesFallbacks ? ["server-side-fallback-2026-07-01"] : [],
                thinkingBudget: Self.thinkingBudget(for: llm.effort)
            ) { event in
                switch event {
                case .thinking(let index, let text): await onEvent(.thinking(turn: turn, index: index, text: text))
                case .writing(let n): await onEvent(.writing(characters: n))
                }
            }
            usage.add(Self.responseUsage(response))
            let content = response["content"]?.arrayValue ?? []
            let stopReason = response["stop_reason"]?.stringValue ?? ""
            if thinkingBudgetHit && !content.contains(where: { $0["type"]?.stringValue == "tool_use" }) {
                // Cut off mid-yap with nothing actionable: nudge it to wrap up.
                await onEvent(.status("Thinking ran long — wrapping up."))
                if content.isEmpty {
                    messages.append(["role": "assistant", "content": .string("(thinking cut short by budget)")])
                } else {
                    messages.append(["role": "assistant", "content": .array(content)])
                }
                messages.append(["role": "user", "content": .string("Thinking budget spent. Write the plan now with what you have researched.")])
                continue
            }

            switch stopReason {
            case "refusal":
                throw GeneratorError.refused(response["stop_details"]?["explanation"]?.stringValue ?? "")
            case "max_tokens":
                throw GeneratorError.truncated
            case "tool_use":
                messages.append(["role": "assistant", "content": .array(content)])
                let calls = content.filter { $0["type"]?.stringValue == "tool_use" }.map {
                    Call(id: $0["id"]?.stringValue ?? "", name: $0["name"]?.stringValue ?? "", input: $0["input"] ?? [:])
                }
                let results = await executeAll(calls, onEvent: onEvent)
                messages.append(["role": "user", "content": .array(results.map {
                    ["type": "tool_result", "tool_use_id": .string($0.id), "content": .string($0.text), "is_error": .bool($0.isError)]
                })])
            default:
                await onEvent(.status("Writing your test plan…"))
                let text = content
                    .filter { $0["type"]?.stringValue == "text" }
                    .compactMap { $0["text"]?.stringValue }
                    .joined()
                do {
                    return try (Self.decodePlan(text), usage)
                } catch {
                    // Compatible servers can't enforce the schema, and weak models
                    // narrate instead of answering. One stern retry, then fail.
                    guard !native, !retriedFinal else { throw error }
                    retriedFinal = true
                    await onEvent(.status("Answer wasn't usable — asking once more, JSON only…"))
                    messages.append(["role": "assistant", "content": .string(String(text.suffix(4000)))])
                    messages.append(["role": "user", "content": .string("That reply was not a JSON object. " + Self.jsonInstruction)])
                    continue
                }
            }
        }
        throw GeneratorError.tooManyTurns
    }

    // MARK: - OpenAI Chat Completions engine

    /// Research with tools until the model stops calling them, then one final
    /// call (no tools) that writes the plan as JSON. Splitting the phases keeps
    /// this portable: not every provider/model handles tools + a JSON schema at once.
    private func runOpenAI(tools: [MCPClient.Tool], request: String,
                           onEvent: @Sendable (Event) async -> Void) async throws -> (TestPlan, LLMUsage) {
        let client = OpenAIChatClient(provider: llm.provider, apiKey: llm.apiKey, baseURL: llm.baseURL)
        var usage = LLMUsage()
        let strictSchemas = llm.provider == .gemini
        let toolDefs: [JSONValue] = tools.map {
            ["type": "function", "function": [
                "name": .string($0.name),
                "description": .string(String($0.description.prefix(1024))),
                "parameters": Self.cleanSchema($0.inputSchema, strict: strictSchemas),
            ]]
        }
        let researchSystem = prompt + """


        Work in two steps. First, research: call the tools as much as you need (in parallel where you can). \
        When you have everything, reply with a short summary of what you found — don't write the plan yet; \
        you'll be asked for it next.
        """
        var messages: [JSONValue] = [
            ["role": "system", "content": .string(researchSystem)],
            ["role": "user", "content": .string(request)],
        ]

        func body(tools: Bool, final: Bool) -> JSONValue {
            var b: [String: JSONValue] = ["model": .string(llm.model), "messages": .array(messages)]
            b["stream_options"] = ["include_usage": true]
            if tools { b["tools"] = .array(toolDefs); b["parallel_tool_calls"] = true }
            switch llm.provider {
            case .openai: b["max_completion_tokens"] = 32000
            case .openAICompatible: break   // local servers: let the model's own context limit apply
            default: b["max_tokens"] = 32000
            }
            let effort = llm.effort == "xhigh" ? "high" : llm.effort
            switch llm.provider {
            case .openai, .gemini, .xai: b["reasoning_effort"] = .string(effort)
            case .openrouter: b["reasoning"] = ["effort": .string(effort)]
            default: break
            }
            if final {
                b["response_format"] = ["type": "json_schema", "json_schema": [
                    "name": "test_plan", "strict": true,
                    "schema": strictSchemas ? Self.cleanSchema(TestPlan.jsonSchema, strict: true) : TestPlan.jsonSchema,
                ]]
            }
            return .object(b)
        }

        for turn in 1...Self.maxTurns {
            try Task.checkCancellation()
            await onEvent(.waiting(turn: turn))
            let reply = try await client.stream(body(tools: true, final: false),
                                                      generationBudget: Self.thinkingBudget(for: llm.effort)) { event in
                if case .reasoning(let text) = event { await onEvent(.thinking(turn: turn, index: 0, text: text)) }
            }
            usage.add(reply.usage)
            if reply.truncatedByBudget {
                await onEvent(.status("Thinking ran long — moving on with what's gathered."))
            }
            if reply.finishReason == "content_filter" { throw GeneratorError.refused("The provider's content filter blocked it.") }

            guard !reply.toolCalls.isEmpty else {
                // Research done — ask for the plan.
                messages.append(["role": "assistant", "content": .string(reply.text.isEmpty ? "Research complete." : reply.text)])
                messages.append(["role": "user", "content": .string("Now write the test plan." + Self.jsonInstruction)])
                await onEvent(.status("Writing your test plan…"))
                await onEvent(.waiting(turn: turn + 1))
                let final = try await client.stream(body(tools: false, final: true)) { event in
                    switch event {
                    case .reasoning(let text): await onEvent(.thinking(turn: turn + 1, index: 0, text: text))
                    case .writing(let n): await onEvent(.writing(characters: n))
                    }
                }
                usage.add(final.usage)
                if final.finishReason == "length" { throw GeneratorError.truncated }
                do {
                    return try (Self.decodePlan(final.text), usage)
                } catch {
                    // Small/weak models often narrate instead of answering. One stern
                    // retry before failing — bounded, only on the failure path.
                    await onEvent(.status("Answer wasn't usable — asking once more, JSON only…"))
                    messages.append(["role": "assistant", "content": .string(String(final.text.suffix(4000)))])
                    messages.append(["role": "user", "content": .string("That reply was not a JSON object. " + Self.jsonInstruction)])
                    await onEvent(.waiting(turn: turn + 2))
                    let retry = try await client.stream(body(tools: false, final: true)) { event in
                        switch event {
                        case .reasoning(let text): await onEvent(.thinking(turn: turn + 2, index: 0, text: text))
                        case .writing(let n): await onEvent(.writing(characters: n))
                        }
                    }
                    usage.add(retry.usage)
                    if retry.finishReason == "length" { throw GeneratorError.truncated }
                    return try (Self.decodePlan(retry.text), usage)
                }
            }

            messages.append(["role": "assistant",
                             "content": reply.text.isEmpty ? .null : .string(reply.text),
                             "tool_calls": .array(reply.toolCalls.map {
                                 ["id": .string($0.id), "type": "function",
                                  "function": ["name": .string($0.name), "arguments": .string($0.arguments.isEmpty ? "{}" : $0.arguments)]]
                             })])
            let calls = reply.toolCalls.map { tc -> Call in
                let input = (try? JSONCoding.decoder.decode(JSONValue.self, from: Data((tc.arguments.isEmpty ? "{}" : tc.arguments).utf8))) ?? [:]
                return Call(id: tc.id, name: tc.name, input: input)
            }
            for r in await executeAll(calls, onEvent: onEvent) {
                messages.append(["role": "tool", "tool_call_id": .string(r.id),
                                 "content": .string(r.isError ? "ERROR: " + r.text : r.text)])
            }
        }
        throw GeneratorError.tooManyTurns
    }

    // MARK: - Shared

    /// Runs every tool call from one turn concurrently.
    private func executeAll(_ calls: [Call], onEvent: @Sendable (Event) async -> Void) async -> [CallResult] {
        for call in calls {
            await onEvent(.toolCall(id: call.id, name: call.name, detail: Self.describe(call.input)))
        }
        return await withTaskGroup(of: (Int, CallResult).self) { group in
            for (i, call) in calls.enumerated() {
                group.addTask {
                    // Codebase tools run locally, read-only, inside the chosen folder.
                    if CodebaseTools.toolNames.contains(call.name), let codebase {
                        let r = codebase.call(call.name, call.input)
                        return (i, CallResult(id: call.id, text: r.text, isError: r.isError))
                    }
                    let allowed = toolRules[call.name]?(call.name) ?? (tracker == .linear || Self.isReadOnly(call.name))
                    guard allowed else {
                        return (i, CallResult(id: call.id, text: "Tool \(call.name) is not available (read-only app).", isError: true))
                    }
                    do {
                        let owner = toolOwners[call.name] ?? mcp
                        let r = try await owner.callTool(call.name, arguments: call.input)
                        var text = r.text
                        if text.count > Self.maxToolResultChars {
                            text = String(text.prefix(Self.maxToolResultChars))
                                + "\n\n[Result truncated at \(Self.maxToolResultChars) characters — request fewer fields or narrower results if more is needed.]"
                        }
                        return (i, CallResult(id: call.id, text: text.isEmpty ? "(empty result)" : text, isError: r.isError))
                    } catch {
                        return (i, CallResult(id: call.id, text: error.localizedDescription, isError: true))
                    }
                }
            }
            var out = [(Int, CallResult)]()
            for await r in group {
                out.append(r)
                await onEvent(.toolDone(id: r.1.id, ok: !r.1.isError))
            }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Tokens reported by one Anthropic response (`usage` is merged in by `ClaudeClient`).
    static func responseUsage(_ response: JSONValue) -> LLMUsage {
        let u = response["usage"]
        func num(_ v: JSONValue?) -> Int {
            if case .number(let n) = v ?? .null { return Int(n) }
            return 0
        }
        var r = LLMUsage()
        r.add(input: num(u?["input_tokens"]) + num(u?["cache_read_input_tokens"]),
              output: num(u?["output_tokens"]))
        return r
    }

    /// Characters of reasoning + text a research turn may generate before we
    /// cut it off (local models sometimes yap forever instead of acting).
    /// Effort finally means something on local servers too. Final-write
    /// turns are never capped — long plans are legitimate.
    static func thinkingBudget(for effort: String) -> Int {
        switch effort {
        case "low": 20_000
        case "medium": 40_000
        case "xhigh": 150_000
        default: 80_000
        }
    }

    /// Short human label for the progress feed, e.g. "PROJ-123" or a JQL / CQL query.
    private static func describe(_ input: JSONValue?) -> String {
        for key in ["issueIdOrKey", "identifier", "issueId", "jql", "cql", "query", "pageId", "id", "url", "path"] {
            if let v = input?[key]?.stringValue { return v }
        }
        return ""
    }

    /// Appended when the provider can't enforce the schema itself.
    static let jsonInstruction = """


    Respond with ONLY a single JSON object (no prose, no code fences) that matches this JSON Schema exactly:
    \(TestPlan.jsonSchema.compactString)
    """

    /// Decodes a plan, tolerating code fences or prose around the JSON object.
    static func decodePlan(_ text: String) throws -> TestPlan {
        if let plan = try? JSONCoding.decoder.decode(TestPlan.self, from: Data(text.utf8)) { return plan }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw GeneratorError.badOutput(text.isEmpty ? "the reply was empty." : "no JSON object in the reply.")
        }
        do {
            return try JSONCoding.decoder.decode(TestPlan.self, from: Data(text[start...end].utf8))
        } catch {
            throw GeneratorError.badOutput(error.localizedDescription)
        }
    }

    /// Removes `$schema` everywhere; with `strict` (Gemini) keeps only the OpenAPI-style
    /// subset its function calling accepts and turns `["x","null"]` types into `nullable`.
    static func cleanSchema(_ v: JSONValue, strict: Bool) -> JSONValue {
        switch v {
        case .object(var o):
            o["$schema"] = nil
            if strict {
                let allowed: Set<String> = ["type", "properties", "required", "items", "enum", "description",
                                            "nullable", "anyOf", "minimum", "maximum", "minItems", "maxItems", "format"]
                o = o.filter { allowed.contains($0.key) }
                if case .array(let types) = o["type"] ?? .null {
                    let real = types.compactMap(\.stringValue).filter { $0 != "null" }
                    o["type"] = .string(real.first ?? "string")
                    if real.count < types.count { o["nullable"] = true }
                }
                if let f = o["format"]?.stringValue, !["enum", "date-time"].contains(f) { o["format"] = nil }
            }
            var out: [String: JSONValue] = [:]
            for (k, val) in o {
                if k == "properties", case .object(let props) = val {
                    out[k] = .object(props.mapValues { cleanSchema($0, strict: strict) })
                } else if k == "enum" || k == "required" {
                    out[k] = val
                } else {
                    out[k] = cleanSchema(val, strict: strict)
                }
            }
            return .object(out)
        case .array(let a):
            return .array(a.map { cleanSchema($0, strict: strict) })
        default:
            return v
        }
    }

    /// Extra instructions for the optional scenarios section.
    static func scenarioPrompt(_ scenarios: ScenarioMode, mode: TestMode) -> String {
        switch scenarios {
        case .off:
            return "\n\n- scenarios: return an empty array."
        case .tickets, .ticketsAndCode:
            var p = """


            Also write scenarios — 3 to 6 end-to-end journeys a real user would take that exercise this change \
            in context: start before the changed screen and carry on past it, through the neighbouring features \
            the flow naturally touches. Each has a concrete role/persona, a goal, numbered steps and one \
            observable end result. Include at least one journey that combines the change with a neighbouring \
            feature and one unhappy path (wrong role, bad data, interruption). They complement the tasks — don't \
            just repeat them.
            To understand the surrounding flows, look beyond this ticket: search for related tickets (same \
            epic/parent, same components or labels, and recent tickets mentioning the same screens or features) \
            and read a few of the most relevant — don't crawl. List the keys that informed each scenario in \
            relatedTickets.
            """
            if scenarios == .ticketsAndCode {
                p += """

                You also have read-only access to the product's codebase via code_list, code_search and code_read. \
                Use it to find the feature's entry points, routes/screens, permission checks, validations and the \
                neighbouring features the flow passes through, so the journeys match how the product really works.
                """
                if mode == .qa {
                    p += " The reader still can't see code: write every scenario in UI terms (screens, buttons, messages), never file or function names."
                }
            }
            p += "\n- basis: \"tickets\", \"codebase\" or \"tickets+codebase\" — whatever the scenario is actually grounded in."
            return p
        }
    }

    /// Plan shape presets (IDEA-010). Auto lets the ticket type decide.
    nonisolated enum PlanTemplate: String, Codable, Sendable, CaseIterable {
        case auto, bug, feature, epic

        var label: String {
            switch self {
            case .auto: "Auto"
            case .bug: "Bug"
            case .feature: "Feature"
            case .epic: "Epic"
            }
        }

        var instruction: String {
            switch self {
            case .auto: ""
            case .bug:
                "\n\nTemplate: BUG. Lead with exact reproduction steps (environment, data, clicks), then fix verification, then regression on adjacent features. Keep setup minimal."
            case .feature:
                "\n\nTemplate: FEATURE. Lead with the happy path end to end, then roles/permissions, then negative and edge cases. Include a setup task for test data."
            case .epic:
                "\n\nTemplate: EPIC. Keep tasks strictly grouped per child ticket, one group each, in dependency order. Add a final cross-cutting regression task."
            }
        }
    }

    private var trackerDisplayName: String {
        switch tracker {
        case .jira: "Atlassian"
        case .linear: "Linear"
        case .custom: trackerName.isEmpty ? "the tracker" : trackerName
        }
    }

    static func systemPrompt(for mode: TestMode, tracker: Tracker, template: PlanTemplate? = nil) -> String {
        let specifics: String
        switch tracker {
        case .jira: specifics = jiraResearch
        case .linear: specifics = linearResearch
        case .custom: specifics = customResearch
        }
        return research + specifics + (mode == .dev ? devPlan : qaPlan)
            + (template?.instruction ?? "") + shared
    }

    private static let research = """
    You prepare manual test briefs for someone about to verify a ticket from their issue tracker. They hate flipping \
    between tabs, so your brief must be the only thing they need open: what changed, what "done" \
    means, and exactly what to do to prove it.

    Research with the tracker tools before writing anything:
    - Comments matter. They often hold revised acceptance criteria, triage notes, notes on what was \
    actually changed and where it was deployed, and QA feedback. Later comments override earlier ones.
    - If the ticket has children, fetch every active child and cover each one — skip children that are \
    closed as superseded, duplicate or cancelled.
    - Follow the parent, linked/related issues and any specs or documents linked from the ticket, but only \
    as far as they change what needs testing. Don't crawl the whole graph.
    - Batch independent fetches into one turn so they run in parallel.

    """

    private static let jiraResearch = """
    Jira specifics: fetch the ticket with description, comments, issue links, subtasks, parent, labels, \
    components, status and fix versions, asking for markdown content. Epic children come from JQL \
    `parent = KEY`. Specs usually live in linked Confluence pages. Use the ticket key as the source id, and \
    https://<site>/browse/<KEY> as its url.


    """

    private static let linearResearch = """
    Linear specifics: fetch the issue (including its sub-issues, parent, relations, labels, project and \
    cycle), then its comments. Project descriptions and Linear documents often hold the spec. Use the \
    issue identifier (e.g. ENG-123) as the source id and its Linear URL as the url.


    """

    private static let customResearch = """
    Tracker specifics: this is a custom tracker reached through its own MCP tools. Look at the tools \
    you have, fetch the item (and anything it links to: parent, sub-items, comments, attachments or \
    docs), and use the tracker's own id as the source id and its link as the url when there is one.


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
    - ticket: copy the ticket's labels, components and fix versions verbatim, and set parentKey to the \
    parent/epic key when the ticket is a child or sub-task (null otherwise).
    - testData: 2–4 concrete synthetic sample inputs per task (valid, invalid, boundary). Never real user data.
    - estimateMin: realistic manual-testing minutes per task, as a number.
    - sources: for each task, where it came from — ticket key plus kind (ac, comment, page, code or spec) \
    plus ref (the AC id, or a short hint like "deploy comment").
    - Adapt emphasis to the ticket type: bugs lead with reproduction, then fix verification, then regression; \
    features lead with the happy path, then roles/permissions and edge cases; epics keep tasks grouped per child ticket.
    - Each task has numbered steps, a single observable expected result, the AC ids it covers, and the \
    ticket it belongs to. Every AC should be covered by at least one task.
    - sources: every ticket and page you actually used, with how it relates (this ticket, parent, child, \
    linked, confluence).
    - Never invent product behaviour you didn't read. When something needed for testing is unclear or \
    contradictory, put it in openQuestions instead.
    """
}

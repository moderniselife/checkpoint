import Foundation

/// Follow-up chat + section revision over a finished plan (IDEA-083/084).
///
/// V1 answers from the plan itself (no live tracker tools); "update" calls
/// re-issue the full plan JSON with an instruction and merge by ID, so ticks,
/// verdicts, notes and evidence survive.
nonisolated struct ChatMsg: Codable, Sendable, Identifiable, Hashable {
    nonisolated enum Role: String, Codable, Sendable { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
    var at: Date = .now
    /// Set on replies that changed the plan (or tried to), so they don't offer "Update Plan" again.
    /// Optional so chats saved before this still decode.
    var edited: Bool? = nil
}

nonisolated enum PlanChat {
    /// One chat turn: the reply to show, and the plan change to make (empty for a plain answer).
    struct Turn: Sendable {
        var reply: String
        var edit: String
    }

    private static let turnSchema: JSONValue = [
        "type": "object",
        "properties": [
            "reply": ["type": "string"],
            "edit": ["type": "string"],
        ],
        "required": ["reply", "edit"],
        "additionalProperties": false,
    ]

    /// Answers questions and turns change requests into a precise edit instruction.
    /// `history` is the chat so far, so "do the same for the other tasks" works.
    static func respond(plan: TestPlan, history: [ChatMsg], message: String, memories: [String],
                        config: LLMConfig) async throws -> Turn {
        let known = memories.isEmpty ? "" : "\n\nCorrections and facts to keep to:\n" + memories.map { "- \($0)" }.joined(separator: "\n")
        let system = """
        You are the assistant inside Checkpoint, helping a tester with this ticket's test plan (JSON):
        \(planJSON(plan))\(known)

        The tester can ask questions or ask you to change the plan: add, remove, reword or reorder test \
        tasks and their steps or expected results, acceptance criteria, edge cases, preconditions, open \
        questions, scenarios, priorities or areas.

        Reply with one JSON object: {"reply": "...", "edit": "..."}.
        - A question: answer it in "reply" (concise, in terms of the plan and ticket; don't invent product \
        behaviour) and leave "edit" empty.
        - A change request: put a precise, complete instruction for the editor in "edit" (which items, \
        by id or title, and exactly what to change), and a one or two sentence summary of the change in \
        "reply", phrased as done ("Added a task for…").
        - Only edit when the tester asks for a change, not when they ask what you think.
        """
        var turns: [(role: String, text: String)] = history.suffix(12).map { ($0.role == .user ? "user" : "assistant", $0.text) }
        turns.append(("user", message))
        let text = try await complete(system: system, turns: turns, config: config, schema: turnSchema, maxTokens: 4000)
        return parseTurn(text)
    }

    /// The JSON turn, or the whole text as a plain answer when a model ignored the format.
    static func parseTurn(_ text: String) -> Turn {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = [trimmed]
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end {
            candidates.append(String(trimmed[start...end]))
        }
        for c in candidates {
            if let json = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(c.utf8)),
               let reply = json["reply"]?.stringValue {
                return Turn(reply: reply, edit: (json["edit"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return Turn(reply: trimmed, edit: "")
    }

    /// Free-text answer grounded in the plan JSON.
    static func answer(plan: TestPlan, question: String, config: LLMConfig) async throws -> String {
        let system = """
        You are helping test a ticket. Here is the current test plan as JSON:
        \(planJSON(plan))

        Answer the follow-up question concisely, in terms of the plan and ticket. \
        Don't invent product behaviour beyond what the plan and question state.
        """
        return try await complete(system: system, turns: [("user", question)], config: config, schema: nil, maxTokens: 2048)
    }

    /// Full revised plan JSON after an instruction (chat apply or section regen).
    static func revise(plan: TestPlan, instruction: String, config: LLMConfig) async throws -> TestPlan {
        let system = """
        You are editing a manual test plan (JSON, schema below). Return the COMPLETE \
        updated plan as a single JSON object — same shape, same ids for unchanged \
        tasks and criteria, new ids for new ones.
        \(TestPlan.jsonSchema.compactString)

        Current plan:
        \(planJSON(plan))

        Change request: \(instruction)
        """
        let text = try await complete(system: system, turns: [("user", "Return the revised plan JSON now.")], config: config,
                                      schema: TestPlan.jsonSchema, maxTokens: 16000)
        return try PlanGenerator.decodePlan(text)
    }

    // MARK: - Engines

    private static func complete(system: String, turns: [(role: String, text: String)], config: LLMConfig,
                                 schema: JSONValue?, maxTokens: Int) async throws -> String {
        switch config.provider.style {
        case .anthropic:
            let native = config.provider == .anthropic
            let client = ClaudeClient(apiKey: config.apiKey, baseURL: config.baseURL, sendBearer: !native)
            // The API wants turns to alternate, starting with the user.
            var messages: [JSONValue] = []
            for t in turns {
                if messages.isEmpty && t.role == "assistant" { continue }
                if let last = messages.last, last["role"]?.stringValue == t.role, let prev = last["content"]?.stringValue {
                    messages[messages.count - 1] = ["role": .string(t.role), "content": .string(prev + "\n\n" + t.text)]
                } else {
                    messages.append(["role": .string(t.role), "content": .string(t.text)])
                }
            }
            var body: [String: JSONValue] = [
                "model": .string(config.model),
                "max_tokens": .number(Double(maxTokens)),
                "system": .string(system),
                "messages": .array(messages),
            ]
            let traits = ClaudeModelTraits.resolve(model: config.model, mode: config.thinking, effort: config.effort)
            if native, let schema, traits.schema {
                body["output_config"] = ["format": ["type": "json_schema", "schema": schema]]
            }
            do {
                let r = try await client.createMessage(.object(body), betas: [])
                return (r["content"]?.arrayValue ?? []).compactMap { $0["text"]?.stringValue }.joined()
            } catch let error as ClaudeClient.ClaudeError where body["output_config"] != nil
                        && (error.isSchemaTooComplex || traits.adjusted(after: error, model: config.model, effort: config.effort) != nil) {
                // The format was refused: ask for JSON in the instructions instead.
                body["output_config"] = nil
                body["system"] = .string(system + "\n\nReply with only the JSON object, no other text.")
                let r = try await client.createMessage(.object(body), betas: [])
                return (r["content"]?.arrayValue ?? []).compactMap { $0["text"]?.stringValue }.joined()
            }
        case .openAIChat:
            let client = OpenAIChatClient(provider: config.provider, apiKey: config.apiKey, baseURL: config.baseURL)
            let history: [JSONValue] = turns.map { .object(["role": .string($0.role), "content": .string($0.text)]) }
            var b: [String: JSONValue] = [
                "model": .string(config.model),
                "messages": .array([.object(["role": "system", "content": .string(system)])] + history),
            ]
            switch config.provider {
            case .openai: b["max_completion_tokens"] = .number(Double(maxTokens))
            case .openAICompatible: break
            default: b["max_tokens"] = .number(Double(maxTokens))
            }
            if let schema {
                b["response_format"] = ["type": "json_schema", "json_schema": [
                    "name": .string(schema == TestPlan.jsonSchema ? "test_plan" : "chat_turn"), "strict": true, "schema": schema,
                ]]
            }
            return try await client.stream(.object(b)) { _ in }.text
        }
    }

    private static func planJSON(_ plan: TestPlan) -> String {
        (try? String(decoding: JSONCoding.encoder.encode(plan), as: UTF8.self)) ?? ""
    }
}

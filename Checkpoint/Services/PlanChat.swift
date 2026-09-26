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
}

nonisolated enum PlanChat {
    /// Free-text answer grounded in the plan JSON.
    static func answer(plan: TestPlan, question: String, config: LLMConfig) async throws -> String {
        let system = """
        You are helping test a ticket. Here is the current test plan as JSON:
        \(planJSON(plan))

        Answer the follow-up question concisely, in terms of the plan and ticket. \
        Don't invent product behaviour beyond what the plan and question state.
        """
        return try await complete(system: system, user: question, config: config, json: false)
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
        let text = try await complete(system: system, user: "Return the revised plan JSON now.", config: config, json: true)
        return try PlanGenerator.decodePlan(text)
    }

    // MARK: - Engines

    private static func complete(system: String, user: String, config: LLMConfig, json: Bool) async throws -> String {
        switch config.provider.style {
        case .anthropic:
            let native = config.provider == .anthropic
            let client = ClaudeClient(apiKey: config.apiKey, baseURL: config.baseURL, sendBearer: !native)
            var body: [String: JSONValue] = [
                "model": .string(config.model),
                "max_tokens": json ? 16000 : 2048,
                "system": .string(system + (json ? "" : "")),
                "messages": [["role": "user", "content": .string(user)]],
            ]
            if native, json {
                body["output_config"] = ["format": ["type": "json_schema", "schema": TestPlan.jsonSchema]]
            }
            let r = try await client.createMessage(.object(body), betas: [])
            return (r["content"]?.arrayValue ?? []).compactMap { $0["text"]?.stringValue }.joined()
        case .openAIChat:
            let client = OpenAIChatClient(provider: config.provider, apiKey: config.apiKey, baseURL: config.baseURL)
            var b: [String: JSONValue] = [
                "model": .string(config.model),
                "messages": [.object(["role": "system", "content": .string(system)]),
                             .object(["role": "user", "content": .string(user)])],
            ]
            switch config.provider {
            case .openai: b["max_completion_tokens"] = 16000
            case .openAICompatible: break
            default: b["max_tokens"] = 16000
            }
            if json {
                b["response_format"] = ["type": "json_schema", "json_schema": [
                    "name": "test_plan", "strict": true, "schema": TestPlan.jsonSchema,
                ]]
            }
            return try await client.stream(.object(b)) { _ in }.text
        }
    }

    private static func planJSON(_ plan: TestPlan) -> String {
        (try? String(decoding: JSONCoding.encoder.encode(plan), as: UTF8.self)) ?? ""
    }
}

import Foundation

/// OpenAI Chat Completions client (streaming) used for OpenAI, Gemini, Grok,
/// OpenRouter and local OpenAI-compatible servers (Ollama, LM Studio, vLLM…).
nonisolated struct OpenAIChatClient: Sendable {
    enum ChatError: LocalizedError {
        case http(Int, String)
        case stream(String)

        var errorDescription: String? {
            switch self {
            case .http(401, _), .http(403, _): return "The AI provider rejected the API key. Check it in Settings."
            case .http(429, _): return "The AI provider is rate limiting — wait a moment and retry."
            case .http(let code, let body):
                let json = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(body.utf8))
                let msg = json?["error"]?["message"]?.stringValue ?? json?["message"]?.stringValue
                    ?? json?.arrayValue?.first?["error"]?["message"]?.stringValue
                return "AI provider HTTP \(code): \(msg ?? String(body.prefix(300)))"
            case .stream(let m): return "AI provider stream error: \(m)"
            }
        }
    }

    enum StreamEvent: Sendable {
        case reasoning(String)
        case writing(characters: Int)
    }

    /// The assistant turn, reassembled from the stream.
    struct Turn: Sendable {
        var text: String
        var reasoning: String
        var toolCalls: [ToolCall]
        var finishReason: String
    }

    struct ToolCall: Sendable {
        var id: String
        var name: String
        var arguments: String
    }

    let provider: LLMProvider
    let apiKey: String
    let baseURL: String
    /// Parameters this provider/model rejected; skipped on later calls in the same run.
    private let rejected = RejectedKeys()

    init(provider: LLMProvider, apiKey: String, baseURL: String) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 600
        c.timeoutIntervalForResource = 1800
        return URLSession(configuration: c)
    }()

    /// Body keys a provider or model may not support; dropped and retried once on a 400.
    private static let optionalKeys = ["reasoning_effort", "response_format", "max_completion_tokens", "max_tokens",
                                       "parallel_tool_calls", "stream_options"]

    private var root: String { baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL }

    private func request(path: String, method: String = "POST") -> URLRequest {
        var req = URLRequest(url: URL(string: root + path)!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { req.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization") }
        if provider == .openrouter {
            // OpenRouter uses these for app attribution on its leaderboard.
            req.setValue("https://checkpoint.guide", forHTTPHeaderField: "HTTP-Referer")
            req.setValue("Checkpoint", forHTTPHeaderField: "X-Title")
        }
        return req
    }

    /// Streams one chat completion. If the provider rejects an optional parameter
    /// (reasoning effort, JSON schema, token limit…), retries once without them.
    func stream(_ body: JSONValue, onEvent: @Sendable (StreamEvent) async -> Void) async throws -> Turn {
        var body = body
        if case .object(var o) = body {
            rejected.keys.forEach { o[$0] = nil }
            body = .object(o)
        }
        do {
            return try await streamOnce(body, onEvent: onEvent)
        } catch ChatError.http(let code, let text) where code == 400 || code == 422 {
            guard case .object(var o) = body else { throw ChatError.http(code, text) }
            let removable = Self.optionalKeys.filter { o[$0] != nil && $0 != "max_tokens" && $0 != "max_completion_tokens" }
            // Only strip what the error mentions, else everything optional.
            let mentioned = removable.filter { text.contains($0) || (text.contains("json_schema") && $0 == "response_format") }
            let strip = mentioned.isEmpty ? removable : mentioned
            guard !strip.isEmpty else { throw ChatError.http(code, text) }
            strip.forEach { o[$0] = nil }
            // response_format is only sent on the final call, so remember it too.
            rejected.add(strip)
            return try await streamOnce(.object(o), onEvent: onEvent)
        }
    }

    private func streamOnce(_ body: JSONValue, onEvent: @Sendable (StreamEvent) async -> Void) async throws -> Turn {
        var streaming = body
        if case .object(var o) = streaming { o["stream"] = true; streaming = .object(o) }
        var req = request(path: "/chat/completions")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONCoding.encoder.encode(streaming)

        var attempt = 0
        while true {
            let (bytes, response) = try await Self.session.bytes(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return try await assemble(bytes, onEvent: onEvent) }
            var text = ""
            for try await line in bytes.lines { text += line; if text.count > 4000 { break } }
            if [429, 500, 502, 503, 504, 529].contains(status), attempt < 3 {
                attempt += 1
                try await Task.sleep(for: .seconds(Double(attempt * attempt) * 2))
                continue
            }
            throw ChatError.http(status, text)
        }
    }

    private func assemble(_ bytes: URLSession.AsyncBytes, onEvent: @Sendable (StreamEvent) async -> Void) async throws -> Turn {
        var turn = Turn(text: "", reasoning: "", toolCalls: [], finishReason: "")
        var calls: [Int: ToolCall] = [:]
        var lastReported = 0

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let chunk = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(payload.utf8)) else { continue }
            if let err = chunk["error"] {
                throw ChatError.stream(err["message"]?.stringValue ?? err.compactString)
            }
            guard let choice = chunk["choices"]?.arrayValue?.first else { continue }
            let delta = choice["delta"]

            if let t = delta?["content"]?.stringValue, !t.isEmpty {
                turn.text += t
                if turn.text.count - lastReported >= 200 {
                    lastReported = turn.text.count
                    await onEvent(.writing(characters: turn.text.count))
                }
            }
            // Reasoning text, where the provider exposes it (OpenRouter, DeepSeek-style servers…).
            for key in ["reasoning", "reasoning_content"] {
                if let r = delta?[key]?.stringValue, !r.isEmpty {
                    turn.reasoning += r
                    await onEvent(.reasoning(turn.reasoning))
                }
            }
            for tc in delta?["tool_calls"]?.arrayValue ?? [] {
                let index: Int = { if case .number(let n) = tc["index"] ?? .null { return Int(n) }; return calls.count }()
                var call = calls[index] ?? ToolCall(id: "", name: "", arguments: "")
                if let id = tc["id"]?.stringValue, !id.isEmpty { call.id = id }
                if let name = tc["function"]?["name"]?.stringValue, !name.isEmpty { call.name += name }
                if let args = tc["function"]?["arguments"]?.stringValue { call.arguments += args }
                calls[index] = call
            }
            if let reason = choice["finish_reason"]?.stringValue { turn.finishReason = reason }
        }
        turn.toolCalls = calls.keys.sorted().compactMap { i in
            guard var c = calls[i], !c.name.isEmpty else { return nil }
            if c.id.isEmpty { c.id = "call_\(i)_\(UUID().uuidString.prefix(8))" }
            return c
        }
        if turn.text.count != lastReported { await onEvent(.writing(characters: turn.text.count)) }
        return turn
    }

    /// Model ids the provider offers (`GET /models`).
    func listModels() async throws -> [String] {
        var req = request(path: "/models", method: "GET")
        req.setValue(nil, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await Self.session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ChatError.http(status, String(decoding: data, as: UTF8.self)) }
        let json = try JSONCoding.decoder.decode(JSONValue.self, from: data)
        let items = json["data"]?.arrayValue ?? json["models"]?.arrayValue ?? json.arrayValue ?? []
        return items.compactMap { $0["id"]?.stringValue ?? $0["name"]?.stringValue }
            .map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }   // Gemini lists "models/…"
            .sorted()
    }
}

/// Thread-safe set of request keys a provider has rejected during one run.
nonisolated final class RejectedKeys: @unchecked Sendable {
    private let lock = NSLock()
    private var set: Set<String> = []
    var keys: Set<String> { lock.withLock { set } }
    func add(_ k: [String]) { lock.withLock { set.formUnion(k) } }
}

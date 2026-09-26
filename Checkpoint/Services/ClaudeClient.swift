import Foundation

/// Raw-HTTP Messages API client (there is no official Swift SDK).
nonisolated struct ClaudeClient: Sendable {
    enum ClaudeError: LocalizedError {
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .http(401, _): return "Anthropic rejected the API key. Check it in Settings."
            case .http(429, _): return "Anthropic rate limit hit — wait a moment and retry."
            case .http(let code, let body):
                if let msg = (try? JSONCoding.decoder.decode(JSONValue.self, from: Data(body.utf8)))?["error"]?["message"]?.stringValue {
                    return "Claude API \(code): \(msg)"
                }
                return "Claude API \(code): \(body.prefix(300))"
            }
        }
    }

    let apiKey: String
    /// Messages endpoint; points elsewhere for Anthropic-compatible servers (and tests).
    var url = URL(string: "https://api.anthropic.com/v1/messages")!
    /// Anthropic-compatible proxies often expect a Bearer token instead of x-api-key.
    var sendBearer = false

    /// Client for an Anthropic or Anthropic-compatible base URL (e.g. http://localhost:4000).
    init(apiKey: String, baseURL: String = "https://api.anthropic.com", sendBearer: Bool = false) {
        self.apiKey = apiKey
        let root = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.url = URL(string: root + (root.hasSuffix("/v1") ? "/messages" : "/v1/messages"))!
        self.sendBearer = sendBearer
    }

    private func authorize(_ req: inout URLRequest) {
        guard !apiKey.isEmpty else { return }
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        if sendBearer { req.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization") }
    }

    /// Model ids from `GET /v1/models`.
    func listModels() async throws -> [String] {
        var req = URLRequest(url: url.deletingLastPathComponent().appending(path: "models"))
        authorize(&req)
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await Self.session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ClaudeError.http(status, String(decoding: data, as: UTF8.self)) }
        let json = try JSONCoding.decoder.decode(JSONValue.self, from: data)
        return (json["data"]?.arrayValue ?? []).compactMap { $0["id"]?.stringValue }.sorted()
    }
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 600
        c.timeoutIntervalForResource = 900
        return URLSession(configuration: c)
    }()

    func createMessage(_ body: JSONValue, betas: [String]) async throws -> JSONValue {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONCoding.encoder.encode(body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&req)
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if !betas.isEmpty { req.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta") }

        var attempt = 0
        while true {
            let (data, response) = try await Self.session.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return try JSONCoding.decoder.decode(JSONValue.self, from: data) }
            // Retry transient failures (rate limit, overloaded, 5xx) with backoff.
            if [429, 500, 502, 503, 504, 529].contains(status), attempt < 3 {
                attempt += 1
                try await Task.sleep(for: .seconds(Double(attempt * attempt) * 2))
                continue
            }
            throw ClaudeError.http(status, String(decoding: data, as: UTF8.self))
        }
    }

    // MARK: - Streaming

    enum StreamEvent: Sendable {
        /// Summarised thinking text arriving for content block `index`.
        case thinking(index: Int, text: String)
        /// Total characters of answer text so far (the final plan JSON).
        case writing(characters: Int)
    }

    struct StreamError: LocalizedError {
        let message: String
        var errorDescription: String? { "Claude API stream error: \(message)" }
    }

    /// Streams a Messages request over SSE, reporting progress, and returns the
    /// reassembled message (content blocks — including thinking signatures and
    /// tool inputs — exactly as the non-streaming API would return them).
    /// `thinkingBudget` caps thinking characters (local Anthropic-compatible
    /// servers can yap forever); when hit, the turn ends early and the flag
    /// reports it. Answer text is never capped.
    func streamMessage(
        _ body: JSONValue,
        betas: [String],
        thinkingBudget: Int? = nil,
        onEvent: @Sendable (StreamEvent) async -> Void
    ) async throws -> (message: JSONValue, thinkingBudgetHit: Bool) {
        var streamingBody = body
        if case .object(var o) = streamingBody { o["stream"] = true; streamingBody = .object(o) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONCoding.encoder.encode(streamingBody)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        authorize(&req)
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if !betas.isEmpty { req.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta") }

        var attempt = 0
        while true {
            let (bytes, response) = try await Self.session.bytes(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return try await assemble(bytes, thinkingBudget: thinkingBudget, onEvent: onEvent) }
            var body = ""
            for try await line in bytes.lines { body += line; if body.count > 4000 { break } }
            if [429, 500, 502, 503, 504, 529].contains(status), attempt < 3 {
                attempt += 1
                try await Task.sleep(for: .seconds(Double(attempt * attempt) * 2))
                continue
            }
            throw ClaudeError.http(status, body)
        }
    }

    private func assemble(
        _ bytes: URLSession.AsyncBytes,
        thinkingBudget: Int?,
        onEvent: @Sendable (StreamEvent) async -> Void
    ) async throws -> (JSONValue, Bool) {
        var message: [String: JSONValue] = [:]
        var blocks: [Int: [String: JSONValue]] = [:]
        var partialJSON: [Int: String] = [:]
        var textCount = 0
        var thinkingCount = 0
        var lastReported = 0
        var budgetHit = false

        func appendString(_ i: Int, _ key: String, _ add: String) {
            let cur = blocks[i]?[key]?.stringValue ?? ""
            blocks[i, default: [:]][key] = .string(cur + add)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            if budgetHit { break }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let event = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(payload.utf8)) else { continue }
            let index: Int = { if case .number(let n) = event["index"] ?? .null { return Int(n) }; return 0 }()

            switch event["type"]?.stringValue {
            case "message_start":
                if case .object(let m) = event["message"] ?? .null { message = m }
            case "content_block_start":
                if case .object(let b) = event["content_block"] ?? .null { blocks[index] = b }
            case "content_block_delta":
                let delta = event["delta"]
                switch delta?["type"]?.stringValue {
                case "text_delta":
                    let t = delta?["text"]?.stringValue ?? ""
                    appendString(index, "text", t)
                    textCount += t.count
                    if textCount - lastReported >= 200 {
                        lastReported = textCount
                        await onEvent(.writing(characters: textCount))
                    }
                case "thinking_delta":
                    let t = delta?["thinking"]?.stringValue ?? ""
                    thinkingCount += t.count
                    if let budget = thinkingBudget, thinkingCount > budget {
                        budgetHit = true
                        break
                    }
                    appendString(index, "thinking", t)
                    await onEvent(.thinking(index: index, text: blocks[index]?["thinking"]?.stringValue ?? ""))
                case "signature_delta":
                    blocks[index, default: [:]]["signature"] = delta?["signature"] ?? ""
                case "input_json_delta":
                    partialJSON[index, default: ""] += delta?["partial_json"]?.stringValue ?? ""
                default:
                    break   // citations and future delta types don't affect what we echo back
                }
            case "content_block_stop":
                if let json = partialJSON[index] {
                    // Unparseable input becomes {}; the tool call then fails validation and is reported back.
                    blocks[index, default: [:]]["input"] = json.isEmpty ? [:]
                        : ((try? JSONCoding.decoder.decode(JSONValue.self, from: Data(json.utf8))) ?? [:])
                }
            case "message_delta":
                if case .object(let d) = event["delta"] ?? .null {
                    for (k, v) in d { message[k] = v }
                }
                if let usage = event["usage"] { message["usage"] = usage }
            case "error":
                throw StreamError(message: event["error"]?["message"]?.stringValue ?? payload)
            default:
                break
            }
        }
        if textCount != lastReported { await onEvent(.writing(characters: textCount)) }
        message["content"] = .array(blocks.keys.sorted().compactMap { blocks[$0].map(JSONValue.object) })
        return (.object(message), budgetHit)
    }
}

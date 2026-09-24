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
    private static let url = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 600
        c.timeoutIntervalForResource = 900
        return URLSession(configuration: c)
    }()

    func createMessage(_ body: JSONValue, betas: [String]) async throws -> JSONValue {
        var req = URLRequest(url: Self.url)
        req.httpMethod = "POST"
        req.httpBody = try JSONCoding.encoder.encode(body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
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
}

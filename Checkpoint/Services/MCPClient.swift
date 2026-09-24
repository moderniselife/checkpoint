import Foundation

/// Minimal MCP client over Streamable HTTP, enough for tools/list + tools/call
/// against the Atlassian Rovo MCP server with API-token (Basic) auth.
actor MCPClient {
    struct Tool: Sendable {
        let name: String
        let description: String
        let inputSchema: JSONValue
    }

    struct CallResult: Sendable {
        let text: String
        let isError: Bool
    }

    enum MCPError: LocalizedError {
        case http(Int, String)
        case rpc(String)
        case noResponse
        case unauthenticated

        var errorDescription: String? {
            switch self {
            case .http(401, _), .http(403, _), .unauthenticated:
                return "Atlassian rejected the API token. Check the email/token in Settings, and that your org admin has enabled API-token auth for the Rovo MCP server."
            case .http(let code, let body): return "Atlassian MCP HTTP \(code): \(body.prefix(300))"
            case .rpc(let msg): return "Atlassian MCP error: \(msg)"
            case .noResponse: return "Atlassian MCP returned no response."
            }
        }
    }

    static let endpoint = URL(string: "https://mcp.atlassian.com/v1/mcp")!
    private static let protocolVersion = "2025-06-18"

    private let authHeader: String
    private let session: URLSession
    private var sessionID: String?
    private var nextID = 1
    private var initialized = false

    init(authHeader: String) {
        self.authHeader = authHeader
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: config)
    }

    func connect() async throws {
        guard !initialized else { return }
        _ = try await request("initialize", params: [
            "protocolVersion": .string(Self.protocolVersion),
            "capabilities": [:],
            "clientInfo": ["name": "Checkpoint", "version": "0.1.0"],
        ])
        try await notify("notifications/initialized")
        initialized = true
    }

    func listTools() async throws -> [Tool] {
        try await connect()
        var tools: [Tool] = []
        var cursor: String?
        repeat {
            let params: JSONValue = cursor.map { ["cursor": .string($0)] } ?? [:]
            let result = try await request("tools/list", params: params)
            for t in result["tools"]?.arrayValue ?? [] {
                guard let name = t["name"]?.stringValue else { continue }
                tools.append(Tool(
                    name: name,
                    description: t["description"]?.stringValue ?? "",
                    inputSchema: t["inputSchema"] ?? ["type": "object", "properties": [:]]
                ))
            }
            cursor = result["nextCursor"]?.stringValue
        } while cursor != nil
        return tools
    }

    /// Atlassian accepts bad credentials at the handshake and just hides the Jira
    /// tools, so "is getJiraIssue listed" is the real auth check.
    func authenticatedTools() async throws -> [Tool] {
        let tools = try await listTools()
        guard tools.contains(where: { $0.name == "getJiraIssue" }) else { throw MCPError.unauthenticated }
        return tools
    }

    /// Display name of the signed-in Atlassian user, for the Settings connection test.
    func whoAmI() async throws -> String {
        let r = try await callTool("atlassianUserInfo", arguments: [:])
        if r.isError { throw MCPError.rpc(r.text) }
        let info = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(r.text.utf8))
        return info?["name"]?.stringValue ?? info?["email"]?.stringValue ?? "connected"
    }

    func callTool(_ name: String, arguments: JSONValue) async throws -> CallResult {
        try await connect()
        let result = try await request("tools/call", params: ["name": .string(name), "arguments": arguments])
        let text = (result["content"]?.arrayValue ?? []).compactMap { block -> String? in
            if block["type"]?.stringValue == "text" { return block["text"]?.stringValue }
            return block.compactString
        }.joined(separator: "\n")
        return CallResult(text: text, isError: result["isError"]?.boolValue ?? false)
    }

    // MARK: - JSON-RPC transport

    private func notify(_ method: String) async throws {
        _ = try await send(["jsonrpc": "2.0", "method": .string(method)], expectID: nil)
    }

    private func request(_ method: String, params: JSONValue) async throws -> JSONValue {
        let id = nextID
        nextID += 1
        let message: JSONValue = ["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method), "params": params]
        guard let response = try await send(message, expectID: id) else { throw MCPError.noResponse }
        if let err = response["error"] {
            throw MCPError.rpc(err["message"]?.stringValue ?? err.compactString)
        }
        return response["result"] ?? .null
    }

    private func send(_ message: JSONValue, expectID: Int?) async throws -> JSONValue? {
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.httpBody = try JSONCoding.encoder.encode(message)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        if initialized || sessionID != nil {
            req.setValue(Self.protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        }
        if let sessionID { req.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }

        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw MCPError.noResponse }
        if let sid = http.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = sid }

        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines { body += line; if body.count > 2000 { break } }
            throw MCPError.http(http.statusCode, body)
        }
        guard let expectID else { return nil }

        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("text/event-stream") {
            // SSE: events are separated by blank lines; each may carry several data: lines.
            var data = ""
            for try await line in bytes.lines {
                if line.hasPrefix("data:") {
                    data += line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    // `lines` skips blank separators, so try to parse after every data line.
                    if let msg = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(data.utf8)) {
                        data = ""
                        if case .number(let n) = msg["id"] ?? .null, Int(n) == expectID { return msg }
                    }
                }
            }
            throw MCPError.noResponse
        }

        var raw = Data()
        for try await byte in bytes { raw.append(byte) }
        return try JSONCoding.decoder.decode(JSONValue.self, from: raw)
    }
}

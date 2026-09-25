import Foundation

/// Sign-in and connection checks shared by Settings and onboarding.
extension AppSettings {
    /// Atlassian OAuth in the browser, then records who signed in.
    func signInAtlassian() async throws {
        try await MCPOAuth.atlassian.signIn()
        atlassianUser = (try? await makeMCPClient().whoAmI()) ?? "Signed in"
    }

    func signOutAtlassian() {
        Task { await MCPOAuth.atlassian.signOut() }
        atlassianUser = nil
    }

    /// Linear OAuth (read scope), then a best-effort display name.
    func signInLinear() async throws {
        try await MCPOAuth.linear.signIn()
        linearUser = "Signed in"
        let client = makeMCPClient(for: .linear)
        if let tools = try? await client.listTools(), let me = await Self.linearViewerName(client, tools: tools) {
            linearUser = me
        }
    }

    func signOutLinear() {
        Task { await MCPOAuth.linear.signOut() }
        linearUser = nil
    }

    /// Best-effort display name via Linear's `get_user` tool ("me").
    nonisolated static func linearViewerName(_ client: MCPClient, tools: [MCPClient.Tool]) async -> String? {
        guard let tool = tools.first(where: { $0.name == "get_user" }) else { return nil }
        let props = tool.inputSchema["properties"]
        let arg = ["query", "id", "userId"].first { props?[$0] != nil } ?? "query"
        guard let r = try? await client.callTool("get_user", arguments: .object([arg: "me"])), !r.isError,
              let json = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(r.text.utf8)) else { return nil }
        let user = json["user"] ?? json
        return user["displayName"]?.stringValue ?? user["name"]?.stringValue
    }

    /// Sends a tiny prompt to prove the key, URL and model work. Returns the model's reply.
    func testModel() async throws -> String {
        let config = llmConfig
        let reply: String
        switch config.provider.style {
        case .anthropic:
            let client = ClaudeClient(apiKey: config.apiKey, baseURL: config.baseURL, sendBearer: config.provider != .anthropic)
            let r = try await client.createMessage([
                "model": .string(config.model), "max_tokens": 64,
                "messages": [["role": "user", "content": "Reply with just: OK"]],
            ], betas: [])
            reply = (r["content"]?.arrayValue ?? []).compactMap { $0["text"]?.stringValue }.joined()
        case .openAIChat:
            let client = OpenAIChatClient(provider: config.provider, apiKey: config.apiKey, baseURL: config.baseURL)
            reply = try await client.stream([
                "model": .string(config.model),
                "messages": [["role": "user", "content": "Reply with just: OK"]],
            ]) { _ in }.text
        }
        return reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

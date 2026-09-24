import Foundation
import Observation

@Observable
final class AppSettings {
    static let models = ["claude-opus-5", "claude-opus-5-5", "claude-sonnet-5", "claude-fable-5-1"]
    static let efforts = ["low", "medium", "high", "xhigh"]

    enum AtlassianAuth: String, CaseIterable, Identifiable {
        case oauth, apiToken
        var id: Self { self }
        var label: String { self == .oauth ? "Sign in with Atlassian" : "API token" }
    }

    var atlassianAuth: AtlassianAuth { didSet { UserDefaults.standard.set(atlassianAuth.rawValue, forKey: "atlassianAuth") } }
    /// Display name after OAuth sign-in; nil when signed out.
    var atlassianUser: String? { didSet { UserDefaults.standard.set(atlassianUser, forKey: "atlassianUser") } }

    enum LinearAuth: String, CaseIterable, Identifiable {
        case oauth, apiKey
        var id: Self { self }
        var label: String { self == .oauth ? "Sign in with Linear" : "API key" }
    }

    var linearAuth: LinearAuth { didSet { UserDefaults.standard.set(linearAuth.rawValue, forKey: "linearAuth") } }
    var linearAPIKey: String { didSet { Keychain.set(linearAPIKey, for: "linear-api-key") } }
    /// Display name after Linear OAuth sign-in; nil when signed out.
    var linearUser: String? { didSet { UserDefaults.standard.set(linearUser, forKey: "linearUser") } }
    /// Used for bare keys when both trackers are connected (links are auto-detected).
    var defaultTracker: Tracker { didSet { UserDefaults.standard.set(defaultTracker.rawValue, forKey: "defaultTracker") } }

    var anthropicKey: String { didSet { Keychain.set(anthropicKey, for: "anthropic") } }
    var atlassianEmail: String { didSet { UserDefaults.standard.set(atlassianEmail, forKey: "atlassianEmail") } }
    var atlassianToken: String { didSet { Keychain.set(atlassianToken, for: "atlassian") } }
    /// Jira site hostname, e.g. yourcompany.atlassian.net — used as the MCP cloudId.
    var site: String { didSet { UserDefaults.standard.set(site, forKey: "site") } }
    var model: String { didSet { UserDefaults.standard.set(model, forKey: "model") } }
    var effort: String { didSet { UserDefaults.standard.set(effort, forKey: "effort") } }
    var mode: TestMode { didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") } }
    /// Hosted app QA tests against, e.g. "https://app.dev.example.com (DEV)".
    var qaEnvironment: String { didSet { UserDefaults.standard.set(qaEnvironment, forKey: "qaEnvironment") } }

    init() {
        let d = UserDefaults.standard
        anthropicKey = Keychain.get("anthropic") ?? ""
        atlassianToken = Keychain.get("atlassian") ?? ""
        atlassianEmail = d.string(forKey: "atlassianEmail") ?? ""
        site = d.string(forKey: "site") ?? ""
        model = d.string(forKey: "model") ?? "claude-opus-5"
        effort = d.string(forKey: "effort") ?? "high"
        mode = TestMode(rawValue: d.string(forKey: "mode") ?? "") ?? .dev
        qaEnvironment = d.string(forKey: "qaEnvironment") ?? ""
        atlassianAuth = AtlassianAuth(rawValue: d.string(forKey: "atlassianAuth") ?? "") ?? .oauth
        atlassianUser = MCPOAuth.atlassian.isSignedIn ? d.string(forKey: "atlassianUser") ?? "Signed in" : nil
        linearAuth = LinearAuth(rawValue: d.string(forKey: "linearAuth") ?? "") ?? .oauth
        linearAPIKey = Keychain.get("linear-api-key") ?? ""
        linearUser = MCPOAuth.linear.isSignedIn ? d.string(forKey: "linearUser") ?? "Signed in" : nil
        defaultTracker = Tracker(rawValue: d.string(forKey: "defaultTracker") ?? "") ?? .jira
    }

    var isLinearConfigured: Bool {
        switch linearAuth {
        case .oauth: linearUser != nil
        case .apiKey: !linearAPIKey.isEmpty
        }
    }

    func isConfigured(_ tracker: Tracker) -> Bool {
        tracker == .jira ? isAtlassianConfigured : isLinearConfigured
    }

    var connectedTrackers: [Tracker] { Tracker.allCases.filter(isConfigured) }

    /// Tracker for an input: link wins, else the only connected one, else the default.
    func tracker(for input: String) -> Tracker {
        if let t = Tracker.detect(in: input) { return t }
        let connected = connectedTrackers
        return connected.count == 1 ? connected[0] : defaultTracker
    }

    func makeMCPClient(for tracker: Tracker) -> MCPClient {
        tracker == .jira ? makeMCPClient() : makeLinearClient()
    }

    /// Linear's read-only MCP endpoint: the server itself refuses any write.
    private func makeLinearClient() -> MCPClient {
        switch linearAuth {
        case .apiKey:
            let key = linearAPIKey
            return MCPClient(endpoint: MCPClient.linearEndpoint, auth: { "Bearer " + key })
        case .oauth:
            return MCPClient(
                endpoint: MCPClient.linearEndpoint,
                auth: { "Bearer " + (try await MCPOAuth.linear.accessToken()) },
                onUnauthorized: { try await MCPOAuth.linear.forceRefresh() }
            )
        }
    }

    /// Authorization header value for private Linear uploads (images in issues).
    func linearUploadAuth() async -> String? {
        switch linearAuth {
        case .apiKey: return linearAPIKey.isEmpty ? nil : linearAPIKey
        case .oauth: return (try? await MCPOAuth.linear.accessToken()).map { "Bearer " + $0 }
        }
    }

    var isAtlassianConfigured: Bool {
        switch atlassianAuth {
        case .oauth: atlassianUser != nil
        case .apiToken: !atlassianEmail.isEmpty && !atlassianToken.isEmpty
        }
    }

    var isConfigured: Bool { !anthropicKey.isEmpty && (isAtlassianConfigured || isLinearConfigured) }

    /// MCP client wired to whichever Atlassian auth method is selected.
    func makeMCPClient() -> MCPClient {
        switch atlassianAuth {
        case .apiToken:
            let header = "Basic " + Data("\(atlassianEmail):\(atlassianToken)".utf8).base64EncodedString()
            return MCPClient(endpoint: MCPClient.apiTokenEndpoint, auth: { header })
        case .oauth:
            return MCPClient(
                endpoint: MCPClient.oauthEndpoint,
                auth: { "Bearer " + (try await MCPOAuth.atlassian.accessToken()) },
                onUnauthorized: { try await MCPOAuth.atlassian.forceRefresh() }
            )
        }
    }

    /// Normalises "https://foo.atlassian.net/browse/X" or "foo" into "foo.atlassian.net".
    var siteHost: String {
        var s = site.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URL(string: s), let host = url.host { s = host }
        if !s.isEmpty && !s.contains(".") { s += ".atlassian.net" }
        return s
    }
}

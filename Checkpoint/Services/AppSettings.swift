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

    var anthropicKey: String { didSet { Keychain.set(anthropicKey, for: "anthropic") } }
    var atlassianEmail: String { didSet { UserDefaults.standard.set(atlassianEmail, forKey: "atlassianEmail") } }
    var atlassianToken: String { didSet { Keychain.set(atlassianToken, for: "atlassian") } }
    /// Jira site hostname, e.g. yourcompany.atlassian.net — used as the MCP cloudId.
    var site: String { didSet { UserDefaults.standard.set(site, forKey: "site") } }
    var model: String { didSet { UserDefaults.standard.set(model, forKey: "model") } }
    var effort: String { didSet { UserDefaults.standard.set(effort, forKey: "effort") } }

    init() {
        let d = UserDefaults.standard
        anthropicKey = Keychain.get("anthropic") ?? ""
        atlassianToken = Keychain.get("atlassian") ?? ""
        atlassianEmail = d.string(forKey: "atlassianEmail") ?? ""
        site = d.string(forKey: "site") ?? ""
        model = d.string(forKey: "model") ?? "claude-opus-5"
        effort = d.string(forKey: "effort") ?? "high"
        atlassianAuth = AtlassianAuth(rawValue: d.string(forKey: "atlassianAuth") ?? "") ?? .oauth
        atlassianUser = AtlassianOAuth.shared.isSignedIn ? d.string(forKey: "atlassianUser") ?? "Signed in" : nil
    }

    var isAtlassianConfigured: Bool {
        switch atlassianAuth {
        case .oauth: atlassianUser != nil
        case .apiToken: !atlassianEmail.isEmpty && !atlassianToken.isEmpty
        }
    }

    var isConfigured: Bool { !anthropicKey.isEmpty && isAtlassianConfigured }

    /// MCP client wired to whichever Atlassian auth method is selected.
    func makeMCPClient() -> MCPClient {
        switch atlassianAuth {
        case .apiToken:
            let header = "Basic " + Data("\(atlassianEmail):\(atlassianToken)".utf8).base64EncodedString()
            return MCPClient(endpoint: MCPClient.apiTokenEndpoint, auth: { header })
        case .oauth:
            return MCPClient(
                endpoint: MCPClient.oauthEndpoint,
                auth: { "Bearer " + (try await AtlassianOAuth.shared.accessToken()) },
                onUnauthorized: { try await AtlassianOAuth.shared.forceRefresh() }
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

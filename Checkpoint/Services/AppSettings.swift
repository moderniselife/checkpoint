import Foundation
import Observation

@Observable
final class AppSettings {
    static let models = ["claude-opus-5", "claude-opus-5-5", "claude-sonnet-5", "claude-fable-5-1"]
    static let efforts = ["low", "medium", "high", "xhigh"]

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
    }

    var isConfigured: Bool {
        !anthropicKey.isEmpty && !atlassianEmail.isEmpty && !atlassianToken.isEmpty
    }

    var atlassianAuthHeader: String {
        "Basic " + Data("\(atlassianEmail):\(atlassianToken)".utf8).base64EncodedString()
    }

    /// Normalises "https://foo.atlassian.net/browse/X" or "foo" into "foo.atlassian.net".
    var siteHost: String {
        var s = site.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URL(string: s), let host = url.host { s = host }
        if !s.isEmpty && !s.contains(".") { s += ".atlassian.net" }
        return s
    }
}

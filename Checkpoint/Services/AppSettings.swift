import Foundation
import Observation

@Observable
final class AppSettings {
    /// Suggested Claude models (other providers list theirs via "Fetch models").
    static let claudeModels = ["claude-opus-5", "claude-opus-5-5", "claude-sonnet-5", "claude-fable-5-1", "claude-haiku-4-5"]
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

    // MARK: Custom MCP trackers (modular)

    /// User-added MCP endpoints. Built-in trackers (Jira/Linear) stay first-class;
    /// anything else that speaks MCP tools/list + tools/call can be added here
    /// without code changes. Tokens live in the Keychain per tracker id.
    var customTrackers: [CustomMCPTracker] {
        didSet { persistCustomTrackers() }
    }

    // MARK: AI provider

    var provider: LLMProvider { didSet { UserDefaults.standard.set(provider.rawValue, forKey: "llmProvider") } }
    /// Per-provider API keys (Keychain), models and base URLs, so switching providers keeps each one's setup.
    private var llmKeys: [LLMProvider: String] = [:]
    private var llmModels: [String: String] { didSet { UserDefaults.standard.set(llmModels, forKey: "llmModels") } }
    private var llmBaseURLs: [String: String] { didSet { UserDefaults.standard.set(llmBaseURLs, forKey: "llmBaseURLs") } }

    /// API key for the selected provider.
    var llmKey: String {
        get { llmKeys[provider] ?? "" }
        set { llmKeys[provider] = newValue; Keychain.set(newValue, for: provider.keychainAccount) }
    }

    /// Model id for the selected provider.
    var model: String {
        get { llmModels[provider.rawValue] ?? provider.defaultModel }
        set { llmModels[provider.rawValue] = newValue }
    }

    /// Base URL for the selected provider (editable for local/compatible servers).
    var llmBaseURL: String {
        get { provider.hasEditableBaseURL ? (llmBaseURLs[provider.rawValue] ?? provider.defaultBaseURL) : provider.defaultBaseURL }
        set { llmBaseURLs[provider.rawValue] = newValue }
    }

    var isLLMConfigured: Bool {
        !model.trimmingCharacters(in: .whitespaces).isEmpty
            && (!provider.requiresKey || !llmKey.isEmpty)
            && URL(string: llmBaseURL)?.scheme != nil
    }

    var llmConfig: LLMConfig {
        LLMConfig(provider: provider, apiKey: llmKey, baseURL: llmBaseURL,
                  model: model.trimmingCharacters(in: .whitespaces), effort: effort)
    }
    var atlassianEmail: String { didSet { UserDefaults.standard.set(atlassianEmail, forKey: "atlassianEmail") } }
    var atlassianToken: String { didSet { Keychain.set(atlassianToken, for: "atlassian") } }
    /// Jira site hostname, e.g. yourcompany.atlassian.net — used as the MCP cloudId.
    var site: String { didSet { UserDefaults.standard.set(site, forKey: "site") } }
    var effort: String { didSet { UserDefaults.standard.set(effort, forKey: "effort") } }
    var mode: TestMode { didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") } }
    /// Optional end-to-end scenario generation.
    var scenarioMode: ScenarioMode { didSet { UserDefaults.standard.set(scenarioMode.rawValue, forKey: "scenarioMode") } }
    /// Security-scoped bookmark to a local codebase (read-only) for scenario research.
    var codebaseBookmark: Data? { didSet { UserDefaults.standard.set(codebaseBookmark, forKey: "codebaseBookmark") } }
    var codebasePath: String? { didSet { UserDefaults.standard.set(codebasePath, forKey: "codebasePath") } }
    /// Hosted app QA tests against, e.g. "https://app.dev.example.com (DEV)".
    var qaEnvironment: String { didSet { UserDefaults.standard.set(qaEnvironment, forKey: "qaEnvironment") } }
    /// Team-wide instructions appended to every generation prompt (IDEA-009).
    var houseRules: String { didSet { UserDefaults.standard.set(houseRules, forKey: "houseRules") } }
    /// Cheaper model for Quick plans (IDEA-082); empty = same model at low effort.
    var quickModel: String { didSet { UserDefaults.standard.set(quickModel, forKey: "quickModel") } }

    init() {
        let d = UserDefaults.standard
        provider = LLMProvider(rawValue: d.string(forKey: "llmProvider") ?? "") ?? .anthropic
        var models = d.dictionary(forKey: "llmModels") as? [String: String] ?? [:]
        // Carry over the model chosen before multi-provider support.
        if models[LLMProvider.anthropic.rawValue] == nil, let old = d.string(forKey: "model") {
            models[LLMProvider.anthropic.rawValue] = old
        }
        llmModels = models
        llmBaseURLs = d.dictionary(forKey: "llmBaseURLs") as? [String: String] ?? [:]
        llmKeys = Dictionary(uniqueKeysWithValues: LLMProvider.allCases.compactMap { p in
            Keychain.get(p.keychainAccount).map { (p, $0) }
        })
        atlassianToken = Keychain.get("atlassian") ?? ""
        atlassianEmail = d.string(forKey: "atlassianEmail") ?? ""
        site = d.string(forKey: "site") ?? ""
        effort = d.string(forKey: "effort") ?? "high"
        mode = TestMode(rawValue: d.string(forKey: "mode") ?? "") ?? .dev
        scenarioMode = ScenarioMode(rawValue: d.string(forKey: "scenarioMode") ?? "") ?? .off
        codebaseBookmark = d.data(forKey: "codebaseBookmark")
        codebasePath = d.string(forKey: "codebasePath")
        qaEnvironment = d.string(forKey: "qaEnvironment") ?? ""
        houseRules = d.string(forKey: "houseRules") ?? ""
        quickModel = d.string(forKey: "quickModel") ?? ""
        atlassianAuth = AtlassianAuth(rawValue: d.string(forKey: "atlassianAuth") ?? "") ?? .oauth
        atlassianUser = MCPOAuth.atlassian.isSignedIn ? d.string(forKey: "atlassianUser") ?? "Signed in" : nil
        linearAuth = LinearAuth(rawValue: d.string(forKey: "linearAuth") ?? "") ?? .oauth
        linearAPIKey = Keychain.get("linear-api-key") ?? ""
        linearUser = MCPOAuth.linear.isSignedIn ? d.string(forKey: "linearUser") ?? "Signed in" : nil
        defaultTracker = Tracker(rawValue: d.string(forKey: "defaultTracker") ?? "") ?? .jira
        customTrackers = Self.loadCustomTrackers()
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

    var isConfigured: Bool { isLLMConfigured && (isAtlassianConfigured || isLinearConfigured) }

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

    // MARK: Custom MCP trackers

    private static func loadCustomTrackers() -> [CustomMCPTracker] {
        guard let data = UserDefaults.standard.data(forKey: "customTrackers"),
              let list = try? JSONCoding.decoder.decode([CustomMCPTracker].self, from: data) else { return [] }
        return list
    }

    private func persistCustomTrackers() {
        UserDefaults.standard.set(try? JSONCoding.encoder.encode(customTrackers), forKey: "customTrackers")
    }

    func customToken(for tracker: CustomMCPTracker) -> String {
        Keychain.get(tracker.keychainAccount) ?? ""
    }

    func setCustomToken(_ token: String, for tracker: CustomMCPTracker) {
        Keychain.set(token, for: tracker.keychainAccount)
    }

    func addCustomTracker(name: String, endpoint: String, matchHint: String = "", token: String = "") {
        let t = CustomMCPTracker(name: name, endpoint: endpoint, matchHint: matchHint)
        // Token goes to Keychain, not UserDefaults.
        customTrackers.append(t)
        if !token.isEmpty { Keychain.set(token, for: t.keychainAccount) }
    }

    func updateCustomTracker(_ tracker: CustomMCPTracker) {
        guard let i = customTrackers.firstIndex(where: { $0.id == tracker.id }) else { return }
        customTrackers[i] = tracker
    }

    func removeCustomTracker(_ tracker: CustomMCPTracker) {
        customTrackers.removeAll { $0.id == tracker.id }
        Keychain.set("", for: tracker.keychainAccount)
    }

    /// Generic MCP client for a custom tracker. Auth is a bearer token when set,
    /// otherwise no header — some local servers need none.
    func makeMCPClient(forCustom tracker: CustomMCPTracker) -> MCPClient? {
        guard let url = URL(string: tracker.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil else { return nil }
        let account = tracker.keychainAccount
        return MCPClient(endpoint: url, auth: {
            let token = Keychain.get(account) ?? ""
            return token.isEmpty ? "" : "Bearer " + token
        })
    }

    /// Route free-form input to a custom tracker via its match hint.
    func customTracker(for input: String) -> CustomMCPTracker? {
        let s = input.lowercased()
        return customTrackers.first { t in
            !t.matchHint.isEmpty && s.contains(t.matchHint.lowercased())
        }
    }
}

// MARK: - Codebase folder (scenario research)

#if os(macOS)
import AppKit

extension AppSettings {
    /// Reading a local repo is a Mac feature; iOS keeps scenarios to tracker data.
    static let supportsCodebase = true

    /// Lets the user pick a repo folder; stores a read-only security-scoped bookmark.
    func chooseCodebase() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Codebase"
        panel.message = "Checkpoint reads this folder (read-only) to build realistic test scenarios."
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                               includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        codebaseBookmark = data
        codebasePath = url.path
    }

    func clearCodebase() {
        codebaseBookmark = nil
        codebasePath = nil
        if scenarioMode == .ticketsAndCode { scenarioMode = .tickets }
    }

    /// Resolves the bookmark and starts security-scoped access; call `stopAccessingSecurityScopedResource()` when done.
    func openCodebase() -> URL? {
        guard let data = codebaseBookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                    includingResourceValuesForKeys: nil, relativeTo: nil) {
            codebaseBookmark = fresh
        }
        return url
    }
}
#else
extension AppSettings {
    static let supportsCodebase = false
    func chooseCodebase() {}
    func clearCodebase() {
        codebaseBookmark = nil
        codebasePath = nil
        if scenarioMode == .ticketsAndCode { scenarioMode = .tickets }
    }
    func openCodebase() -> URL? { nil }
}
#endif

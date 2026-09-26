import Foundation
import Observation

/// Drives the ticket side panel: which ticket is open, a back stack for
/// hopping between linked tickets, and a cache of fetched details.
@Observable
final class TicketInspector {
    enum LoadState {
        case loading
        case loaded(TicketDetail)
        case failed(String)
        /// The built-in sample plan's ticket: nothing to fetch.
        case sample
    }

    struct Ref: Hashable {
        var key: String
        var tracker: Tracker
        var cacheKey: String { "\(tracker.rawValue):\(key)" }
    }

    /// Open tickets, shown as floating glass tabs above the panel.
    private(set) var tabs: [Ref] = [] { didSet { persistTabs() } }
    private(set) var active: Ref? { didSet { persistTabs() } }
    /// The panel can be hidden while its tabs stay open.
    private(set) var isVisible = false
    private(set) var states: [String: LoadState] = [:]
    /// Previously active tabs, most recent last — drives Back.
    private var history: [Ref] = []
    private var settings: AppSettings?

    var current: Ref? { isVisible ? active : nil }
    var currentKey: String? { current?.key }
    var currentState: LoadState? { current.flatMap { states[$0.cacheKey] } }
    var isOpen: Bool { isVisible && active != nil }
    var canGoBack: Bool { history.contains(where: tabs.contains) }

    func attach(_ settings: AppSettings) {
        self.settings = settings
        restoreTabs()
    }

    func state(for ref: Ref) -> LoadState? { states[ref.cacheKey] }

    /// Opens (or switches to) a ticket's tab and shows the panel. `push` opens it
    /// right after the current tab, e.g. when following a linked issue.
    func open(_ key: String, tracker: Tracker = .jira, push: Bool = false) {
        let ref = Ref(key: key.uppercased(), tracker: tracker)
        if !tabs.contains(ref) {
            if push, let a = active, let i = tabs.firstIndex(of: a) { tabs.insert(ref, at: i + 1) } else { tabs.append(ref) }
        }
        activate(ref)
        isVisible = true
    }

    func activate(_ ref: Ref, recordHistory: Bool = true) {
        if recordHistory, let a = active, a != ref { history.append(a) }
        active = ref
        isVisible = true
        if states[ref.cacheKey] == nil { load(ref) }
    }

    /// Toggle used by the toolbar button and ⌘I.
    func toggle(_ key: String, tracker: Tracker) {
        if isOpen && active == Ref(key: key.uppercased(), tracker: tracker) { close() } else { open(key, tracker: tracker) }
    }

    /// Back = the previously active tab that's still open.
    func back() {
        while let prev = history.popLast() {
            if tabs.contains(prev) { activate(prev, recordHistory: false); return }
        }
    }

    func closeTab(_ ref: Ref) {
        guard let i = tabs.firstIndex(of: ref) else { return }
        tabs.remove(at: i)
        history.removeAll { $0 == ref }
        if active == ref {
            if let prev = history.last(where: tabs.contains) {
                history.removeAll { $0 == prev }
                activate(prev, recordHistory: false)
            } else if !tabs.isEmpty {
                activate(tabs[min(i, tabs.count - 1)], recordHistory: false)
            } else {
                active = nil
                isVisible = false
            }
        }
    }

    func closeOtherTabs(_ ref: Ref) {
        tabs = tabs.filter { $0 == ref }
        history = []
        activate(ref, recordHistory: false)
    }

    /// ⌃Tab / ⌃⇧Tab.
    func cycle(_ step: Int) {
        guard !tabs.isEmpty else { return }
        let i = active.flatMap(tabs.firstIndex(of:)) ?? 0
        activate(tabs[(i + step + tabs.count) % tabs.count])
    }

    /// Hides the panel; tabs stay open.
    func close() { isVisible = false }

    private func persistTabs() {
        UserDefaults.standard.set(tabs.map(\.cacheKey), forKey: "openTicketTabs")
        UserDefaults.standard.set(active?.cacheKey, forKey: "activeTicketTab")
    }

    private func restoreTabs() {
        func ref(_ s: String) -> Ref? {
            let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let t = Tracker(rawValue: parts[0]) else { return nil }
            return Ref(key: parts[1], tracker: t)
        }
        let saved = (UserDefaults.standard.stringArray(forKey: "openTicketTabs") ?? []).compactMap(ref)
        guard !saved.isEmpty, tabs.isEmpty else { return }
        // Read before assigning: setting `tabs` persists and would overwrite the saved active tab.
        let savedActive = UserDefaults.standard.string(forKey: "activeTicketTab").flatMap(ref)
        tabs = saved
        // Restored hidden; the active tab loads when the panel is next shown.
        active = savedActive.flatMap { saved.contains($0) ? $0 : nil } ?? saved.first
    }

    /// Shows the panel on the active tab (e.g. ⌘I with no ticket in view).
    func show() {
        guard let a = active else { return }
        activate(a, recordHistory: false)
    }

    func refresh() { if let current { load(current) } }

    private func load(_ ref: Ref) {
        if ref.key.uppercased() == SamplePlan.key {
            states[ref.cacheKey] = .sample
            return
        }
        if ref.tracker == .custom {
            states[ref.cacheKey] = .failed("Ticket details aren't available for custom trackers. Open the ticket in its own app.")
            return
        }
        guard let settings, settings.isConfigured(ref.tracker) else {
            states[ref.cacheKey] = .failed("Connect \(ref.tracker.label) in \(Platform.settingsName) to view its issues.")
            return
        }
        states[ref.cacheKey] = .loading
        let mcp = settings.makeMCPClient(for: ref.tracker)
        let site = settings.siteHost
        Task {
            do {
                let detail = ref.tracker == .jira
                    ? try await Self.loadJira(ref.key, site: site, mcp: mcp)
                    : try await Self.loadLinear(ref.key, mcp: mcp)
                states[ref.cacheKey] = .loaded(detail)
            } catch {
                states[ref.cacheKey] = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated private static func loadJira(_ key: String, site: String, mcp: MCPClient) async throws -> TicketDetail {
        let cloudID = try await resolveCloudID(site: site, mcp: mcp)
        let result = try await mcp.callTool("getJiraIssue", arguments: [
            "cloudId": .string(cloudID),
            "issueIdOrKey": .string(key),
            "fields": ["*all"],
            // ADF + renderedFields keep inline images resolvable to attachment IDs;
            // the markdown format drops or blob-ifies them.
            "expand": "names,changelog,renderedFields",
            "responseContentFormat": "adf",
        ])
        if result.isError { throw TicketDetail.ParseError.notFound(result.text) }
        let raw = try JSONCoding.decoder.decode(JSONValue.self, from: Data(result.text.utf8))
        var detail = try TicketDetail.parse(raw)
        // Epic children are linked by `parent`, not listed in `subtasks` — ask for them explicitly.
        let subtaskKeys = Set(detail.subtasks.map(\.key))
        detail.children = (await jiraChildren(of: detail.key, cloudID: cloudID, mcp: mcp))
            .filter { !subtaskKeys.contains($0.key) }
        return detail
    }

    /// Every issue with `parent = key`, following pagination (epics can have hundreds).
    nonisolated private static func jiraChildren(of key: String, cloudID: String, mcp: MCPClient) async -> [TicketDetail.LinkedIssue] {
        var out: [TicketDetail.LinkedIssue] = []
        var token: String?
        for _ in 0..<10 {   // up to 1,000 children
            var args: [String: JSONValue] = [
                "cloudId": .string(cloudID),
                "jql": .string("parent = \(key) ORDER BY rank, key"),
                "fields": ["summary", "status", "issuetype"],
                "maxResults": 100,
            ]
            if let token { args["nextPageToken"] = .string(token) }
            guard let r = try? await mcp.callTool("searchJiraIssuesUsingJql", arguments: .object(args)), !r.isError,
                  let json = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(r.text.utf8)) else { break }
            let nodes = json["issues"]?["nodes"]?.arrayValue ?? json["issues"]?.arrayValue ?? []
            out += nodes.compactMap { n in
                guard let k = n["key"]?.stringValue else { return nil }
                let f = n["fields"]
                return .init(key: k, summary: f?["summary"]?.stringValue ?? "",
                             status: f?["status"]?["name"]?.stringValue ?? "",
                             type: f?["issuetype"]?["name"]?.stringValue ?? "",
                             relation: f?["issuetype"]?["name"]?.stringValue.map { $0.lowercased() } ?? "child",
                             category: f?["status"]?["statusCategory"]?["key"]?.stringValue ?? "")
            }
            let info = json["issues"]?["pageInfo"] ?? json["pageInfo"]
            guard info?["hasNextPage"]?.boolValue == true,
                  let next = info?["endCursor"]?.stringValue ?? json["nextPageToken"]?.stringValue else { break }
            token = next
        }
        return out
    }

    /// Linear's tool argument names aren't documented, so pick them from each tool's schema.
    nonisolated private static func loadLinear(_ key: String, mcp: MCPClient) async throws -> TicketDetail {
        let tools = try await mcp.listTools()
        func arg(_ tool: String, _ candidates: [String]) -> String {
            let props = tools.first { $0.name == tool }?.inputSchema["properties"]
            return candidates.first { props?[$0] != nil } ?? candidates[0]
        }
        guard tools.contains(where: { $0.name == "get_issue" }) else {
            throw TicketDetail.ParseError.notFound("Linear didn't offer a get_issue tool.")
        }
        let issue = try await mcp.callTool("get_issue", arguments: .object([arg("get_issue", ["id", "issueId", "identifier"]): .string(key)]))
        if issue.isError { throw TicketDetail.ParseError.notFound(issue.text) }

        var comments: MCPClient.CallResult?
        if tools.contains(where: { $0.name == "list_comments" }) {
            comments = try? await mcp.callTool("list_comments", arguments: .object([arg("list_comments", ["issueId", "id", "issue"]): .string(key)]))
        }
        var detail = TicketDetail.parseLinear(key: key, issue: issue.text, comments: comments?.isError == false ? comments?.text : nil)

        // Sub-issues aren't always embedded; ask list_issues for children when it supports a parent filter.
        if detail.subtasks.isEmpty, let list = tools.first(where: { $0.name == "list_issues" }),
           let parentArg = ["parentId", "parent"].first(where: { list.inputSchema["properties"]?[$0] != nil }) {
            let issueID = (try? JSONCoding.decoder.decode(JSONValue.self, from: Data(issue.text.utf8)))
                .flatMap { ($0["issue"] ?? $0)["id"]?.stringValue } ?? key
            if let r = try? await mcp.callTool("list_issues", arguments: .object([parentArg: .string(issueID)])), !r.isError,
               let json = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(r.text.utf8)) {
                let items = json.arrayValue ?? json["issues"]?.arrayValue ?? json["nodes"]?.arrayValue ?? []
                detail.subtasks = items.compactMap { item in
                    guard let k = item["identifier"]?.stringValue else { return nil }
                    let state = item["state"] ?? item["status"]
                    return .init(key: k, summary: item["title"]?.stringValue ?? "",
                                 status: state?.stringValue ?? state?["name"]?.stringValue ?? "",
                                 type: "", relation: "sub-issue")
                }
            }
        }
        return detail
    }

    nonisolated static func resolveCloudID(site: String, mcp: MCPClient) async throws -> String {
        if !site.isEmpty { return site }
        let r = try await mcp.callTool("getAccessibleAtlassianResources", arguments: [:])
        let json = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(r.text.utf8))
        let first = json?.arrayValue?.first ?? json?["resources"]?.arrayValue?.first
        guard let id = first?["id"]?.stringValue else {
            throw TicketDetail.ParseError.notFound("Set your Jira site in Settings.")
        }
        return id
    }
}

/// Loads attachment images. Jira needs auth for these, so try (1) API-token Basic
/// auth against the site, then (2) the OAuth token against the gateway URL.
actor AttachmentLoader {
    static let shared = AttachmentLoader()

    struct Credentials: Sendable {
        var site: String
        var basicHeader: String?
        var useOAuth: Bool
        var linearAPIKey: String?
        var linearOAuth: Bool
    }

    private var cache: [String: Data] = [:]

    func data(for attachment: TicketDetail.Attachment, full: Bool, creds: Credentials) async -> Data? {
        let cacheKey = attachment.id + (full ? "-full" : "-thumb")
        if let d = cache[cacheKey] { return d }
        let kind = full ? "content" : "thumbnail"

        var attempts: [(URL, String)] = []
        // Linear files: private uploads that take the API key or the OAuth bearer.
        if let url = attachment.contentURL, url.host()?.hasSuffix("uploads.linear.app") == true {
            if let key = creds.linearAPIKey { attempts.append((url, key)) }
            if creds.linearOAuth, let token = try? await MCPOAuth.linear.accessToken() {
                attempts.append((url, "Bearer " + token))
            }
            return await fetch(attempts, cacheKey: cacheKey)
        }

        if let basic = creds.basicHeader, !creds.site.isEmpty,
           let url = URL(string: "https://\(creds.site)/rest/api/3/attachment/\(kind)/\(attachment.id)?redirect=false") {
            attempts.append((url, basic))
        }
        if creds.useOAuth, let token = try? await MCPOAuth.atlassian.accessToken(),
           let base = full ? attachment.contentURL : (attachment.thumbnailURL ?? attachment.contentURL),
           let url = URL(string: base.absoluteString + "?redirect=false") {
            attempts.append((url, "Bearer " + token))
        }

        return await fetch(attempts, cacheKey: cacheKey)
    }

    private func fetch(_ attempts: [(URL, String)], cacheKey: String) async -> Data? {
        for (url, auth) in attempts {
            var req = URLRequest(url: url)
            req.setValue(auth, forHTTPHeaderField: "Authorization")
            req.setValue("image/*", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: req),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  PlatformImage(data: data) != nil else { continue }
            cache[cacheKey] = data
            return data
        }
        return nil
    }
}

extension AppSettings {
    var attachmentCredentials: AttachmentLoader.Credentials {
        let hasToken = !atlassianEmail.isEmpty && !atlassianToken.isEmpty
        return .init(
            site: siteHost,
            basicHeader: hasToken
                ? "Basic " + Data("\(atlassianEmail):\(atlassianToken)".utf8).base64EncodedString()
                : nil,
            useOAuth: atlassianUser != nil,
            linearAPIKey: linearAuth == .apiKey && !linearAPIKey.isEmpty ? linearAPIKey : nil,
            linearOAuth: linearAuth == .oauth && linearUser != nil
        )
    }

    /// Browser URL for an attachment — the browser's own Jira session handles auth.
    func browserURL(for attachment: TicketDetail.Attachment) -> URL? {
        if attachment.contentURL?.host()?.hasSuffix("linear.app") == true { return attachment.contentURL }
        guard !siteHost.isEmpty else { return attachment.contentURL }
        return URL(string: "https://\(siteHost)/rest/api/3/attachment/content/\(attachment.id)")
    }

    func browseURL(for key: String) -> URL? {
        URL(string: "https://\(siteHost.isEmpty ? "atlassian.net" : siteHost)/browse/\(key)")
    }
}

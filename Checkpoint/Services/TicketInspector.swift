import AppKit
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
    }

    struct Ref: Hashable {
        var key: String
        var tracker: Tracker
        var cacheKey: String { "\(tracker.rawValue):\(key)" }
    }

    private(set) var stack: [Ref] = []
    private(set) var states: [String: LoadState] = [:]
    private var settings: AppSettings?

    var current: Ref? { stack.last }
    var currentKey: String? { stack.last?.key }
    var currentState: LoadState? { current.flatMap { states[$0.cacheKey] } }
    var isOpen: Bool { !stack.isEmpty }
    var canGoBack: Bool { stack.count > 1 }

    func attach(_ settings: AppSettings) { self.settings = settings }

    /// Opens a ticket; from inside the panel it pushes so Back returns to where you were.
    func open(_ key: String, tracker: Tracker = .jira, push: Bool = false) {
        let ref = Ref(key: key.uppercased(), tracker: tracker)
        if push, stack.last != ref { stack.append(ref) } else if !push { stack = [ref] }
        if states[ref.cacheKey] == nil { load(ref) }
    }

    /// Toggle used by the toolbar button and ⌘I.
    func toggle(_ key: String, tracker: Tracker) {
        if current == Ref(key: key.uppercased(), tracker: tracker) { close() } else { open(key, tracker: tracker) }
    }

    func back() { if canGoBack { stack.removeLast() } }
    func close() { stack = [] }
    func refresh() { if let current { load(current) } }

    private func load(_ ref: Ref) {
        guard let settings, settings.isConfigured(ref.tracker) else {
            states[ref.cacheKey] = .failed("Connect \(ref.tracker.label) in Settings (⌘,) to view its issues.")
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
        return try TicketDetail.parse(raw)
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
                  NSImage(data: data) != nil else { continue }
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

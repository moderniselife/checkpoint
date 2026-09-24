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

    private(set) var stack: [String] = []
    private(set) var states: [String: LoadState] = [:]
    private var settings: AppSettings?

    var currentKey: String? { stack.last }
    var isOpen: Bool { !stack.isEmpty }
    var canGoBack: Bool { stack.count > 1 }

    func attach(_ settings: AppSettings) { self.settings = settings }

    /// Opens a ticket; from inside the panel it pushes so Back returns to where you were.
    func open(_ key: String, push: Bool = false) {
        let key = key.uppercased()
        if push, stack.last != key { stack.append(key) } else if !push { stack = [key] }
        if states[key] == nil { load(key) }
    }

    func back() { if canGoBack { stack.removeLast() } }
    func close() { stack = [] }
    func refresh() { if let key = currentKey { load(key) } }

    private func load(_ key: String) {
        guard let settings, settings.isAtlassianConfigured else {
            states[key] = .failed("Connect Atlassian in Settings (⌘,) to view tickets.")
            return
        }
        states[key] = .loading
        let mcp = settings.makeMCPClient()
        let site = settings.siteHost
        Task {
            do {
                let cloudID = try await Self.resolveCloudID(site: site, mcp: mcp)
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
                states[key] = .loaded(try TicketDetail.parse(raw))
            } catch {
                states[key] = .failed(error.localizedDescription)
            }
        }
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
    }

    private var cache: [String: Data] = [:]

    func data(for attachment: TicketDetail.Attachment, full: Bool, creds: Credentials) async -> Data? {
        let cacheKey = attachment.id + (full ? "-full" : "-thumb")
        if let d = cache[cacheKey] { return d }
        let kind = full ? "content" : "thumbnail"

        var attempts: [(URL, String)] = []
        if let basic = creds.basicHeader, !creds.site.isEmpty,
           let url = URL(string: "https://\(creds.site)/rest/api/3/attachment/\(kind)/\(attachment.id)?redirect=false") {
            attempts.append((url, basic))
        }
        if creds.useOAuth, let token = try? await AtlassianOAuth.shared.accessToken(),
           let base = full ? attachment.contentURL : (attachment.thumbnailURL ?? attachment.contentURL),
           let url = URL(string: base.absoluteString + "?redirect=false") {
            attempts.append((url, "Bearer " + token))
        }

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
            useOAuth: atlassianUser != nil
        )
    }

    /// Browser URL for an attachment — the browser's own Jira session handles auth.
    func browserURL(for attachment: TicketDetail.Attachment) -> URL? {
        guard !siteHost.isEmpty else { return attachment.contentURL }
        return URL(string: "https://\(siteHost)/rest/api/3/attachment/content/\(attachment.id)")
    }

    func browseURL(for key: String) -> URL? {
        URL(string: "https://\(siteHost.isEmpty ? "atlassian.net" : siteHost)/browse/\(key)")
    }
}

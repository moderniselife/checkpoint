import Foundation

/// Maps Linear MCP `get_issue` / `list_comments` output onto `TicketDetail`.
/// Linear's MCP output shape isn't formally documented, so every field is read
/// tolerantly (string or {name}, camelCase variants, wrapped or bare objects),
/// and non-JSON output falls back to showing the raw text as the description.
nonisolated extension TicketDetail {
    static func parseLinear(key: String, issue: String, comments: String?) -> TicketDetail {
        guard let raw = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(issue.utf8)) else {
            return fallback(key: key, text: issue)
        }
        let i = raw["issue"] ?? raw["data"]?["issue"] ?? raw
        guard i["title"] != nil || i["identifier"] != nil else { return fallback(key: key, text: issue) }

        let state = i["state"] ?? i["status"]
        let priority = name(i["priorityLabel"]) ?? name(i["priority"])
        var detail = TicketDetail(
            key: i["identifier"]?.stringValue ?? key,
            summary: i["title"]?.stringValue ?? key,
            type: name(i["team"]).map { "\($0) issue" } ?? "Issue",
            status: name(state) ?? "",
            statusCategory: linearCategory(state?["type"]?.stringValue ?? name(state) ?? ""),
            priority: priority == "No priority" ? nil : priority,
            resolution: nil,
            assignee: person(i["assignee"]),
            reporter: person(i["creator"] ?? i["createdBy"]),
            created: LinearDate.parse(i["createdAt"]?.stringValue),
            updated: LinearDate.parse(i["updatedAt"]?.stringValue),
            dueDate: i["dueDate"]?.stringValue,
            labels: names(i["labels"]),
            components: [name(i["project"])].compactMap { $0 },
            fixVersions: [name(i["cycle"])].compactMap { $0 },
            parent: linked(i["parent"], relation: "parent"),
            description: i["description"]?.stringValue ?? "",
            comments: [],
            commentTotal: 0,
            attachments: [],
            worklogs: [],
            worklogTotal: 0,
            timeTracking: TimeTracking(original: nil, remaining: nil, spent: nil,
                                       originalSeconds: 0, remainingSeconds: 0, spentSeconds: 0),
            links: [],
            subtasks: list(i["children"] ?? i["subIssues"]).compactMap { linked($0, relation: "sub-issue") },
            history: [],
            otherFields: [],
            webURL: i["url"]?.stringValue.flatMap(URL.init(string:))
        )

        detail.links = list(i["relations"]).compactMap { r in
            let related = r["relatedIssue"] ?? r["issue"] ?? r
            return linked(related, relation: (r["type"]?.stringValue ?? "related").replacingOccurrences(of: "_", with: " "))
        }

        detail.tracker = .linear
        // Linear "attachments" are links (PRs, Sentry, Figma…), not files.
        detail.externalLinks = list(i["attachments"]).compactMap { a in
            guard let s = a["url"]?.stringValue, let url = URL(string: s) else { return nil }
            return ExternalLink(title: a["title"]?.stringValue ?? s, url: url,
                                subtitle: a["subtitle"]?.stringValue ?? url.host() ?? "")
        }
        var other: [Field] = []
        if let e = i["estimate"], case .number(let n) = e { other.append(Field(name: "Estimate", value: String(Int(n)))) }
        if let branch = i["gitBranchName"]?.stringValue ?? i["branchName"]?.stringValue {
            other.append(Field(name: "Git branch", value: branch))
        }
        if let team = name(i["team"]) { other.append(Field(name: "Team", value: team)) }
        detail.otherFields = other

        // Comments: from list_comments when available, else embedded in the issue.
        let commentsJSON = comments.flatMap { try? JSONCoding.decoder.decode(JSONValue.self, from: Data($0.utf8)) }
            ?? i["comments"]
        if let c = commentsJSON {
            let items = list(c["comments"] ?? c)
            detail.comments = items.enumerated().map { idx, item in
                Comment(
                    id: item["id"]?.stringValue ?? "\(idx)",
                    author: person(item["user"] ?? item["author"] ?? item["createdBy"]) ?? Person(name: "Unknown"),
                    created: LinearDate.parse(item["createdAt"]?.stringValue),
                    updated: LinearDate.parse(item["updatedAt"]?.stringValue),
                    body: item["body"]?.stringValue ?? ""
                )
            }
            .sorted { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }
            detail.commentTotal = detail.comments.count
        }

        // Files in Linear are uploads linked inline in the description/comments.
        detail.attachments = uploads(in: ([detail.description] + detail.comments.map(\.body)).joined(separator: "\n"))
        return detail
    }

    /// `uploads.linear.app` links (images and files) found in markdown, de-duplicated.
    static func uploads(in markdown: String) -> [Attachment] {
        var seen = Set<String>()
        return markdown.matches(of: /(!?)\[([^\]]*)\]\((https:\/\/uploads\.linear\.app\/[^)\s]+)\)/).compactMap { m in
            let urlString = String(m.3)
            guard seen.insert(urlString).inserted, let url = URL(string: urlString) else { return nil }
            let label = String(m.2)
            let name = label.isEmpty ? url.lastPathComponent : label
            let ext = (name as NSString).pathExtension.lowercased()
            let isImage = !m.1.isEmpty || ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(ext)
            return Attachment(
                id: urlString, filename: name,
                mimeType: isImage ? "image/\(ext.isEmpty ? "png" : ext)" : mime(for: ext),
                size: 0, author: "", created: nil, contentURL: url, thumbnailURL: url
            )
        }
    }

    private static func mime(for ext: String) -> String {
        switch ext {
        case "pdf": "application/pdf"
        case "mp4", "mov": "video/\(ext)"
        case "zip": "application/zip"
        case "json": "application/json"
        case "txt", "log", "csv": "text/plain"
        default: "application/octet-stream"
        }
    }

    private static func fallback(key: String, text: String) -> TicketDetail {
        TicketDetail(
            key: key, summary: key, type: "Issue", status: "", statusCategory: "", priority: nil,
            resolution: nil, assignee: nil, reporter: nil, created: nil, updated: nil, dueDate: nil,
            labels: [], components: [], fixVersions: [], parent: nil, description: text,
            comments: [], commentTotal: 0, attachments: [], worklogs: [], worklogTotal: 0,
            timeTracking: TimeTracking(original: nil, remaining: nil, spent: nil,
                                       originalSeconds: 0, remainingSeconds: 0, spentSeconds: 0),
            links: [], subtasks: [], history: [], otherFields: [], webURL: nil
        )
    }

    /// Linear state types → the Jira-style categories the panel colours by.
    private static func linearCategory(_ type: String) -> String {
        switch type.lowercased() {
        case "completed", "done", "canceled", "cancelled": "done"
        case "started", "in progress", "in review": "indeterminate"
        default: "new"
        }
    }

    /// A string, or an object's display name.
    private static func name(_ v: JSONValue?) -> String? {
        guard let v else { return nil }
        if let s = v.stringValue { return s.isEmpty ? nil : s }
        for k in ["name", "displayName", "label", "title", "identifier"] {
            if let s = v[k]?.stringValue { return s }
        }
        return nil
    }

    private static func names(_ v: JSONValue?) -> [String] { list(v).compactMap(name) }

    /// Arrays may come bare or wrapped as {nodes: [...]}.
    private static func list(_ v: JSONValue?) -> [JSONValue] {
        v?.arrayValue ?? v?["nodes"]?.arrayValue ?? []
    }

    private static func person(_ v: JSONValue?) -> Person? {
        guard let n = name(v) else { return nil }
        return Person(name: n, avatar: v?["avatarUrl"]?.stringValue.flatMap(URL.init(string:)))
    }

    private static func linked(_ v: JSONValue?, relation: String) -> LinkedIssue? {
        guard let v else { return nil }
        let key = v["identifier"]?.stringValue ?? v.stringValue
        guard let key, !key.isEmpty else { return nil }
        return LinkedIssue(
            key: key,
            summary: v["title"]?.stringValue ?? "",
            status: name(v["state"] ?? v["status"]) ?? "",
            type: "",
            relation: relation
        )
    }
}

/// Linear timestamps are ISO 8601, usually with fractional seconds.
nonisolated enum LinearDate {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return fractional.date(from: s) ?? plain.date(from: s)
    }
}

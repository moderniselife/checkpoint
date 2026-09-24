import Foundation

/// Everything the side panel shows for one Jira issue, parsed from getJiraIssue (`*all` fields).
nonisolated struct TicketDetail: Sendable, Hashable {
    struct Person: Sendable, Hashable {
        var name: String
        var avatar: URL?
    }

    struct Comment: Sendable, Hashable, Identifiable {
        var id: String
        var author: Person
        var created: Date?
        var updated: Date?
        var body: String
    }

    struct Attachment: Sendable, Hashable, Identifiable {
        var id: String
        var filename: String
        var mimeType: String
        var size: Int
        var author: String
        var created: Date?
        var contentURL: URL?
        var thumbnailURL: URL?
        var isImage: Bool { mimeType.hasPrefix("image/") }
    }

    struct Worklog: Sendable, Hashable, Identifiable {
        var id: String
        var author: Person
        var started: Date?
        var timeSpent: String
        var seconds: Int
        var comment: String
    }

    struct TimeTracking: Sendable, Hashable {
        var original: String?
        var remaining: String?
        var spent: String?
        var originalSeconds: Int
        var remainingSeconds: Int
        var spentSeconds: Int
        var isEmpty: Bool { original == nil && remaining == nil && spent == nil }
    }

    struct LinkedIssue: Sendable, Hashable, Identifiable {
        var key: String
        var summary: String
        var status: String
        var type: String
        var relation: String
        var id: String { relation + key }
    }

    struct HistoryEntry: Sendable, Hashable, Identifiable {
        struct Change: Sendable, Hashable {
            var field: String
            var from: String
            var to: String
        }
        var id: String
        var author: String
        var created: Date?
        var changes: [Change]
    }

    struct Field: Sendable, Hashable, Identifiable {
        var name: String
        var value: String
        var id: String { name }
    }

    var key: String
    var summary: String
    var type: String
    var status: String
    var statusCategory: String
    var priority: String?
    var resolution: String?
    var assignee: Person?
    var reporter: Person?
    var created: Date?
    var updated: Date?
    var dueDate: String?
    var labels: [String]
    var components: [String]
    var fixVersions: [String]
    var parent: LinkedIssue?
    var description: String
    var comments: [Comment]
    var commentTotal: Int
    var attachments: [Attachment]
    var worklogs: [Worklog]
    var worklogTotal: Int
    var timeTracking: TimeTracking
    var links: [LinkedIssue]
    var subtasks: [LinkedIssue]
    var history: [HistoryEntry]
    var otherFields: [Field]
    var webURL: URL?
}

// MARK: - Parsing

nonisolated extension TicketDetail {
    enum ParseError: LocalizedError {
        case notFound(String)
        var errorDescription: String? {
            switch self { case .notFound(let s): "Jira didn't return that ticket. \(s.prefix(200))" }
        }
    }

    /// Fields rendered in their own sections, or too noisy to be useful.
    private static let handledFields: Set<String> = [
        "summary", "issuetype", "status", "priority", "resolution", "assignee", "reporter", "creator",
        "created", "updated", "duedate", "labels", "components", "fixVersions", "parent", "description",
        "comment", "attachment", "worklog", "timetracking", "timespent", "timeoriginalestimate",
        "timeestimate", "aggregatetimespent", "aggregatetimeoriginalestimate", "aggregatetimeestimate",
        "aggregateprogress", "progress", "issuelinks", "subtasks", "project", "watches", "votes",
        "lastViewed", "workratio", "statuscategorychangedate", "issuerestriction", "statusCategory",
        "resolutiondate", "thumbnail", "security",
    ]
    private static let noisyNames: Set<String> = ["Rank", "Development", "[CHART] Date of First Response", "[CHART] Time in Status"]

    static func parse(_ raw: JSONValue) throws -> TicketDetail {
        // getJiraIssue wraps the issue as {issues: {nodes: [issue]}}; accept a bare issue too.
        let node = raw["issues"]?["nodes"]?.arrayValue?.first ?? raw
        guard let key = node["key"]?.stringValue, let f = node["fields"] else {
            throw ParseError.notFound(raw["error"]?.stringValue ?? raw.compactString)
        }
        let names = node["names"]

        var detail = TicketDetail(
            key: key,
            summary: f["summary"]?.stringValue ?? "",
            type: f["issuetype"]?["name"]?.stringValue ?? "",
            status: f["status"]?["name"]?.stringValue ?? "",
            statusCategory: f["status"]?["statusCategory"]?["key"]?.stringValue ?? "",
            priority: f["priority"]?["name"]?.stringValue,
            resolution: f["resolution"]?["name"]?.stringValue,
            assignee: person(f["assignee"]),
            reporter: person(f["reporter"]),
            created: JiraDate.parse(f["created"]?.stringValue),
            updated: JiraDate.parse(f["updated"]?.stringValue),
            dueDate: f["duedate"]?.stringValue,
            labels: (f["labels"]?.arrayValue ?? []).compactMap(\.stringValue),
            components: (f["components"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue },
            fixVersions: (f["fixVersions"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue },
            parent: f["parent"].flatMap { linked($0, relation: "parent") },
            description: text(f["description"]),
            comments: [],
            commentTotal: 0,
            attachments: [],
            worklogs: [],
            worklogTotal: 0,
            timeTracking: timeTracking(f["timetracking"]),
            links: [],
            subtasks: (f["subtasks"]?.arrayValue ?? []).compactMap { linked($0, relation: "subtask") },
            history: [],
            otherFields: [],
            webURL: node["webUrl"]?.stringValue.flatMap(URL.init(string:))
        )

        let comments = f["comment"]?["comments"]?.arrayValue ?? []
        detail.comments = comments.enumerated().map { i, c in
            Comment(
                id: c["id"]?.stringValue ?? "\(i)",
                author: person(c["author"]) ?? Person(name: "Unknown"),
                created: JiraDate.parse(c["created"]?.stringValue),
                updated: JiraDate.parse(c["updated"]?.stringValue),
                body: text(c["body"])
            )
        }
        detail.commentTotal = int(f["comment"]?["total"]) ?? comments.count

        detail.attachments = (f["attachment"]?.arrayValue ?? []).map { a in
            Attachment(
                id: a["id"]?.stringValue ?? UUID().uuidString,
                filename: a["filename"]?.stringValue ?? "attachment",
                mimeType: a["mimeType"]?.stringValue ?? "",
                size: int(a["size"]) ?? 0,
                author: a["author"]?["displayName"]?.stringValue ?? "",
                created: JiraDate.parse(a["created"]?.stringValue),
                contentURL: a["content"]?.stringValue.flatMap(URL.init(string:)),
                thumbnailURL: a["thumbnail"]?.stringValue.flatMap(URL.init(string:))
            )
        }

        let worklogs = f["worklog"]?["worklogs"]?.arrayValue ?? []
        detail.worklogs = worklogs.enumerated().map { i, w in
            Worklog(
                id: w["id"]?.stringValue ?? "\(i)",
                author: person(w["author"]) ?? Person(name: "Unknown"),
                started: JiraDate.parse(w["started"]?.stringValue),
                timeSpent: w["timeSpent"]?.stringValue ?? "",
                seconds: int(w["timeSpentSeconds"]) ?? 0,
                comment: text(w["comment"])
            )
        }
        detail.worklogTotal = int(f["worklog"]?["total"]) ?? worklogs.count

        detail.links = (f["issuelinks"]?.arrayValue ?? []).compactMap { l in
            if let out = l["outwardIssue"] {
                return linked(out, relation: l["type"]?["outward"]?.stringValue ?? "relates to")
            }
            if let inw = l["inwardIssue"] {
                return linked(inw, relation: l["type"]?["inward"]?.stringValue ?? "relates to")
            }
            return nil
        }

        let histories = node["changelog"]?["histories"]?.arrayValue ?? []
        detail.history = histories.enumerated().map { i, h in
            HistoryEntry(
                id: h["id"]?.stringValue ?? "\(i)",
                author: h["author"]?["displayName"]?.stringValue ?? "Automation",
                created: JiraDate.parse(h["created"]?.stringValue),
                changes: (h["items"]?.arrayValue ?? []).map {
                    HistoryEntry.Change(
                        field: $0["field"]?.stringValue ?? "",
                        from: $0["fromString"]?.stringValue ?? "",
                        to: $0["toString"]?.stringValue ?? ""
                    )
                }
            )
        }
        .sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }

        if case .object(let all) = f {
            detail.otherFields = all.compactMap { key, value -> Field? in
                guard !handledFields.contains(key) else { return nil }
                let name = names?[key]?.stringValue ?? key
                guard !noisyNames.contains(name) else { return nil }
                let v = summarize(value)
                return v.isEmpty ? nil : Field(name: name, value: v)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return detail
    }

    private static func person(_ v: JSONValue?) -> Person? {
        guard let v, let name = v["displayName"]?.stringValue else { return nil }
        return Person(name: name, avatar: v["avatarUrls"]?["48x48"]?.stringValue.flatMap(URL.init(string:)))
    }

    private static func linked(_ v: JSONValue, relation: String) -> LinkedIssue? {
        guard let key = v["key"]?.stringValue else { return nil }
        return LinkedIssue(
            key: key,
            summary: v["fields"]?["summary"]?.stringValue ?? "",
            status: v["fields"]?["status"]?["name"]?.stringValue ?? "",
            type: v["fields"]?["issuetype"]?["name"]?.stringValue ?? "",
            relation: relation
        )
    }

    private static func timeTracking(_ v: JSONValue?) -> TimeTracking {
        TimeTracking(
            original: v?["originalEstimate"]?.stringValue,
            remaining: v?["remainingEstimate"]?.stringValue,
            spent: v?["timeSpent"]?.stringValue,
            originalSeconds: int(v?["originalEstimateSeconds"]) ?? 0,
            remainingSeconds: int(v?["remainingEstimateSeconds"]) ?? 0,
            spentSeconds: int(v?["timeSpentSeconds"]) ?? 0
        )
    }

    private static func int(_ v: JSONValue?) -> Int? {
        if case .number(let n) = v ?? .null { return Int(n) }
        return nil
    }

    /// Markdown string as-is, or plain text flattened from an ADF document.
    static func text(_ v: JSONValue?) -> String {
        guard let v else { return "" }
        if let s = v.stringValue { return s }
        guard v["type"]?.stringValue == "doc" else { return "" }
        return adfText(v).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func adfText(_ node: JSONValue) -> String {
        let type = node["type"]?.stringValue ?? ""
        if type == "text" { return node["text"]?.stringValue ?? "" }
        if type == "hardBreak" { return "\n" }
        if type == "mention" { return node["attrs"]?["text"]?.stringValue ?? "@someone" }
        if type == "inlineCard" { return node["attrs"]?["url"]?.stringValue ?? "" }
        let inner = (node["content"]?.arrayValue ?? []).map(adfText).joined()
        switch type {
        case "paragraph", "heading", "codeBlock", "blockquote": return inner + "\n\n"
        case "listItem": return "- " + inner.trimmingCharacters(in: .newlines) + "\n"
        case "bulletList", "orderedList": return inner + "\n"
        default: return inner
        }
    }

    /// One-line human value for an arbitrary custom field.
    private static func summarize(_ v: JSONValue) -> String {
        switch v {
        case .null: return ""
        case .bool(let b): return b ? "Yes" : "No"
        case .number(let n): return n.rounded() == n ? String(Int(n)) : String(n)
        case .string(let s): return s
        case .array(let a): return a.map(summarize).filter { !$0.isEmpty }.joined(separator: ", ")
        case .object:
            if v["type"]?.stringValue == "doc" { return text(v) }
            for k in ["displayName", "name", "value", "key", "title"] {
                if let s = v[k]?.stringValue { return s }
            }
            return ""
        }
    }
}

/// Jira REST timestamps look like 2026-09-21T16:03:21.130+1000.
nonisolated enum JiraDate {
    // DateFormatter is thread-safe for parsing on modern macOS.
    nonisolated(unsafe) private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return formatter.date(from: s)
    }
}

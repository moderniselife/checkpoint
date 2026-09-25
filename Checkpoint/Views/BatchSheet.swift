import SwiftUI

/// Batch planning sheet (IDEA-106 import-a-sprint, IDEA-108 epic children,
/// plus a paste-a-list fallback that covers Linear views).
///
/// All modes converge on a key list + destination folder + Start, which feeds
/// `PlanStore.startBatch` — sequential, cancellable, errors summarized.
struct BatchSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case jql = "Jira JQL"
        case epic = "Epic children"
        case paste = "Paste list"
        var id: Self { self }
    }

    /// When non-nil, keys are pre-resolved (e.g. panel children) — no fetch UI.
    var initialKeys: [String]? = nil
    var initialTracker: Tracker = .jira
    var initialFolderName: String? = nil

    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .jql
    @State private var jql = "sprint in openSprints() ORDER BY rank"
    @State private var epicKey = ""
    @State private var pasted = ""
    @State private var keys: [String] = []
    @State private var folderName = ""
    @State private var runMode: TestMode = .dev
    @State private var tracker: Tracker = .jira
    @State private var resolving = false
    @State private var resolveError: String?

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            if initialKeys == nil {
                Picker("Source", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode, perform: { _ in keys = []; resolveError = nil })
                sourceEditor
            }
            if !keys.isEmpty {
                Text("\(keys.count) issues: \(keys.prefix(8).joined(separator: ", "))\(keys.count > 8 ? "…" : "")")
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let resolveError {
                Text(resolveError).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Text("Folder").frame(width: 70, alignment: .leading)
                TextField("Folder name", text: $folderName)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Mode").frame(width: 70, alignment: .leading)
                Picker("Mode", selection: $runMode) {
                    ForEach(TestMode.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                Picker("Tracker", selection: $tracker) {
                    ForEach(Tracker.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 140)
            }
            if keys.count > 25 {
                Text("Large batch — each plan takes a minute or more. It runs sequentially and you can cancel anytime.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Plan \(keys.count) issues", action: start)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(keys.isEmpty || folderName.trimmingCharacters(in: .whitespaces).isEmpty || store.batchRunning)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear(perform: setup)
    }

    private var title: String {
        if initialKeys != nil { return "Plan each child" }
        switch mode {
        case .jql: return "Import from Jira"
        case .epic: return "Plan epic children"
        case .paste: return "Batch from a list"
        }
    }

    private func setup() {
        tracker = initialKeys == nil ? settings.tracker(for: "") : initialTracker
        runMode = settings.mode
        if let initialKeys {
            keys = initialKeys
            folderName = initialFolderName ?? "Batch"
        } else {
            folderName = "Sprint import"
        }
    }

    @ViewBuilder
    private var sourceEditor: some View {
        switch mode {
        case .jql:
            VStack(alignment: .leading, spacing: 8) {
                TextField("JQL", text: $jql, axis: .vertical)
                    .font(.body.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                HStack {
                    Button(resolving ? "Searching…" : "Find issues", action: resolveJQL)
                        .disabled(resolving || jql.isEmpty)
                    Spacer()
                }
            }
        case .epic:
            HStack {
                TextField("Epic key", text: $epicKey, prompt: Text("PROJ-100"))
                    .font(.body.monospaced())
                    .textFieldStyle(.roundedBorder)
                Button(resolving ? "Loading…" : "Load children", action: resolveEpic)
                    .disabled(resolving || epicKey.isEmpty)
            }
        case .paste:
            TextField("One key or link per line", text: $pasted, axis: .vertical)
                .font(.body.monospaced())
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)
                .onChange(of: pasted, perform: { _ in
                    keys = BatchResolver.extractKeys(from: pasted)
                    if folderName == "Sprint import" || folderName.isEmpty {
                        folderName = keys.first.map { String($0.prefix(while: { $0 != "-" })) + " batch" } ?? folderName
                    }
                })
        }
    }

    private func resolveJQL() {
        resolving = true
        resolveError = nil
        let jql = jql
        Task {
            defer { resolving = false }
            do {
                keys = try await BatchResolver.jiraKeys(jql: jql, settings: settings)
                if keys.isEmpty { resolveError = "That JQL matched nothing." }
            } catch {
                resolveError = error.localizedDescription
            }
        }
    }

    private func resolveEpic() {
        resolving = true
        resolveError = nil
        let key = epicKey
        let tracker = tracker
        Task {
            defer { resolving = false }
            do {
                keys = try await BatchResolver.epicChildKeys(key: key, tracker: tracker, settings: settings)
                folderName = "\(PlanStore.extractKey(key) ?? key) children"
                if keys.isEmpty { resolveError = "No children found for \(key)." }
            } catch {
                resolveError = error.localizedDescription
            }
        }
    }

    private func start() {
        store.startBatch(inputs: keys, mode: runMode, tracker: tracker, settings: settings,
                         folderName: folderName.trimmingCharacters(in: .whitespaces))
        dismiss()
    }
}

// MARK: - Key resolution

/// Turns JQL / epic keys / pasted text into ticket key lists.
enum BatchResolver {
    /// All `KEY-123`-shaped tokens in free text, deduped in order.
    static func extractKeys(from text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for m in text.uppercased().matches(of: /[A-Z][A-Z0-9]+-\d+/) {
            let k = String(m.output)
            if seen.insert(k).inserted { out.append(k) }
        }
        return out
    }

    /// Runs JQL through the Rovo MCP search tool (paginated).
    static func jiraKeys(jql: String, settings: AppSettings) async throws -> [String] {
        let mcp = settings.makeMCPClient()
        let cloudID = try await TicketInspector.resolveCloudID(site: settings.siteHost, mcp: mcp)
        var out: [String] = []
        var token: String?
        for _ in 0..<10 {
            var args: [String: JSONValue] = [
                "cloudId": .string(cloudID),
                "jql": .string(jql),
                "fields": ["key"],
                "maxResults": 100,
            ]
            if let token { args["nextPageToken"] = .string(token) }
            let r = try await mcp.callTool("searchJiraIssuesUsingJql", arguments: .object(args))
            if r.isError { throw MCPClient.MCPError.rpc(r.text) }
            let json = try JSONCoding.decoder.decode(JSONValue.self, from: Data(r.text.utf8))
            let nodes = json["issues"]?["nodes"]?.arrayValue ?? json["issues"]?.arrayValue ?? []
            out += nodes.compactMap { $0["key"]?.stringValue }
            let info = json["issues"]?["pageInfo"] ?? json["pageInfo"]
            guard info?["hasNextPage"]?.boolValue == true,
                  let next = info?["endCursor"]?.stringValue ?? json["nextPageToken"]?.stringValue else { break }
            token = next
        }
        return out
    }

    /// Children of an epic / parent issue on either tracker.
    static func epicChildKeys(key: String, tracker: Tracker, settings: AppSettings) async throws -> [String] {
        let upper = (PlanStore.extractKey(key) ?? key).uppercased()
        switch tracker {
        case .jira:
            return try await jiraKeys(jql: "parent = \(upper) ORDER BY rank, key", settings: settings)
        case .linear:
            return try await linearChildKeys(key: upper, settings: settings)
        }
    }

    /// Linear sub-issues via `list_issues` with whatever parent filter the
    /// server's schema offers (mirrors `TicketInspector.loadLinear`).
    static func linearChildKeys(key: String, settings: AppSettings) async throws -> [String] {
        let mcp = settings.makeMCPClient(for: .linear)
        let tools = try await mcp.listTools()
        func arg(_ tool: String, _ candidates: [String]) -> String {
            let props = tools.first { $0.name == tool }?.inputSchema["properties"]
            return candidates.first { props?[$0] != nil } ?? candidates[0]
        }
        guard tools.contains(where: { $0.name == "get_issue" }),
              let list = tools.first(where: { $0.name == "list_issues" }),
              let parentArg = ["parentId", "parent"].first(where: { list.inputSchema["properties"]?[$0] != nil })
        else {
            throw TicketDetail.ParseError.notFound("Linear didn't offer the tools to list sub-issues.")
        }
        let issue = try await mcp.callTool("get_issue", arguments: .object([arg("get_issue", ["id", "issueId", "identifier"]): .string(key)]))
        if issue.isError { throw TicketDetail.ParseError.notFound(issue.text) }
        let issueID = (try? JSONCoding.decoder.decode(JSONValue.self, from: Data(issue.text.utf8)))
            .flatMap { ($0["issue"] ?? $0)["id"]?.stringValue } ?? key
        let r = try await mcp.callTool("list_issues", arguments: .object([parentArg: .string(issueID)]))
        if r.isError { throw TicketDetail.ParseError.notFound(r.text) }
        let json = try JSONCoding.decoder.decode(JSONValue.self, from: Data(r.text.utf8))
        let items = json.arrayValue ?? json["issues"]?.arrayValue ?? json["nodes"]?.arrayValue ?? []
        return items.compactMap { $0["identifier"]?.stringValue }
    }
}

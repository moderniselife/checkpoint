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
        VStack(spacing: 0) {
            Form {
                if initialKeys == nil {
                    Section {
                        Picker("Source", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: mode) { keys = []; resolveError = nil }
                        sourceEditor
                    } header: {
                        Text(title)
                    }
                }

                Section {
                    if keys.isEmpty {
                        Text(initialKeys == nil ? "Nothing found yet." : "No issues.")
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("\(keys.count) issue\(keys.count == 1 ? "" : "s")") {
                            Text(keys.prefix(6).joined(separator: ", ") + (keys.count > 6 ? "…" : ""))
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    if let resolveError {
                        Label(resolveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(initialKeys == nil ? "Found" : title)
                } footer: {
                    if keys.count > 25 {
                        Text("Large batch — each plan takes a minute or more. They run one at a time and you can cancel from the sidebar.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                Section("Plan into") {
                    TextField("Folder", text: $folderName, prompt: Text("Sprint import"))
                    Picker("Mode", selection: $runMode) {
                        ForEach(TestMode.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if settings.connectedTrackers.count > 1 || initialKeys != nil {
                        Picker("Tracker", selection: $tracker) {
                            ForEach(Tracker.allCases) { Text($0.label).tag($0) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(Platform.isMac)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(keys.isEmpty ? "Plan Issues" : "Plan \(keys.count) Issue\(keys.count == 1 ? "" : "s")", action: start)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(keys.isEmpty || folderName.trimmingCharacters(in: .whitespaces).isEmpty || store.batchRunning)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .macSheetFrame(width: 500)
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
            TextField("JQL", text: $jql, axis: .vertical)
                .font(.body.monospaced())
                .lineLimit(2...4)
            HStack {
                Spacer()
                if resolving { ProgressView().controlSize(.small) }
                Button("Find Issues", action: resolveJQL)
                    .disabled(resolving || jql.isEmpty)
            }
        case .epic:
            HStack {
                TextField("Epic", text: $epicKey, prompt: Text("PROJ-100"))
                    .font(.body.monospaced())
                    .onSubmit(resolveEpic)
                if resolving { ProgressView().controlSize(.small) }
                Button("Load Children", action: resolveEpic)
                    .disabled(resolving || epicKey.isEmpty)
            }
        case .paste:
            TextField("Keys", text: $pasted, prompt: Text("One key or link per line"), axis: .vertical)
                .font(.body.monospaced())
                .lineLimit(3...8)
                .onChange(of: pasted) {
                    keys = BatchResolver.extractKeys(from: pasted)
                    if folderName == "Sprint import" || folderName.isEmpty {
                        folderName = keys.first.map { String($0.prefix(while: { $0 != "-" })) + " batch" } ?? folderName
                    }
                }
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

import SwiftUI

/// Plan several tickets at once, from any connected tracker:
/// a Jira JQL search, Linear filters, a custom tracker's own search, an epic's children,
/// or a pasted list. Every source ends in a list of ids + a folder + Plan, which feeds
/// `PlanStore.startBatch` (sequential, cancellable, errors summarised).
struct BatchSheet: View {
    enum Source: String, CaseIterable, Identifiable {
        case jira = "Jira"
        case linear = "Linear"
        case custom = "Custom tracker"
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

    @State private var source: Source = .paste
    // Jira
    @State private var jql = "sprint in openSprints() ORDER BY rank"
    // Linear
    @State private var linear = BatchResolver.LinearFilter()
    // Custom
    @State private var customID: UUID?
    @State private var customTools: [MCPClient.Tool] = []
    @State private var customTool = ""
    @State private var customQuery = ""
    // Epic
    @State private var epicKey = ""
    @State private var epicTracker: Tracker = .jira
    // Paste
    @State private var pasted = ""
    @State private var pasteDestination = ""

    @State private var keys: [String] = []
    @State private var folderName = ""
    @State private var runMode: TestMode = .dev
    @State private var resolving = false
    @State private var resolveError: String?

    private var sources: [Source] {
        var out: [Source] = []
        if settings.isAtlassianConfigured { out.append(.jira) }
        if settings.isLinearConfigured { out.append(.linear) }
        if !settings.trackerServers.isEmpty { out.append(.custom) }
        if settings.isAtlassianConfigured || settings.isLinearConfigured { out.append(.epic) }
        out.append(.paste)
        return out
    }

    private var customServer: CustomMCPTracker? { settings.trackerServers.first { $0.id == customID } }

    /// Tracker the plans are written against (and the custom server, if any).
    private var destination: (tracker: Tracker, custom: UUID?) {
        if initialKeys != nil { return (initialTracker, nil) }
        switch source {
        case .jira: return (.jira, nil)
        case .linear: return (.linear, nil)
        case .custom: return (.custom, customID)
        case .epic: return (epicTracker, nil)
        case .paste:
            if let id = UUID(uuidString: pasteDestination) { return (.custom, id) }
            return (Tracker(rawValue: pasteDestination) ?? settings.tracker(for: pasted), nil)
        }
    }

    var body: some View {
        FormSheet(title: title,
                  confirmTitle: keys.isEmpty ? "Plan" : "Plan \(keys.count)",
                  canConfirm: !keys.isEmpty && !folderName.trimmingCharacters(in: .whitespaces).isEmpty && !store.batchRunning,
                  busy: resolving,
                  width: 520,
                  onConfirm: start) {
            if initialKeys == nil {
                Section {
                    Picker("From", selection: $source) {
                        ForEach(sources) { Text($0.rawValue).tag($0) }
                    }
                    #if os(macOS)
                    .pickerStyle(.segmented)
                    #endif
                    .onChange(of: source) { keys = []; resolveError = nil }
                    sourceFields
                } footer: {
                    Text(footer).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                if keys.isEmpty {
                    Text(initialKeys == nil ? "Nothing found yet." : "No issues.").foregroundStyle(.secondary)
                } else {
                    LabeledContent("\(keys.count) issue\(keys.count == 1 ? "" : "s")") {
                        Text(keys.prefix(6).joined(separator: ", ") + (keys.count > 6 ? "…" : ""))
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                if let resolveError {
                    Label(resolveError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            } header: {
                Text("Found")
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
            }
        }
        .onAppear(perform: setup)
    }

    private var title: String {
        if initialKeys != nil { return "Plan each child" }
        return "Plan several tickets"
    }

    private var footer: String {
        switch source {
        case .jira: "Any JQL works, e.g. sprint in openSprints(), fixVersion = 2.14, or labels = checkout."
        case .linear: "Leave a filter empty to ignore it. Team is the key you see in ids, like ENG."
        case .custom: "Uses one of the server's own search or list tools. Checkpoint picks out the ids it returns."
        case .epic: "Every child or sub-issue of the epic gets its own plan."
        case .paste: "One key or link per line, from anywhere — a Jira board, a Linear view, a spreadsheet."
        }
    }

    // MARK: Source fields

    @ViewBuilder
    private var sourceFields: some View {
        switch source {
        case .jira:
            TextField("JQL", text: $jql, axis: .vertical)
                .font(.body.monospaced())
                .lineLimit(2...4)
                .plainInput()
            findButton("Find Issues", enabled: !jql.isEmpty, action: resolveJQL)

        case .linear:
            TextField("Team", text: $linear.team, prompt: Text("ENG"))
                .plainInput()
            Picker("Cycle", selection: $linear.currentCycle) {
                Text("Any").tag(false)
                Text("Current cycle").tag(true)
            }
            TextField("Project", text: $linear.project, prompt: Text("optional"))
            TextField("State", text: $linear.state, prompt: Text("e.g. Todo, In Progress"))
            Toggle("Assigned to me", isOn: $linear.mine)
            TextField("Search", text: $linear.query, prompt: Text("optional words"))
            findButton("Find Issues", enabled: true, action: resolveLinear)

        case .custom:
            Picker("Tracker", selection: $customID) {
                ForEach(settings.trackerServers) { Text($0.displayName).tag(Optional($0.id)) }
            }
            .onChange(of: customID) { loadCustomTools() }
            if customTools.isEmpty {
                LabeledContent("Search tool") {
                    if resolving { ProgressView().controlSize(.small) } else { Text("No search or list tools found").foregroundStyle(.secondary) }
                }
            } else {
                Picker("Search tool", selection: $customTool) {
                    ForEach(customTools, id: \.name) { Text($0.name).tag($0.name) }
                }
            }
            TextField("Search", text: $customQuery, prompt: Text("what to find"))
                .plainInput()
            findButton("Find Issues", enabled: !customTool.isEmpty, action: resolveCustom)

        case .epic:
            if settings.isAtlassianConfigured && settings.isLinearConfigured {
                Picker("Tracker", selection: $epicTracker) {
                    ForEach(Tracker.builtIn) { Text($0.label).tag($0) }
                }
            }
            HStack {
                TextField("Epic", text: $epicKey, prompt: Text("PROJ-100"))
                    .font(.body.monospaced())
                    .plainInput()
                    .onSubmit(resolveEpic)
                Button("Load Children", action: resolveEpic)
                    .disabled(resolving || epicKey.isEmpty)
            }

        case .paste:
            TextField("Keys", text: $pasted, prompt: Text("One key or link per line"), axis: .vertical)
                .font(.body.monospaced())
                .lineLimit(3...8)
                .plainInput()
                .onChange(of: pasted) {
                    keys = pasteKeys
                    if folderName == "Sprint import" || folderName.isEmpty {
                        folderName = keys.first.map { String($0.prefix(while: { $0 != "-" })) + " batch" } ?? folderName
                    }
                }
            if destinations.count > 1 {
                Picker("Tracker", selection: $pasteDestination) {
                    ForEach(destinations, id: \.id) { Text($0.name).tag($0.id) }
                }
                .onChange(of: pasteDestination) { keys = pasteKeys }
            }
        }
    }

    private func findButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            if resolving { ProgressView().controlSize(.small) }
            Button(title, action: action).disabled(resolving || !enabled)
        }
    }

    /// Where pasted ids go: Jira, Linear, or a custom tracker.
    private var destinations: [(id: String, name: String)] {
        Tracker.builtIn.filter(settings.isConfigured).map { ($0.rawValue, $0.label) }
            + settings.trackerServers.map { ($0.id.uuidString, $0.displayName) }
    }

    /// KEY-123s for Jira/Linear; for a custom tracker any non-empty line is an id.
    private var pasteKeys: [String] {
        if destination.tracker == .custom {
            var seen = Set<String>()
            return pasted.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
        }
        return BatchResolver.extractKeys(from: pasted)
    }

    private func setup() {
        runMode = settings.mode
        if let initialKeys {
            keys = initialKeys
            folderName = initialFolderName ?? "Batch"
            return
        }
        folderName = "Sprint import"
        source = sources.first ?? .paste
        epicTracker = settings.isAtlassianConfigured ? .jira : .linear
        customID = settings.trackerServers.first?.id
        pasteDestination = destinations.first?.id ?? Tracker.jira.rawValue
        if source == .custom { loadCustomTools() }
    }

    // MARK: Resolving

    private func run(_ work: @escaping () async throws -> [String], folder: String? = nil, empty: String) {
        resolving = true
        resolveError = nil
        Task {
            defer { resolving = false }
            do {
                keys = try await work()
                if let folder { folderName = folder }
                if keys.isEmpty { resolveError = empty }
            } catch {
                resolveError = error.localizedDescription
            }
        }
    }

    private func resolveJQL() {
        let jql = jql
        run({ try await BatchResolver.jiraKeys(jql: jql, settings: settings) }, empty: "That JQL matched nothing.")
    }

    private func resolveLinear() {
        let filter = linear
        let folder = [filter.team, filter.currentCycle ? "current cycle" : ""].filter { !$0.isEmpty }.joined(separator: " ")
        run({ try await BatchResolver.linearKeys(filter, settings: settings) },
            folder: folder.isEmpty ? nil : folder, empty: "No Linear issues match those filters.")
    }

    private func loadCustomTools() {
        guard let server = customServer, let client = settings.makeMCPClient(forCustom: server) else {
            customTools = []
            return
        }
        resolving = true
        Task {
            defer { resolving = false }
            let all = (try? await client.listTools()) ?? []
            customTools = BatchResolver.searchTools(in: all)
            customTool = customTools.first?.name ?? ""
            if customTools.isEmpty { resolveError = "\(server.displayName) has no read-only search or list tools." }
        }
    }

    private func resolveCustom() {
        guard let server = customServer, let client = settings.makeMCPClient(forCustom: server),
              let tool = customTools.first(where: { $0.name == customTool }) else { return }
        let query = customQuery
        run({ try await BatchResolver.customKeys(tool: tool, query: query, client: client) },
            folder: "\(server.displayName) batch", empty: "\(server.displayName) returned nothing for that search.")
    }

    private func resolveEpic() {
        let key = epicKey, tracker = epicTracker
        run({ try await BatchResolver.epicChildKeys(key: key, tracker: tracker, settings: settings) },
            folder: "\(PlanStore.extractKey(key) ?? key) children", empty: "No children found for \(key).")
    }

    private func start() {
        let dest = destination
        store.startBatch(inputs: keys, mode: runMode, tracker: dest.tracker, customTracker: dest.custom,
                         settings: settings, folderName: folderName.trimmingCharacters(in: .whitespaces))
        dismiss()
    }
}

private extension View {
    func plainInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self
        #endif
    }
}

// MARK: - Key resolution

/// Turns JQL, Linear filters, custom searches, epic keys and pasted text into id lists.
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

    struct LinearFilter: Sendable {
        var team = ""
        var currentCycle = false
        var project = ""
        var state = ""
        var mine = false
        var query = ""
    }

    /// Linear issues through `list_issues`, sending only the filters its schema accepts.
    static func linearKeys(_ f: LinearFilter, settings: AppSettings) async throws -> [String] {
        let mcp = settings.makeMCPClient(for: .linear)
        let tools = try await mcp.listTools()
        guard let list = tools.first(where: { $0.name == "list_issues" }) else {
            throw TicketDetail.ParseError.notFound("Linear didn't offer a list_issues tool.")
        }
        let props = list.inputSchema["properties"]
        func key(_ candidates: [String]) -> String? { candidates.first { props?[$0] != nil } }
        var args: [String: JSONValue] = [:]
        if !f.team.isEmpty, let k = key(["team", "teamId", "teamKey"]) { args[k] = .string(f.team) }
        if f.currentCycle, let k = key(["cycle", "cycleId"]) { args[k] = .string("current") }
        if !f.project.isEmpty, let k = key(["project", "projectId"]) { args[k] = .string(f.project) }
        if !f.state.isEmpty, let k = key(["state", "status", "stateId"]) { args[k] = .string(f.state) }
        if f.mine, let k = key(["assignee", "assigneeId"]) { args[k] = .string("me") }
        if !f.query.isEmpty, let k = key(["query", "search", "filter"]) { args[k] = .string(f.query) }
        if let k = key(["limit", "first"]) { args[k] = 100 }
        let r = try await mcp.callTool("list_issues", arguments: .object(args))
        if r.isError { throw TicketDetail.ParseError.notFound(r.text) }
        return ids(in: r.text, preferring: ["identifier"])
    }

    /// A custom server's read-only tools that look like search or list calls.
    static func searchTools(in tools: [MCPClient.Tool]) -> [MCPClient.Tool] {
        let words = ["search", "list", "query", "find", "filter"]
        return tools
            .filter { t in PlanGenerator.isReadOnly(t.name) && words.contains { t.name.lowercased().contains($0) } }
            .sorted { a, b in
                // Search-y tools first, then list-y.
                let sa = a.name.lowercased().contains("search"), sb = b.name.lowercased().contains("search")
                return sa != sb ? sa : a.name < b.name
            }
    }

    /// Calls a custom tracker's search tool with the query in whichever string argument it takes.
    static func customKeys(tool: MCPClient.Tool, query: String, client: MCPClient) async throws -> [String] {
        let props = tool.inputSchema["properties"]
        let names = ["query", "q", "search", "jql", "filter", "text", "term", "keyword", "keywords"]
        var args: [String: JSONValue] = [:]
        if !query.isEmpty {
            let required = tool.inputSchema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
            if let k = names.first(where: { props?[$0] != nil }) ?? required.first {
                args[k] = .string(query)
            }
        }
        if let k = ["limit", "max_results", "maxResults", "first", "per_page"].first(where: { props?[$0] != nil }) {
            args[k] = 100
        }
        let r = try await client.callTool(tool.name, arguments: .object(args))
        if r.isError { throw TicketDetail.ParseError.notFound(r.text) }
        return ids(in: r.text, preferring: ["identifier", "key", "number", "id"])
    }

    /// Ids from a tool result: the preferred fields of each listed item when it's JSON,
    /// else anything shaped like KEY-123.
    static func ids(in text: String, preferring fields: [String]) -> [String] {
        guard let json = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(text.utf8)) else {
            return extractKeys(from: text)
        }
        func items(_ v: JSONValue) -> [JSONValue] {
            if let a = v.arrayValue { return a }
            for k in ["issues", "items", "results", "tasks", "nodes", "data", "records", "tickets"] {
                if let inner = v[k] { let found = items(inner); if !found.isEmpty { return found } }
            }
            return []
        }
        var seen = Set<String>()
        let found = items(json).compactMap { item -> String? in
            for f in fields {
                if let s = item[f]?.stringValue, !s.isEmpty { return s }
                if case .number(let n)? = item[f] { return String(Int(n)) }
            }
            return nil
        }.filter { seen.insert($0).inserted }
        return found.isEmpty ? extractKeys(from: text) : found
    }

    /// Children of an epic / parent issue on either built-in tracker.
    static func epicChildKeys(key: String, tracker: Tracker, settings: AppSettings) async throws -> [String] {
        let upper = (PlanStore.extractKey(key) ?? key).uppercased()
        switch tracker {
        case .jira:
            return try await jiraKeys(jql: "parent = \(upper) ORDER BY rank, key", settings: settings)
        case .linear:
            return try await linearChildKeys(key: upper, settings: settings)
        case .custom:
            throw TicketDetail.ParseError.notFound("Epic children are only available for Jira and Linear.")
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

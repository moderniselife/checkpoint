import SwiftUI

// MARK: - Jira (Atlassian Rovo MCP)

struct JiraPane: View {
    @Environment(AppSettings.self) private var settings
    @State private var testState: ConnectionTestState = .idle
    @State private var signingIn = false
    @State private var tools: [MCPClient.Tool] = []

    var body: some View {
        @Bindable var settings = settings
        SettingsPane(section: .jira) {
            Section {
                TextField("Jira site", text: $settings.site, prompt: Text("yourcompany.atlassian.net"))
                Picker("Connect with", selection: $settings.atlassianAuth) {
                    ForEach(AppSettings.AtlassianAuth.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: settings.atlassianAuth) { testState = .idle; tools = [] }

                switch settings.atlassianAuth {
                case .oauth:
                    HStack {
                        if let user = settings.atlassianUser {
                            Label(user, systemImage: "person.crop.circle.badge.checkmark")
                                .foregroundStyle(.green)
                            Spacer()
                            Button("Sign out", action: signOut)
                        } else {
                            Text("Not signed in").foregroundStyle(.secondary)
                            Spacer()
                            Button("Sign in with Atlassian", action: signIn)
                                .buttonStyle(.glassProminent)
                                .disabled(signingIn)
                        }
                        if signingIn { ProgressView().controlSize(.small) }
                    }
                case .apiToken:
                    TextField("Email", text: $settings.atlassianEmail, prompt: Text("you@company.com"))
                    SecureField("API token", text: $settings.atlassianToken)
                }

                TestRow(title: "Test connection", state: testState, disabled: !settings.isAtlassianConfigured,
                        action: test) { who, n in "\(who) — \(n) read-only tools" }
                MCPToolsView(tools: tools)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if settings.atlassianAuth == .apiToken {
                        Link("Create an Atlassian API token", destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                        Text("Your org admin must allow API-token auth for the Rovo MCP server.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Opens Atlassian's consent screen in your browser, then returns here. Tokens refresh automatically.")
                            .foregroundStyle(.secondary)
                    }
                    Text("Checkpoint only ever uses read-only tools.").foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    private func signIn() {
        signingIn = true
        testState = .idle
        Task {
            defer { signingIn = false }
            do {
                try await settings.signInAtlassian()
            } catch MCPOAuth.OAuthError.cancelled {
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }

    private func signOut() {
        settings.signOutAtlassian()
        testState = .idle
        tools = []
    }

    private func test() {
        testState = .testing
        let client = settings.makeMCPClient()
        Task {
            do {
                let all = try await client.authenticatedTools()
                let who = try await client.whoAmI()
                tools = all.sorted { $0.name < $1.name }
                testState = .ok(who, all.filter { PlanGenerator.isReadOnly($0.name) }.count)
            } catch {
                tools = []
                testState = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Linear (official MCP)

struct LinearPane: View {
    @Environment(AppSettings.self) private var settings
    @State private var linearState: ConnectionTestState = .idle
    @State private var linearSigningIn = false
    @State private var tools: [MCPClient.Tool] = []

    var body: some View {
        @Bindable var settings = settings
        SettingsPane(section: .linear) {
            Section {
                Picker("Connect with", selection: $settings.linearAuth) {
                    ForEach(AppSettings.LinearAuth.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: settings.linearAuth) { linearState = .idle; tools = [] }

                switch settings.linearAuth {
                case .oauth:
                    HStack {
                        if let user = settings.linearUser {
                            Label(user, systemImage: "person.crop.circle.badge.checkmark").foregroundStyle(.green)
                            Spacer()
                            Button("Sign out", action: linearSignOut)
                        } else {
                            Text("Not signed in").foregroundStyle(.secondary)
                            Spacer()
                            Button("Sign in with Linear", action: linearSignIn)
                                .buttonStyle(.glassProminent)
                                .disabled(linearSigningIn)
                        }
                        if linearSigningIn { ProgressView().controlSize(.small) }
                    }
                case .apiKey:
                    SecureField("API key", text: $settings.linearAPIKey, prompt: Text("lin_api_…"))
                }

                TestRow(title: "Test connection", state: linearState, disabled: !settings.isLinearConfigured,
                        action: testLinear) { _, n in "Connected — \(n) read-only tools" }
                MCPToolsView(tools: tools)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if settings.linearAuth == .apiKey {
                        Link("Create a Linear API key", destination: URL(string: "https://linear.app/settings/account/security")!)
                    }
                    Text("Uses Linear's read-only MCP endpoint with a read-only scope — Checkpoint can't change anything in Linear. Pasted links pick Jira or Linear automatically.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    private func linearSignIn() {
        linearSigningIn = true
        linearState = .idle
        Task {
            defer { linearSigningIn = false }
            do {
                try await settings.signInLinear()
                testLinear()
            } catch MCPOAuth.OAuthError.cancelled {
            } catch {
                linearState = .failed(error.localizedDescription)
            }
        }
    }

    private func linearSignOut() {
        settings.signOutLinear()
        linearState = .idle
        tools = []
    }

    private func testLinear() {
        linearState = .testing
        let client = settings.makeMCPClient(for: .linear)
        Task {
            do {
                let listed = try await client.listTools()
                tools = listed.sorted { $0.name < $1.name }
                linearState = .ok("", listed.count)
                if settings.linearAuth == .oauth, let me = await AppSettings.linearViewerName(client, tools: listed) {
                    settings.linearUser = me
                }
            } catch {
                tools = []
                linearState = .failed(error.localizedDescription)
            }
        }
    }

}

// MARK: - Custom MCP servers and research tools

/// Wording and routing for the two kinds of user-added MCP server.
private extension CustomMCPTracker.Role {
    func section(_ id: UUID?) -> SettingsSection {
        self == .tracker ? .customMCP(id: id) : .researchTools(id: id)
    }
    var noun: String { self == .tracker ? "Server" : "Research Tool" }
    var icon: String { self == .tracker ? "server.rack" : "wand.and.stars" }
    var tint: Color { self == .tracker ? .teal : .pink }
    /// iOS forms show no field labels, so the prompt names the field there.
    var namePrompt: String {
        let example = self == .tracker ? "e.g. Asana" : "e.g. Corellium"
        return Platform.isMac ? example : "Name, \(example)"
    }
    var notesPrompt: String {
        self == .tracker ? "optional" : "e.g. Spin up an iPhone 17 on iOS 26 to test on. Use it to check crash logs."
    }
}

/// Any MCP server over Streamable HTTP: endpoint + optional bearer token,
/// then tools/list decides what Checkpoint may use.
///
/// Trackers hold tickets (plans can be written from them and batches imported);
/// research tools (Obsidian, Corellium, a wiki, a device farm) are extra sources and
/// helpers the planner can use while it researches.
struct CustomMCPListPane: View {
    var role: CustomMCPTracker.Role = .tracker
    @Environment(AppSettings.self) private var settings
    @Binding var selection: SettingsSection?
    @State private var showingAdd = false

    private var servers: [CustomMCPTracker] { role == .tracker ? settings.trackerServers : settings.researchTools }

    var body: some View {
        @Bindable var settings = settings
        SettingsPane(section: role.section(nil)) {
            Section {
                if servers.isEmpty {
                    Text(role == .tracker ? "No servers yet." : "No research tools yet.").foregroundStyle(.secondary)
                }
                ForEach(servers) { server in
                    Button { selection = role.section(server.id) } label: {
                        HStack(spacing: 10) {
                            SettingsIconTile(icon: role.icon, tint: role.tint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(server.displayName)
                                Text(server.endpoint)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(badge(server)).font(.caption).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Spacer()
                    Button("Add \(role.noun)…", systemImage: "plus") { showingAdd = true }
                }
            } header: {
                Text(role == .tracker ? "Servers" : "Research tools")
            } footer: {
                Text(footer).font(.caption).foregroundStyle(.secondary)
            }

            if role == .tracker, !servers.isEmpty {
                Section {
                    Picker("Bare keys go to", selection: $settings.defaultCustomTrackerID) {
                        Text(settings.connectedTrackers.isEmpty ? "First server" : "Jira / Linear").tag(UUID?.none)
                        ForEach(servers) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                } header: {
                    Text("Routing")
                } footer: {
                    Text("A key typed on its own goes here. Links and match hints are always routed to the right tracker.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            CustomMCPEditor(role: role) { name, endpoint, hint, token, notes in
                let added = settings.addCustomTracker(name: name, endpoint: endpoint, matchHint: hint,
                                                      token: token, role: role, notes: notes)
                showingAdd = false
                selection = role.section(added.id)
            }
        }
    }

    private var footer: String {
        switch role {
        case .tracker:
            "Any MCP server over Streamable HTTP that holds tickets. Plan from it like Jira or Linear, and import batches from its search tools. Checkpoint only calls read-only tools. Tokens stay in the Keychain."
        case .research:
            "Tools the planner can use while it researches: notes in Obsidian, docs in a wiki, or a device cloud like Corellium to set up the test environment. Read-only by default; choose action tools per server. Servers that run locally over stdio need an HTTP bridge (for example supergateway or mcp-proxy)."
        }
    }

    private func badge(_ server: CustomMCPTracker) -> String {
        switch role {
        case .tracker: server.id == settings.defaultCustomTrackerID ? "Default" : (server.useForResearch ? "Research" : "")
        case .research: !server.useForResearch ? "Off" : (server.toolAccess == .chosen ? "\(server.allowedTools.count) tools" : "Read-only")
        }
    }
}

struct CustomMCPDetailPane: View {
    let trackerID: UUID
    @Binding var selection: SettingsSection?
    @Environment(AppSettings.self) private var settings
    @State private var state: ConnectionTestState = .idle
    @State private var tools: [MCPClient.Tool] = []
    @State private var token = ""
    @State private var confirmingRemove = false

    private var tracker: CustomMCPTracker? { settings.customTrackers.first { $0.id == trackerID } }

    private func binding<T>(_ key: WritableKeyPath<CustomMCPTracker, T>) -> Binding<T> {
        Binding(
            get: { tracker![keyPath: key] },
            set: { guard var t = tracker else { return }; t[keyPath: key] = $0; settings.updateCustomTracker(t) }
        )
    }

    private func toolBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { tracker?.allowedTools.contains(name) ?? false },
            set: { on in
                guard var t = tracker else { return }
                if on { t.allowedTools.insert(name) } else { t.allowedTools.remove(name) }
                settings.updateCustomTracker(t)
            }
        )
    }

    var body: some View {
        if let tracker {
            let role = tracker.role
            SettingsPane(section: role.section(tracker.id), title: tracker.displayName) {
                Section {
                    TextField("Name", text: binding(\.name), prompt: Text(role.namePrompt))
                    TextField("Endpoint", text: binding(\.endpoint), prompt: Text("https://mcp.example.com/mcp"))
                        .font(.body.monospaced())
                        .plainURLInput()
                    SecureField("Bearer token", text: $token, prompt: Text(Platform.isMac ? "optional" : "Bearer token (optional)"))
                        .onAppear { token = settings.customToken(for: tracker) }
                        .onChange(of: token) { settings.setCustomToken(token, for: tracker) }
                    if role == .tracker {
                        TextField("Match hint", text: binding(\.matchHint), prompt: Text("e.g. asana"))
                            .plainURLInput()
                    }
                } header: {
                    Text(role.noun)
                } footer: {
                    if role == .tracker {
                        Text("The match hint routes pasted links containing it (like “asana”) to this server.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if role == .research {
                    Section {
                        TextField("What it's for", text: binding(\.notes), prompt: Text(role.notesPrompt), axis: .vertical)
                            .lineLimit(2...6)
                    } header: {
                        Text("Instructions")
                    } footer: {
                        Text("Told to the planner with the tool list, so it knows when this is worth using.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle(role == .tracker ? "Use while researching plans" : "Use while writing plans",
                           isOn: binding(\.useForResearch))
                    if role == .research {
                        Picker("Tools it may call", selection: binding(\.toolAccess)) {
                            Text("Read-only").tag(CustomMCPTracker.ToolAccess.readOnly)
                            Text("Chosen tools").tag(CustomMCPTracker.ToolAccess.chosen)
                        }
                    }
                    TestRow(title: "List tools", state: state, disabled: tracker.endpoint.isEmpty,
                            action: listTools) { _, n in
                        role == .research && tracker.toolAccess == .chosen ? "\(n) tools" : "\(n) read-only tools"
                    }
                    if role == .research && tracker.toolAccess == .chosen {
                        if tools.isEmpty {
                            Text("List tools to choose which ones the planner may call.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(tools, id: \.name) { tool in
                            Toggle(isOn: toolBinding(tool.name)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.name).font(.callout.monospaced())
                                    if !tool.description.isEmpty {
                                        Text(tool.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                            }
                        }
                    } else {
                        MCPToolsView(tools: tools)
                    }
                } header: {
                    Text("Access")
                } footer: {
                    Text(accessFooter(tracker)).font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Spacer()
                        Button("Remove \(role.noun)…", role: .destructive) { confirmingRemove = true }
                    }
                }
            }
            .onAppear { if role == .research && tracker.toolAccess == .chosen && !tracker.endpoint.isEmpty { listTools() } }
            .confirmationDialog("Remove \(tracker.displayName)?", isPresented: $confirmingRemove) {
                Button("Remove", role: .destructive) {
                    settings.removeCustomTracker(tracker)
                    selection = role.section(nil)
                }
            } message: {
                Text("Its token is deleted from the Keychain.")
            }
        } else {
            ContentUnavailableView("Removed", systemImage: "server.rack",
                                   description: Text("Pick another from the sidebar."))
        }
    }

    private func accessFooter(_ t: CustomMCPTracker) -> String {
        switch (t.role, t.toolAccess) {
        case (.tracker, _):
            "When on, the planner can also read from this server's read-only tools, and tasks cite it as a source."
        case (.research, .readOnly):
            "The planner can call this server's read-only tools (get, list, search…) and cite what it finds."
        case (.research, .chosen):
            "The planner may call exactly the tools ticked here, including ones that act, like creating a device. It only acts to set up testing, and lists what it set up in the plan's preconditions."
        }
    }

    private func listTools() {
        guard let tracker, let client = settings.makeMCPClient(forCustom: tracker) else {
            state = .failed("That endpoint URL doesn't look valid.")
            return
        }
        state = .testing
        Task {
            do {
                let listed = try await client.listTools()
                tools = listed.sorted { $0.name < $1.name }
                state = .ok("", listed.filter { tracker.allows($0.name) || tracker.toolAccess == .chosen && tracker.role == .research }.count)
            } catch {
                tools = []
                state = .failed(error.localizedDescription)
            }
        }
    }
}

/// Add sheet for either kind of server.
private struct CustomMCPEditor: View {
    let role: CustomMCPTracker.Role
    var onSave: (_ name: String, _ endpoint: String, _ hint: String, _ token: String, _ notes: String) -> Void
    @State private var name = ""
    @State private var endpoint = ""
    @State private var hint = ""
    @State private var token = ""
    @State private var notes = ""

    private var valid: Bool {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces)) else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }

    var body: some View {
        FormSheet(title: "Add \(role.noun)", confirmTitle: "Add", canConfirm: valid, width: 460) {
            onSave(name, endpoint.trimmingCharacters(in: .whitespaces), hint, token, notes)
        } content: {
            Section {
                TextField("Name", text: $name, prompt: Text(role.namePrompt))
                TextField("Endpoint", text: $endpoint, prompt: Text("https://…/mcp endpoint"))
                    .font(.body.monospaced())
                    .plainURLInput()
                    #if os(iOS)
                    .keyboardType(.URL)
                    #endif
                SecureField("Bearer token", text: $token, prompt: Text(Platform.isMac ? "optional" : "Bearer token (optional)"))
            } header: {
                Text("Server")
            } footer: {
                Text("Streamable HTTP. Servers that only run locally over stdio need an HTTP bridge first.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if role == .tracker {
                Section {
                    TextField("Match hint", text: $hint, prompt: Text("optional, e.g. asana"))
                        .plainURLInput()
                } footer: {
                    Text("Links containing this go to this server. Checkpoint only ever calls its read-only tools.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    TextField("What it's for", text: $notes, prompt: Text(role.notesPrompt), axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("Read-only to start. Allow specific action tools, like creating a test device, from its settings page.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private extension View {
    func plainURLInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self
        #endif
    }
}

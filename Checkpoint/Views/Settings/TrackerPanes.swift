import SwiftUI

// MARK: - Jira (Atlassian Rovo MCP)

struct JiraPane: View {
    @Environment(AppSettings.self) private var settings
    @State private var testState: ConnectionTestState = .idle
    @State private var signingIn = false
    @State private var tools: [MCPClient.Tool] = []

    var body: some View {
        @Bindable var settings = settings
        SettingsDetailContainer(section: .jira) {
            SettingsCard(title: "Site") {
                SettingsRow(label: "Jira site", systemImage: "building.2", tint: .blue) {
                    TextField("Jira site", text: $settings.site, prompt: Text("yourcompany.atlassian.net"))
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospaced())
                }
                CardDivider()
                SettingsRow(label: "Connect with", systemImage: "person.badge.key", tint: .orange) {
                    Picker("Connect with", selection: $settings.atlassianAuth) {
                        ForEach(AppSettings.AtlassianAuth.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .onChange(of: settings.atlassianAuth) { testState = .idle; tools = [] }
                }
            }

            SettingsCard(title: "Account") {
                switch settings.atlassianAuth {
                case .oauth:
                    HStack {
                        if let user = settings.atlassianUser {
                            Label(user, systemImage: "person.crop.circle.badge.checkmark").foregroundStyle(.green)
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
                    .padding(.horizontal, 16).padding(.vertical, 10)
                case .apiToken:
                    SettingsRow(label: "Email", systemImage: "envelope", tint: .secondary) {
                        TextField("Email", text: $settings.atlassianEmail, prompt: Text("you@company.com"))
                            .multilineTextAlignment(.trailing)
                    }
                    CardDivider()
                    SettingsRow(label: "API token", systemImage: "key", tint: .secondary) {
                        SecureField("API token", text: $settings.atlassianToken)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                if settings.atlassianAuth == .apiToken {
                    Link("Create an Atlassian API token", destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                    Text("Your org admin must allow API-token auth for the Rovo MCP server.").foregroundStyle(.secondary)
                } else {
                    Text("Opens Atlassian's consent screen in your browser, then returns here. Tokens refresh automatically.").foregroundStyle(.secondary)
                }
                Text("Checkpoint only ever uses read-only tools.").foregroundStyle(.secondary)
            }

            SettingsCard(title: "MCP tools") {
                HStack {
                    Button("Test connection", action: test)
                        .buttonStyle(.glass)
                        .disabled(!settings.isAtlassianConfigured || testState == .testing)
                    switch testState {
                    case .idle: Text("Checks auth and lists tools.").font(.caption).foregroundStyle(.secondary)
                    case .testing: ProgressView().controlSize(.small)
                    case .ok(let who, let n): Label("\(who) — \(n) read-only tools", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    case .failed(let msg): Text(msg).foregroundStyle(.red).font(.caption).lineLimit(3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                if !tools.isEmpty {
                    CardDivider()
                    MCPToolsView(tools: tools)
                }
            }
        }
    }

    private func signIn() {
        signingIn = true
        testState = .idle
        Task {
            defer { signingIn = false }
            do {
                try await MCPOAuth.atlassian.signIn()
                settings.atlassianUser = (try? await settings.makeMCPClient().whoAmI()) ?? "Signed in"
            } catch MCPOAuth.OAuthError.cancelled {
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }

    private func signOut() {
        Task { await MCPOAuth.atlassian.signOut() }
        settings.atlassianUser = nil
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
                let readOnly = all.filter { PlanGenerator.isReadOnly($0.name) }
                tools = all.sorted { $0.name < $1.name }
                testState = .ok(who, readOnly.count)
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
        SettingsDetailContainer(section: .linear) {
            SettingsCard(title: "Account") {
                SettingsRow(label: "Connect with", systemImage: "person.badge.key", tint: .indigo) {
                    Picker("Connect with", selection: $settings.linearAuth) {
                        ForEach(AppSettings.LinearAuth.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .onChange(of: settings.linearAuth) { linearState = .idle; tools = [] }
                }
                CardDivider()
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
                    .padding(.horizontal, 16).padding(.vertical, 10)
                case .apiKey:
                    SettingsRow(label: "API key", systemImage: "key", tint: .secondary) {
                        SecureField("API key", text: $settings.linearAPIKey, prompt: Text("lin_api_…"))
                            .multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                if settings.linearAuth == .apiKey {
                    Link("Create a Linear API key", destination: URL(string: "https://linear.app/settings/account/security")!)
                }
                Text("Uses Linear's read-only MCP endpoint with a read-only scope — Checkpoint can't change anything in Linear. Pasted links pick Jira or Linear automatically.").foregroundStyle(.secondary)
            }

            SettingsCard(title: "MCP tools") {
                HStack {
                    Button("Test connection", action: testLinear)
                        .buttonStyle(.glass)
                        .disabled(!settings.isLinearConfigured || linearState == .testing)
                    switch linearState {
                    case .idle: Text("Lists Linear's read-only tools.").font(.caption).foregroundStyle(.secondary)
                    case .testing: ProgressView().controlSize(.small)
                    case .ok(_, let n): Label("Connected — \(n) read-only tools", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    case .failed(let msg): Text(msg).foregroundStyle(.red).font(.caption).lineLimit(3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                if !tools.isEmpty {
                    CardDivider()
                    MCPToolsView(tools: tools)
                }
            }
        }
    }

    private func linearSignIn() {
        linearSigningIn = true
        linearState = .idle
        Task {
            defer { linearSigningIn = false }
            do {
                try await MCPOAuth.linear.signIn()
                settings.linearUser = "Signed in"
                testLinear()
            } catch MCPOAuth.OAuthError.cancelled {
            } catch {
                linearState = .failed(error.localizedDescription)
            }
        }
    }

    private func linearSignOut() {
        Task { await MCPOAuth.linear.signOut() }
        settings.linearUser = nil
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
                if settings.linearAuth == .oauth, let me = await Self.linearViewerName(client, tools: listed) {
                    settings.linearUser = me
                }
            } catch {
                tools = []
                linearState = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated private static func linearViewerName(_ client: MCPClient, tools: [MCPClient.Tool]) async -> String? {
        guard let tool = tools.first(where: { $0.name == "get_user" }) else { return nil }
        let props = tool.inputSchema["properties"]
        let arg = ["query", "id", "userId"].first { props?[$0] != nil } ?? "query"
        guard let r = try? await client.callTool("get_user", arguments: .object([arg: "me"])), !r.isError,
              let json = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(r.text.utf8)) else { return nil }
        let user = json["user"] ?? json
        return user["displayName"]?.stringValue ?? user["name"]?.stringValue
    }
}

// MARK: - Custom MCP trackers

/// Generic pane for any MCP server. Proves the modularity story: endpoint +
/// optional bearer token → tools/list → read-only mapping. No code changes.
struct CustomMCPListPane: View {
    @Environment(AppSettings.self) private var settings
    @Binding var selection: SettingsSection?
    @State private var showingAdd = false

    var body: some View {
        @Bindable var settings = settings
        SettingsDetailContainer(section: .customMCP(id: nil)) {
            SettingsCard(title: "Servers (\(settings.customTrackers.count))") {
                if settings.customTrackers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No custom servers yet.")
                            .foregroundStyle(.secondary)
                        Text("Add any MCP server that speaks Streamable HTTP. Checkpoint reads its tools and uses the read-only ones, just like Jira and Linear.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Add MCP server…", systemImage: "plus") { showingAdd = true }
                            .buttonStyle(.glassProminent)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                } else {
                    ForEach(settings.customTrackers) { tracker in
                        Button { selection = .customMCP(id: tracker.id) } label: {
                            HStack {
                                Image(systemName: "cable.connector").foregroundStyle(.teal)
                                VStack(alignment: .leading) {
                                    Text(tracker.displayName).foregroundStyle(.primary)
                                    Text(tracker.endpoint).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    HStack {
                        Spacer()
                        Button("Add MCP server…", systemImage: "plus") { showingAdd = true }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            } footer: {
                Text("Format: Streamable HTTP endpoint with tools/list + tools/call. Auth is an optional bearer token stored in the Keychain. Routing uses the match hint (e.g. “asana”) when tracker links look alike.")
            }
        }
        .sheet(isPresented: $showingAdd) {
            CustomTrackerEditor { name, endpoint, hint, token in
                settings.addCustomTracker(name: name, endpoint: endpoint, matchHint: hint, token: token)
                showingAdd = false
            }
        }
    }
}

struct CustomMCPDetailPane: View {
    let trackerID: UUID
    @Binding var selection: SettingsSection?
    @Environment(AppSettings.self) private var settings
    @State private var state: ConnectionTestState = .idle
    @State private var tools: [MCPClient.Tool] = []
    @State private var token: String = ""

    private var tracker: CustomMCPTracker? {
        settings.customTrackers.first { $0.id == trackerID }
    }

    var body: some View {
        @Bindable var settings = settings
        Group {
            if let tracker {
                SettingsDetailContainer(section: .customMCP(id: tracker.id)) {
                    SettingsCard(title: "Server") {                        SettingsRow(label: "Name", systemImage: "tag", tint: .teal) {
                            TextField("Name", text: Binding(
                                get: { tracker.name },
                                set: { var t = tracker; t.name = $0; settings.updateCustomTracker(t) }
                            )).multilineTextAlignment(.trailing)
                        }
                        CardDivider()
                        SettingsRow(label: "Endpoint", systemImage: "link", tint: .blue) {
                            TextField("Endpoint", text: Binding(
                                get: { tracker.endpoint },
                                set: { var t = tracker; t.endpoint = $0; settings.updateCustomTracker(t) }
                            ), prompt: Text("https://mcp.example.com/mcp"))
                                .multilineTextAlignment(.trailing)
                                .font(.body.monospaced())
                        }
                        CardDivider()
                        SettingsRow(label: "Match hint", systemImage: "magnifyingglass", tint: .orange) {
                            TextField("Match hint", text: Binding(
                                get: { tracker.matchHint },
                                set: { var t = tracker; t.matchHint = $0; settings.updateCustomTracker(t) }
                            ), prompt: Text("e.g. asana"))
                                .multilineTextAlignment(.trailing)
                        }
                        CardDivider()
                        SettingsRow(label: "Token", systemImage: "key", tint: .secondary) {
                            SecureField("Bearer token (optional)", text: $token, prompt: Text("optional"))
                                .multilineTextAlignment(.trailing)
                                .onChange(of: tracker.id, initial: true) { token = settings.customToken(for: tracker) }
                                .onChange(of: token) { settings.setCustomToken(token, for: tracker) }
                        }
                    }
                    SettingsCard(title: "Research") {
                        SettingsRow(label: "Use for research", systemImage: "magnifyingglass", tint: .teal) {
                            Toggle("Use for research", isOn: Binding(
                                get: { tracker.useForResearch },
                                set: { var t = tracker; t.useForResearch = $0; settings.updateCustomTracker(t) }
                            ))
                            .labelsHidden()
                        }
                    } footer: {
                        Text("Offers this server's read-only tools to the planner alongside tracker tools. Cited in task sources.")
                    }
                    SettingsCard(title: "MCP tools") {
                        HStack {
                            Button("List tools", action: listTools)
                                .buttonStyle(.glass)
                                .disabled(state == .testing || tracker.endpoint.isEmpty)
                            switch state {
                            case .idle: Text("Reads tools/list from this server.").font(.caption).foregroundStyle(.secondary)
                            case .testing: ProgressView().controlSize(.small)
                            case .ok(_, let n): Label("\(n) tools found", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                            case .failed(let msg): Text(msg).foregroundStyle(.red).font(.caption).lineLimit(4)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        if !tools.isEmpty {
                            CardDivider()
                            MCPToolsView(tools: tools)
                        }
                    }
                    SettingsCard(title: "Danger") {
                        Button("Remove server", role: .destructive) {
                            settings.removeCustomTracker(tracker)
                            selection = .customMCP(id: nil)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                }
            } else {
                ContentUnavailableView("Server removed", systemImage: "cable.connector.slash", description: Text("Pick another server from the list."))
            }
        }
        .onChange(of: trackerID) { state = .idle; tools = [] }
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
                let ro = listed.filter { PlanGenerator.isReadOnly($0.name) }.count
                state = .ok("", ro)
            } catch {
                tools = []
                state = .failed(error.localizedDescription)
            }
        }
    }
}

private struct CustomTrackerEditor: View {
    var onSave: (String, String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var endpoint = ""
    @State private var hint = ""
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add MCP server").font(.headline)
            TextField("Name (e.g. Asana)", text: $name)
            TextField("Endpoint (https://…/mcp)", text: $endpoint)
                .font(.body.monospaced())
            TextField("Match hint (optional, e.g. asana)", text: $hint)
            SecureField("Bearer token (optional)", text: $token)
            Text("Checkpoint calls tools/list to discover what this server offers, then only uses read-only tools for planning.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add server") { onSave(name, endpoint, hint, token) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(URL(string: endpoint)?.scheme == nil)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

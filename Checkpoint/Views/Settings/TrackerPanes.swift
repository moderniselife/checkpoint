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

// MARK: - Custom MCP servers

/// Any MCP server over Streamable HTTP: endpoint + optional bearer token,
/// then tools/list decides what Checkpoint may read.
struct CustomMCPListPane: View {
    @Environment(AppSettings.self) private var settings
    @Binding var selection: SettingsSection?
    @State private var showingAdd = false

    var body: some View {
        SettingsPane(section: .customMCP(id: nil)) {
            Section {
                if settings.customTrackers.isEmpty {
                    Text("No servers yet.").foregroundStyle(.secondary)
                }
                ForEach(settings.customTrackers) { tracker in
                    Button { selection = .customMCP(id: tracker.id) } label: {
                        HStack(spacing: 10) {
                            SettingsIconTile(icon: "server.rack", tint: .teal)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tracker.displayName)
                                Text(tracker.endpoint)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            if tracker.useForResearch {
                                Text("Research").font(.caption).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Spacer()
                    Button("Add Server…", systemImage: "plus") { showingAdd = true }
                }
            } header: {
                Text("Servers")
            } footer: {
                Text("Any MCP server over Streamable HTTP with tools/list and tools/call. Checkpoint only calls its read-only tools. Tokens are kept in the Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingAdd) {
            CustomTrackerEditor { name, endpoint, hint, token in
                settings.addCustomTracker(name: name, endpoint: endpoint, matchHint: hint, token: token)
                showingAdd = false
                if let added = settings.customTrackers.last { selection = .customMCP(id: added.id) }
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
    @State private var token = ""
    @State private var confirmingRemove = false

    private var tracker: CustomMCPTracker? { settings.customTrackers.first { $0.id == trackerID } }

    private func binding<T>(_ key: WritableKeyPath<CustomMCPTracker, T>) -> Binding<T> {
        Binding(
            get: { tracker![keyPath: key] },
            set: { guard var t = tracker else { return }; t[keyPath: key] = $0; settings.updateCustomTracker(t) }
        )
    }

    var body: some View {
        if let tracker {
            SettingsPane(section: .customMCP(id: tracker.id), title: tracker.displayName) {
                Section {
                    TextField("Name", text: binding(\.name), prompt: Text("e.g. Asana"))
                    TextField("Endpoint", text: binding(\.endpoint), prompt: Text("https://mcp.example.com/mcp"))
                        .font(.body.monospaced())
                    SecureField("Bearer token", text: $token, prompt: Text("optional"))
                        .onAppear { token = settings.customToken(for: tracker) }
                        .onChange(of: token) { settings.setCustomToken(token, for: tracker) }
                    TextField("Match hint", text: binding(\.matchHint), prompt: Text("e.g. asana"))
                } header: {
                    Text("Server")
                } footer: {
                    Text("The match hint routes pasted links containing it (like “asana”) to this server.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Use while researching plans", isOn: binding(\.useForResearch))
                    TestRow(title: "List tools", state: state, disabled: tracker.endpoint.isEmpty,
                            action: listTools) { _, n in "\(n) read-only tools" }
                    MCPToolsView(tools: tools)
                } footer: {
                    Text("When on, the planner can also read from this server's read-only tools, and tasks cite it as a source.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Spacer()
                        Button("Remove Server…", role: .destructive) { confirmingRemove = true }
                    }
                }
            }
            .confirmationDialog("Remove \(tracker.displayName)?", isPresented: $confirmingRemove) {
                Button("Remove", role: .destructive) {
                    settings.removeCustomTracker(tracker)
                    selection = .customMCP(id: nil)
                }
            } message: {
                Text("Its token is deleted from the Keychain.")
            }
        } else {
            ContentUnavailableView("Server removed", systemImage: "server.rack",
                                   description: Text("Pick another server from the sidebar."))
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
                state = .ok("", listed.filter { PlanGenerator.isReadOnly($0.name) }.count)
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
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("e.g. Asana"))
                    TextField("Endpoint", text: $endpoint, prompt: Text("https://…/mcp"))
                        .font(.body.monospaced())
                    SecureField("Bearer token", text: $token, prompt: Text("optional"))
                    TextField("Match hint", text: $hint, prompt: Text("optional, e.g. asana"))
                } header: {
                    Text("Add MCP server")
                } footer: {
                    Text("Checkpoint reads tools/list to see what the server offers, and only ever calls read-only tools.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Server") { onSave(name, endpoint, hint, token) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(URL(string: endpoint)?.scheme == nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

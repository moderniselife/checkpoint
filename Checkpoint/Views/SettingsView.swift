import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var testState: TestState = .idle
    @State private var signingIn = false
    @State private var linearState: TestState = .idle
    @State private var linearSigningIn = false
    @State private var llmState: TestState = .idle
    @State private var fetchedModels: [String] = []
    @State private var fetchingModels = false

    enum TestState: Equatable { case idle, testing, ok(String, Int), failed(String) }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(LLMProvider.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: settings.provider) { llmState = .idle; fetchedModels = [] }

                if settings.provider.hasEditableBaseURL {
                    TextField("Base URL", text: $settings.llmBaseURL, prompt: Text(settings.provider.defaultBaseURL))
                        .font(.body.monospaced())
                }
                SecureField(settings.provider.requiresKey ? "API key" : "API key (optional)",
                            text: $settings.llmKey, prompt: Text(settings.provider.keyPrompt))

                HStack {
                    TextField("Model", text: $settings.model, prompt: Text(settings.provider.defaultModel))
                        .font(.body.monospaced())
                    Menu {
                        let options = fetchedModels.isEmpty && settings.provider == .anthropic
                            ? AppSettings.claudeModels : fetchedModels
                        if options.isEmpty {
                            Text("Fetch models to see what's available")
                        }
                        ForEach(options, id: \.self) { m in
                            Button(m) { settings.model = m }
                        }
                        Divider()
                        Button("Fetch models from \(settings.provider.shortLabel)", systemImage: "arrow.down.circle", action: fetchModels)
                    } label: {
                        if fetchingModels { ProgressView().controlSize(.small) } else { Image(systemName: "list.bullet") }
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    .help("Pick a model")
                }

                Picker("Effort", selection: $settings.effort) {
                    ForEach(AppSettings.efforts, id: \.self) { Text($0.capitalized) }
                }

                HStack {
                    Button("Test", action: testLLM)
                        .disabled(!settings.isLLMConfigured || llmState == .testing)
                    switch llmState {
                    case .idle: EmptyView()
                    case .testing: ProgressView().controlSize(.small)
                    case .ok(let msg, _): Label(msg, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed(let msg): Text(msg).foregroundStyle(.red).font(.caption).lineLimit(3)
                    }
                }
            } header: {
                Text("AI provider")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let url = settings.provider.keyURL {
                        Link("Get a \(settings.provider.shortLabel) API key", destination: url)
                    }
                    Text(providerNote).foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            Section {
                Picker("Default mode", selection: $settings.mode) {
                    ForEach(TestMode.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("Hosted environment", text: $settings.qaEnvironment,
                          prompt: Text("e.g. https://app.dev.example.com (DEV)"))
            } header: {
                Text("Testing")
            } footer: {
                Text("QA mode writes black-box, UI-only plans for the hosted app. The environment is where QA plans point you.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Scenarios", selection: $settings.scenarioMode) {
                    ForEach(ScenarioMode.allCases) { Text($0.label).tag($0) }
                }
                HStack {
                    if let path = settings.codebasePath {
                        Label((path as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Change…") { settings.chooseCodebase() }
                        Button("Remove", role: .destructive) { settings.clearCodebase() }
                    } else {
                        Text("No codebase").foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose Codebase…") { settings.chooseCodebase() }
                    }
                }
            } header: {
                Text("Scenarios (optional)")
            } footer: {
                Text("Adds 3–6 end-to-end user journeys to each plan. From related tickets uses your tracker only; tickets + codebase also reads a local repo — read-only, and only the folder you choose.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                TextField("Jira site", text: $settings.site, prompt: Text("yourcompany.atlassian.net"))
                Picker("Connect with", selection: $settings.atlassianAuth) {
                    ForEach(AppSettings.AtlassianAuth.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: settings.atlassianAuth) { testState = .idle }

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

                HStack {
                    Button("Test connection", action: test)
                        .disabled(!settings.isAtlassianConfigured || testState == .testing)
                    switch testState {
                    case .idle: EmptyView()
                    case .testing: ProgressView().controlSize(.small)
                    case .ok(let who, let n): Label("\(who) — \(n) read-only tools", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed(let msg): Text(msg).foregroundStyle(.red).font(.caption).lineLimit(3)
                    }
                }
            } header: {
                Text("Atlassian (Rovo MCP)")
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
            Section {
                Picker("Connect with", selection: $settings.linearAuth) {
                    ForEach(AppSettings.LinearAuth.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: settings.linearAuth) { linearState = .idle }

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

                HStack {
                    Button("Test connection", action: testLinear)
                        .disabled(!settings.isLinearConfigured || linearState == .testing)
                    switch linearState {
                    case .idle: EmptyView()
                    case .testing: ProgressView().controlSize(.small)
                    case .ok(_, let n): Label("Connected — \(n) read-only tools", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed(let msg): Text(msg).foregroundStyle(.red).font(.caption).lineLimit(3)
                    }
                }

                if settings.isAtlassianConfigured && settings.isLinearConfigured {
                    Picker("Bare keys go to", selection: $settings.defaultTracker) {
                        ForEach(Tracker.allCases) { Text($0.label).tag($0) }
                    }
                }
            } header: {
                Text("Linear (official MCP)")
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

            Section {
                Text("Keys are stored in your macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var providerNote: String {
        switch settings.provider {
        case .anthropic: "Claude gets adaptive thinking, schema-enforced plans and automatic refusal fallbacks."
        case .openAICompatible: "Ollama, LM Studio, vLLM, llama.cpp… Use a model with tool calling. Plans need a large context window — big epics can exceed small local models."
        case .anthropicCompatible: "Any server speaking the Anthropic Messages API (e.g. LiteLLM or a gateway). Tool calling required."
        case .openrouter: "Any OpenRouter model with tool calling works, e.g. anthropic/…, openai/…, google/…"
        default: "Plans are written with tool calling, then a JSON-schema answer. Pick a model that supports tools."
        }
    }

    private func fetchModels() {
        fetchingModels = true
        let config = settings.llmConfig
        Task {
            defer { fetchingModels = false }
            do {
                let models: [String]
                switch config.provider.style {
                case .anthropic:
                    models = try await ClaudeClient(apiKey: config.apiKey, baseURL: config.baseURL,
                                                    sendBearer: config.provider != .anthropic).listModels()
                case .openAIChat:
                    models = try await OpenAIChatClient(provider: config.provider, apiKey: config.apiKey,
                                                        baseURL: config.baseURL).listModels()
                }
                fetchedModels = models
                llmState = .ok("\(models.count) models available", 0)
            } catch {
                llmState = .failed(error.localizedDescription)
            }
        }
    }

    /// Sends a tiny prompt to prove the key, URL and model all work.
    private func testLLM() {
        llmState = .testing
        let config = settings.llmConfig
        Task {
            do {
                let reply: String
                switch config.provider.style {
                case .anthropic:
                    let client = ClaudeClient(apiKey: config.apiKey, baseURL: config.baseURL, sendBearer: config.provider != .anthropic)
                    let r = try await client.createMessage([
                        "model": .string(config.model), "max_tokens": 64,
                        "messages": [["role": "user", "content": "Reply with just: OK"]],
                    ], betas: [])
                    reply = (r["content"]?.arrayValue ?? []).compactMap { $0["text"]?.stringValue }.joined()
                case .openAIChat:
                    let client = OpenAIChatClient(provider: config.provider, apiKey: config.apiKey, baseURL: config.baseURL)
                    reply = try await client.stream([
                        "model": .string(config.model),
                        "messages": [["role": "user", "content": "Reply with just: OK"]],
                    ]) { _ in }.text
                }
                let short = reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)
                llmState = .ok("\(config.model) replied “\(short.isEmpty ? "…" : short)”", 0)
            } catch {
                llmState = .failed(error.localizedDescription)
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
    }

    private func linearSignIn() {
        linearSigningIn = true
        linearState = .idle
        Task {
            defer { linearSigningIn = false }
            do {
                try await MCPOAuth.linear.signIn()
                settings.linearUser = "Signed in"
                testLinear()   // replaces "Signed in" with your name when Linear offers get_user
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
    }

    private func testLinear() {
        linearState = .testing
        let client = settings.makeMCPClient(for: .linear)
        Task {
            do {
                let tools = try await client.listTools()
                linearState = .ok("", tools.count)
                if settings.linearAuth == .oauth, let me = await Self.linearViewerName(client, tools: tools) {
                    settings.linearUser = me
                }
            } catch {
                linearState = .failed(error.localizedDescription)
            }
        }
    }

    /// Best-effort display name via Linear's `get_user` tool ("me").
    nonisolated private static func linearViewerName(_ client: MCPClient, tools: [MCPClient.Tool]) async -> String? {
        guard let tool = tools.first(where: { $0.name == "get_user" }) else { return nil }
        let props = tool.inputSchema["properties"]
        let arg = ["query", "id", "userId"].first { props?[$0] != nil } ?? "query"
        guard let r = try? await client.callTool("get_user", arguments: .object([arg: "me"])), !r.isError,
              let json = try? JSONCoding.decoder.decode(JSONValue.self, from: Data(r.text.utf8)) else { return nil }
        let user = json["user"] ?? json
        return user["displayName"]?.stringValue ?? user["name"]?.stringValue
    }

    private func test() {
        testState = .testing
        let client = settings.makeMCPClient()
        Task {
            do {
                let tools = try await client.authenticatedTools()
                let who = try await client.whoAmI()
                testState = .ok(who, tools.filter { PlanGenerator.isReadOnly($0.name) }.count)
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }
}

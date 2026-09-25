import SwiftUI

// MARK: - AI provider

/// Every provider comes from `LLMProvider.allCases`, so a new case shows up here.
struct AIProviderPane: View {
    @Environment(AppSettings.self) private var settings
    @State private var llmState: ConnectionTestState = .idle
    @State private var fetchedModels: [String] = []
    @State private var fetchingModels = false

    var body: some View {
        @Bindable var settings = settings
        SettingsPane(section: .aiProvider) {
            Section {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(LLMProvider.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: settings.provider) { llmState = .idle; fetchedModels = []; autoFetch() }
                .onAppear(perform: autoFetch)

                if settings.provider.hasEditableBaseURL {
                    TextField("Base URL", text: $settings.llmBaseURL, prompt: Text(settings.provider.defaultBaseURL))
                        .font(.body.monospaced())
                }
                SecureField(settings.provider.requiresKey ? "API key" : "API key (optional)",
                            text: $settings.llmKey, prompt: Text(settings.provider.keyPrompt))

                LabeledContent("Model") {
                    ComboBox(text: $settings.model, items: modelOptions, placeholder: settings.provider.defaultModel)
                        .frame(maxWidth: 280)
                }

                Picker("Effort", selection: $settings.effort) {
                    ForEach(AppSettings.efforts, id: \.self) { Text($0.capitalized) }
                }

                HStack {
                    Button("Test", action: testLLM)
                        .disabled(!settings.isLLMConfigured || llmState == .testing)
                    Button("Fetch Models", action: fetchModels)
                        .disabled(fetchingModels || (settings.provider.requiresKey && settings.llmKey.isEmpty))
                        .help("List the models \(settings.provider.shortLabel) offers in the Model dropdowns")
                    if fetchingModels { ProgressView().controlSize(.small) }
                    switch llmState {
                    case .idle: EmptyView()
                    case .testing: ProgressView().controlSize(.small)
                    case .ok(let msg, _): Label(msg, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed(let msg): Text(msg).foregroundStyle(.red).font(.caption).lineLimit(3)
                    }
                }
            } header: {
                Text("Provider")
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
                LabeledContent("Quick model") {
                    ComboBox(text: $settings.quickModel, items: modelOptions, placeholder: "same as above")
                        .frame(maxWidth: 280)
                }
            } header: {
                Text("Quick plans")
            } footer: {
                Text("Quick plans run at low effort, on this model if you set one. Pick a cheaper, faster model for a first pass; re-run as Deep when it matters.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Quietly fills the dropdowns for providers without a built-in list.
    private func autoFetch() {
        guard settings.provider != .anthropic, fetchedModels.isEmpty, !fetchingModels,
              !settings.provider.requiresKey || !settings.llmKey.isEmpty else { return }
        fetchModels(quiet: true)
    }

    /// Fetched models, or the built-in Claude list until a fetch.
    private var modelOptions: [String] {
        fetchedModels.isEmpty && settings.provider == .anthropic ? AppSettings.claudeModels : fetchedModels
    }

    private var providerNote: String {
        switch settings.provider {
        case .anthropic: "Claude gets adaptive thinking, schema-enforced plans and automatic refusal fallbacks."
        case .openAICompatible: "Ollama, LM Studio, vLLM, llama.cpp… Use a model with tool calling. Big epics need a large context window. Effort also caps how long a runaway thinker may go before Checkpoint moves on."
        case .anthropicCompatible: "Any server speaking the Anthropic Messages API (e.g. LiteLLM or a gateway). Tool calling required."
        case .openrouter: "Any OpenRouter model with tool calling works, e.g. anthropic/…, openai/…, google/…"
        default: "Plans are written with tool calling, then a JSON-schema answer. Pick a model that supports tools."
        }
    }

    private func fetchModels() { fetchModels(quiet: false) }

    private func fetchModels(quiet: Bool) {
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
                if !quiet { llmState = .ok("\(models.count) models available", 0) }
            } catch {
                if !quiet { llmState = .failed(error.localizedDescription) }
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
}

// MARK: - Testing

struct TestingPane: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsPane(section: .testing) {
            Section {
                Picker("Default mode", selection: $settings.mode) {
                    ForEach(TestMode.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("Hosted environment", text: $settings.qaEnvironment,
                          prompt: Text("e.g. https://app.dev.example.com (DEV)"))
            } footer: {
                Text("QA mode writes black-box, UI-only plans for the hosted app. The environment is where QA plans point you.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $settings.houseRules)
                    .font(.body)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .onChange(of: settings.houseRules) {
                        if settings.houseRules.count > 1000 {
                            settings.houseRules = String(settings.houseRules.prefix(1000))
                        }
                    }
            } header: {
                Text("House rules")
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Standing instructions added to every plan, like “always check Safari” or “use the demo tenant”.")
                    Spacer()
                    Text("\(settings.houseRules.count)/1000").monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Scenarios

struct ScenariosPane: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsPane(section: .scenarios) {
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
            } footer: {
                Text("Adds 3–6 end-to-end user journeys to each plan. From related tickets uses your tracker only; tickets + codebase also reads a local repo — read-only, and only the folder you choose.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsPane(section: .advanced) {
            Section {
                if settings.isAtlassianConfigured && settings.isLinearConfigured {
                    Picker("Bare keys go to", selection: $settings.defaultTracker) {
                        ForEach(Tracker.allCases) { Text($0.label).tag($0) }
                    }
                } else {
                    LabeledContent("Bare keys go to", value: settings.defaultTracker.label)
                }
            } header: {
                Text("Routing")
            } footer: {
                Text("Pasted links pick the right tracker automatically. With Jira and Linear both connected, choose where bare keys like PROJ-12 go.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Connections") {
                StatusRow(label: "AI provider", ok: settings.isLLMConfigured,
                          value: settings.isLLMConfigured ? settings.provider.shortLabel : "Needs setup")
                StatusRow(label: "Jira", ok: settings.isAtlassianConfigured,
                          value: settings.isAtlassianConfigured ? "Connected" : "Not connected")
                StatusRow(label: "Linear", ok: settings.isLinearConfigured,
                          value: settings.isLinearConfigured ? "Connected" : "Not connected")
                StatusRow(label: "Custom MCP servers", ok: !settings.customTrackers.isEmpty,
                          value: settings.customTrackers.isEmpty ? "None" : "\(settings.customTrackers.count)")
            }

            Section {
                Text("Keys and tokens are stored in your macOS Keychain. Preferences live in UserDefaults, and the codebase is a read-only security-scoped bookmark.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatusRow: View {
    let label: String
    let ok: Bool
    let value: String

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Text(value).foregroundStyle(ok ? .primary : .secondary)
                Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(ok ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
            }
        }
    }
}

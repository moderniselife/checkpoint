import SwiftUI

// MARK: - AI provider

/// All providers come from `LLMProvider.allCases` — adding a case there
/// automatically shows up here. The two `*Compatible` cases are the generic
/// escape hatch for any local/gateway server.
struct AIProviderPane: View {
    @Environment(AppSettings.self) private var settings
    @State private var llmState: ConnectionTestState = .idle
    @State private var fetchedModels: [String] = []
    @State private var fetchingModels = false

    var body: some View {
        @Bindable var settings = settings
        SettingsDetailContainer(section: .aiProvider) {
            SettingsCard(title: "Provider") {
                SettingsRow(label: "Provider", systemImage: "cpu", tint: .purple) {
                    Picker("Provider", selection: $settings.provider) {
                        ForEach(LLMProvider.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .onChange(of: settings.provider) { llmState = .idle; fetchedModels = [] }
                }
                CardDivider()
                if settings.provider.hasEditableBaseURL {
                    SettingsRow(label: "Base URL", systemImage: "link", tint: .secondary) {
                        TextField("Base URL", text: $settings.llmBaseURL, prompt: Text(settings.provider.defaultBaseURL))
                            .font(.body.monospaced())
                            .multilineTextAlignment(.trailing)
                    }
                    CardDivider()
                }
                SettingsRow(label: "API key", systemImage: "key.fill", tint: .orange) {
                    SecureField(settings.provider.requiresKey ? "API key" : "API key (optional)",
                                text: $settings.llmKey, prompt: Text(settings.provider.keyPrompt))
                        .multilineTextAlignment(.trailing)
                }
                CardDivider()
                SettingsRow(label: "Model", systemImage: "text.bubble", tint: .blue) {
                    HStack {
                        TextField("Model", text: $settings.model, prompt: Text(settings.provider.defaultModel))
                            .font(.body.monospaced())
                            .multilineTextAlignment(.trailing)
                        Menu {
                            let options = fetchedModels.isEmpty && settings.provider == .anthropic
                                ? AppSettings.claudeModels : fetchedModels
                            if options.isEmpty { Text("Fetch models to see what's available") }
                            ForEach(options, id: \.self) { m in Button(m) { settings.model = m } }
                            Divider()
                            Button("Fetch models from \(settings.provider.shortLabel)", systemImage: "arrow.down.circle", action: fetchModels)
                        } label: {
                            if fetchingModels { ProgressView().controlSize(.small) } else { Image(systemName: "list.bullet") }
                        }
                        .menuStyle(.button)
                        .fixedSize()
                        .help("Pick a model")
                    }
                }
                CardDivider()
                SettingsRow(label: "Effort", systemImage: "gauge.with.dots.needle.67percent", tint: .green) {
                    Picker("Effort", selection: $settings.effort) {
                        ForEach(AppSettings.efforts, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
                CardDivider()
                SettingsRow(label: "Quick model", systemImage: "hare", tint: .teal) {
                    TextField("Quick model", text: $settings.quickModel,
                              prompt: Text("same model, low effort"))
                        .font(.body.monospaced())
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                if let url = settings.provider.keyURL {
                    Link("Get a \(settings.provider.shortLabel) API key", destination: url)
                }
                Text(providerNote).foregroundStyle(.secondary)
                Text("Quick plans use the quick model (or the same model) at low effort.").foregroundStyle(.secondary)
            }

            SettingsCard(title: "Connection") {
                HStack {
                    Button("Test model", action: testLLM)
                        .buttonStyle(.glass)
                        .disabled(!settings.isLLMConfigured || llmState == .testing)
                    switch llmState {
                    case .idle: Text("Sends a tiny “reply OK” prompt.").font(.caption).foregroundStyle(.secondary)
                    case .testing: ProgressView().controlSize(.small)
                    case .ok(let msg, _): Label(msg, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    case .failed(let msg): Text(msg).foregroundStyle(.red).font(.caption).lineLimit(3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }

    private var providerNote: String {
        switch settings.provider {
        case .anthropic: "Claude gets adaptive thinking, schema-enforced plans and automatic refusal fallbacks."
        case .openAICompatible: "Ollama, LM Studio, vLLM, llama.cpp… Use a model with tool calling. Big epics need a large context window. Effort also caps how long a runaway thinker may yap before Checkpoint moves on."
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
        SettingsDetailContainer(section: .testing) {
            SettingsCard(title: "Default mode") {
                Picker("Default mode", selection: $settings.mode) {
                    ForEach(TestMode.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 10)
                Text(modeHelp)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 10)
            }
            SettingsCard(title: "Hosted environment") {
                SettingsRow(label: "Environment", systemImage: "globe", tint: .blue) {
                    TextField("Hosted environment", text: $settings.qaEnvironment,
                              prompt: Text("https://app.dev.example.com (DEV)"))
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("QA mode writes black-box, UI-only plans for the hosted app. The environment is where QA plans point you.")
            }
            SettingsCard(title: "House rules") {
                TextEditor(text: $settings.houseRules)
                    .font(.body)
                    .frame(minHeight: 70)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                Text("\(settings.houseRules.count)/1000 — appended to every generation prompt.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 10)
                    .onChange(of: settings.houseRules) { _, _ in
                        if settings.houseRules.count > 1000 {
                            settings.houseRules = String(settings.houseRules.prefix(1000))
                        }
                    }
            } footer: {
                Text("Standing instructions like “always check Safari” or “use tenant X”.")
            }
        }
    }

    private var modeHelp: String {
        settings.mode == .qa
            ? "QA — black-box plans for testing the hosted app, no code or local setup."
            : "Dev — plans can reference code, branches and local setup."
    }
}

// MARK: - Scenarios

struct ScenariosPane: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsDetailContainer(section: .scenarios) {
            SettingsCard(title: "End-to-end journeys") {
                Picker("Scenarios", selection: $settings.scenarioMode) {
                    ForEach(ScenarioMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .padding(.horizontal, 16).padding(.vertical, 10)
                CardDivider()
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
                .padding(.horizontal, 16).padding(.vertical, 10)
            } footer: {
                Text("Adds 3–6 end-to-end user journeys to each plan. From related tickets uses your tracker only; tickets + codebase also reads a local repo — read-only, and only the folder you choose.")
            }
        }
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsDetailContainer(section: .advanced) {
            SettingsCard(title: "Routing") {
                if settings.isAtlassianConfigured && settings.isLinearConfigured {
                    SettingsRow(label: "Bare keys go to", systemImage: "arrow.triangle.branch", tint: .blue) {
                        Picker("Bare keys go to", selection: $settings.defaultTracker) {
                            ForEach(Tracker.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                    }
                } else {
                    Text("Pasted links pick Jira or Linear automatically. Connect both trackers to choose where bare keys (PROJ-12) go.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
            SettingsCard(title: "Status") {
                LabeledRow(icon: "brain.head.profile", label: "AI provider", value: settings.isLLMConfigured ? "Configured (\(settings.provider.shortLabel))" : "Needs setup", ok: settings.isLLMConfigured)
                CardDivider()
                LabeledRow(icon: "square.stack.3d.up", label: "Jira", value: settings.isAtlassianConfigured ? "Connected" : "Not connected", ok: settings.isAtlassianConfigured)
                CardDivider()
                LabeledRow(icon: "line.3.horizontal.decrease.circle", label: "Linear", value: settings.isLinearConfigured ? "Connected" : "Not connected", ok: settings.isLinearConfigured)
                CardDivider()
                LabeledRow(icon: "cable.connector", label: "Custom MCP", value: settings.customTrackers.isEmpty ? "None added" : "\(settings.customTrackers.count) server(s)", ok: !settings.customTrackers.isEmpty)
            }
            SettingsCard(title: "Storage") {
                Text("Keys are stored in your macOS Keychain. Preferences live in UserDefaults; the codebase bookmark is a read-only security-scoped bookmark.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }
}

private struct LabeledRow: View {
    let icon: String
    let label: String
    let value: String
    let ok: Bool

    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
            Text(label)
            Spacer()
            Text(value).font(.caption).foregroundStyle(ok ? .green : .secondary)
            StatusDot(state: ok ? .ok : .warn)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

/// Scrollable detail wrapper: header + centered narrow column that grows on
/// large monitors and scrolls on small MacBooks. No fixed sizes.
struct SettingsDetailContainer<Content: View>: View {
    let section: SettingsSection
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsHeader(icon: section.icon, tint: section.tint, title: section.title, subtitle: section.subtitle)
                VStack(spacing: 16) {
                    content
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

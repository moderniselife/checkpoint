import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var testState: TestState = .idle
    @State private var signingIn = false

    enum TestState: Equatable { case idle, testing, ok(String, Int), failed(String) }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                SecureField("API key", text: $settings.anthropicKey, prompt: Text("sk-ant-…"))
                Picker("Model", selection: $settings.model) {
                    ForEach(AppSettings.models, id: \.self) { Text($0) }
                }
                Picker("Effort", selection: $settings.effort) {
                    ForEach(AppSettings.efforts, id: \.self) { Text($0.capitalized) }
                }
            } header: {
                Text("Anthropic")
            } footer: {
                Link("Get an API key", destination: URL(string: "https://platform.claude.com/settings/keys")!)
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
                Text("Keys are stored in your macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func signIn() {
        signingIn = true
        testState = .idle
        Task {
            defer { signingIn = false }
            do {
                try await AtlassianOAuth.shared.signIn()
                settings.atlassianUser = (try? await settings.makeMCPClient().whoAmI()) ?? "Signed in"
            } catch AtlassianOAuth.OAuthError.cancelled {
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }

    private func signOut() {
        Task { await AtlassianOAuth.shared.signOut() }
        settings.atlassianUser = nil
        testState = .idle
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

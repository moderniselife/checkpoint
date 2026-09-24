import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var testState: TestState = .idle

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
                TextField("Jira site", text: $settings.site, prompt: Text("yourcompany.atlassian.net"))
                TextField("Email", text: $settings.atlassianEmail, prompt: Text("you@company.com"))
                SecureField("API token", text: $settings.atlassianToken)
                HStack {
                    Button("Test connection", action: test)
                        .disabled(settings.atlassianEmail.isEmpty || settings.atlassianToken.isEmpty || testState == .testing)
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
                    Link("Create an Atlassian API token", destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                    Text("Your org admin must allow API-token auth for the Rovo MCP server. Checkpoint only ever uses read-only tools.")
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

    private func test() {
        testState = .testing
        let client = MCPClient(authHeader: settings.atlassianAuthHeader)
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

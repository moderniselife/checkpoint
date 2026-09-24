import SwiftUI

struct TicketInputBar: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var input = ""
    @FocusState private var focused: Bool
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "ticket")
                        .foregroundStyle(.secondary)
                    TextField("Jira key or link — e.g. PROJ-123", text: $input)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($focused)
                        .onSubmit(submit)
                        .disabled(store.isRunning)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("field", in: glass)

                if store.isRunning {
                    Button("Stop", systemImage: "stop.fill") { store.cancel() }
                        .buttonStyle(.glass)
                        .controlSize(.extraLarge)
                        .glassEffectID("action", in: glass)
                } else {
                    Button("Analyze", systemImage: "sparkles", action: submit)
                        .buttonStyle(.glassProminent)
                        .controlSize(.extraLarge)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(PlanStore.extractKey(input) == nil)
                        .glassEffectID("action", in: glass)
                }
            }
        }
        .frame(maxWidth: 720)
        .animation(.smooth, value: store.isRunning)
        .onAppear { focused = true }
        .background {
            // ⌘L jumps to the field from anywhere.
            Button("") { focused = true }
                .keyboardShortcut("l", modifiers: .command)
                .hidden()
        }
    }

    private func submit() {
        store.analyze(input, settings: settings)
        if store.error == nil { input = "" }
    }
}

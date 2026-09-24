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
                    // Custom placeholder: macOS hides the built-in one as soon as the field
                    // is focused, and this field auto-focuses, so it was never visible.
                    TextField("", text: $input)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .background(alignment: .leading) {
                            if input.isEmpty {
                                Text("Jira key or link — e.g. PROJ-123")
                                    .font(.title3)
                                    .foregroundStyle(.tertiary)
                                    .allowsHitTesting(false)
                            }
                        }
                        .focused($focused)
                        .onSubmit(submit)
                        .disabled(store.isRunning)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("field", in: glass)

                ModeToggle()
                    .glassEffectID("mode", in: glass)

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

/// Dev / QA switch that sits in the glass input bar. ⌘⇧M flips it.
private struct ModeToggle: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlanStore.self) private var store

    var body: some View {
        @Bindable var settings = settings
        HStack(spacing: 2) {
            ForEach(TestMode.allCases) { mode in
                let selected = settings.mode == mode
                Button {
                    withAnimation(.smooth) { settings.mode = mode }
                } label: {
                    Label(mode.label, systemImage: mode.icon)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .background {
                            if selected {
                                Capsule().fill(mode == .qa ? Color.teal.gradient : Color.indigo.gradient)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help(mode.help)
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(store.isRunning)
        .background {
            Button("") { settings.mode = settings.mode == .dev ? .qa : .dev }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .hidden()
        }
    }
}

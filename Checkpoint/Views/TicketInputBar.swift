import SwiftUI

struct TicketInputBar: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var input = ""
    @State private var template: PlanGenerator.PlanTemplate = .auto
    @State private var quick = false
    @FocusState private var focused: Bool
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 10) {
                // Row 1: the field gets the full width; Analyze never squeezes it.
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        if settings.isAtlassianConfigured && settings.isLinearConfigured {
                            TrackerMenu()
                        } else {
                            Image(systemName: "ticket")
                                .foregroundStyle(.secondary)
                        }
                        // Custom placeholder: macOS hides the built-in one as soon as the field
                        // is focused, and this field auto-focuses, so it was never visible.
                        TextField("", text: $input)
                            .textFieldStyle(.plain)
                            .font(.title3)
                            .background(alignment: .leading) {
                                if input.isEmpty {
                                    Text(placeholder)
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
                // Row 2: option pills get their own line so nothing ever squishes.
                HStack(spacing: 10) {
                    ModeToggle()
                        .glassEffectID("mode", in: glass)
                    TemplateMenu(template: $template)
                        .glassEffectID("template", in: glass)
                    QuickDeepToggle(quick: $quick)
                        .glassEffectID("depth", in: glass)
                    ScenarioMenu()
                        .glassEffectID("scenarios", in: glass)
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

    private var placeholder: String {
        switch settings.connectedTrackers {
        case [.linear]: "Linear issue ID or link — e.g. ENG-123"
        case [.jira, .linear]: "Jira or Linear key, or paste a link"
        default: "Jira key or link — e.g. PROJ-123"
        }
    }

    private func submit() {
        if quick {
            let q = PlanStore.quickOverrides(settings: settings)
            store.analyze(input, template: template == .auto ? nil : template,
                          modelOverride: q.model, effortOverride: q.effort, settings: settings)
        } else {
            store.analyze(input, template: template == .auto ? nil : template, settings: settings)
        }
        if store.error == nil { input = "" }
    }
}

/// Quick (cheap, low effort) vs Deep (best model + effort) plans.
private struct QuickDeepToggle: View {
    @Binding var quick: Bool
    @Environment(PlanStore.self) private var store

    var body: some View {
        Button {
            withAnimation(.smooth) { quick.toggle() }
        } label: {
            Label(quick ? "Quick" : "Deep", systemImage: quick ? "hare" : "tortoise")
                .font(.callout.weight(quick ? .semibold : .regular))
                .foregroundStyle(quick ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background { if quick { Capsule().fill(Color.teal.gradient) } }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(store.isRunning)
        .help(quick ? "Quick plan: cheaper model at low effort" : "Deep plan: your best model and effort")
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

/// Picks where bare keys are looked up when both Jira and Linear are connected.
private struct TrackerMenu: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Menu {
            ForEach(Tracker.allCases) { t in
                Button { settings.defaultTracker = t } label: {
                    Label(t.label, systemImage: settings.defaultTracker == t ? "checkmark" : t.icon)
                }
            }
        } label: {
            Text(settings.defaultTracker.label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Bare keys are looked up in \(settings.defaultTracker.label). Pasted links are detected automatically.")
    }
}

/// Plan shape override: auto (from ticket type), bug, feature or epic.
private struct TemplateMenu: View {
    @Binding var template: PlanGenerator.PlanTemplate
    @Environment(PlanStore.self) private var store

    var body: some View {
        let forced = template != .auto
        Menu {
            ForEach(PlanGenerator.PlanTemplate.allCases, id: \.self) { t in
                Button {
                    template = t
                } label: {
                    Label(t.label, systemImage: template == t ? "checkmark" : "doc.badge.gearshape")
                }
            }
        } label: {
            Label(forced ? template.label : "Template", systemImage: "doc.badge.gearshape")
                .font(.callout.weight(forced ? .semibold : .regular))
                .foregroundStyle(forced ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background { if forced { Capsule().fill(Color.orange.gradient) } }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(store.isRunning)
        .help("Plan shape: auto follows the ticket type")
    }
}

/// Optional scenario generation: off, from related tickets, or tickets + a local codebase.
private struct ScenarioMenu: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlanStore.self) private var store

    var body: some View {
        let on = settings.scenarioMode != .off
        Menu {
            ForEach(ScenarioMode.allCases) { m in
                Button {
                    if m == .ticketsAndCode && settings.codebaseBookmark == nil { settings.chooseCodebase() }
                    if m != .ticketsAndCode || settings.codebaseBookmark != nil { settings.scenarioMode = m }
                } label: {
                    Label(m.label, systemImage: settings.scenarioMode == m ? "checkmark" : icon(m))
                }
            }
            Divider()
            if let path = settings.codebasePath {
                Text("Codebase: \((path as NSString).lastPathComponent)")
            }
            Button(settings.codebasePath == nil ? "Choose Codebase…" : "Change Codebase…", systemImage: "folder") {
                settings.chooseCodebase()
            }
        } label: {
            Label(on ? settings.scenarioMode.shortLabel : "Scenarios", systemImage: "theatermasks")
                .font(.callout.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background { if on { Capsule().fill(Color.purple.gradient) } }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(store.isRunning)
        .help("Optional: also generate end-to-end test scenarios")
    }

    private func icon(_ m: ScenarioMode) -> String {
        switch m {
        case .off: "xmark.circle"
        case .tickets: "ticket"
        case .ticketsAndCode: "chevron.left.forwardslash.chevron.right"
        }
    }
}

import SwiftUI

struct TicketInputBar: View {
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var input = ""
    @State private var template: PlanGenerator.PlanTemplate = .auto
    @State private var quick = false
    @FocusState private var focused: Bool
    @Namespace private var glass
    /// Width the bar actually gets; below ~700pt the pills drop their labels.
    @State private var width: CGFloat = 760
    private var compact: Bool { width < 700 }

    /// iPhone: field and Analyze on one row, options on the row below.
    var stacked = false

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            if stacked {
                // One row on iPhone: scenarios move into the field's options menu.
                HStack(spacing: 8) {
                    field
                    ModeToggle(compact: true)
                        .glassEffectID("mode", in: glass)
                        .tourStop(.modeToggle)
                    action
                }
            } else {
                HStack(spacing: 12) {
                    field
                    ModeToggle(compact: compact)
                        .glassEffectID("mode", in: glass)
                        .tourStop(.modeToggle)
                    ScenarioMenu(compact: compact)
                        .glassEffectID("scenarios", in: glass)
                    action
                }
            }
        }
        .frame(maxWidth: 760)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .animation(.smooth, value: store.isRunning)
        .animation(.smooth, value: compact)
        .onAppear {
            // Mac: type straight away. iOS: don't throw the keyboard up on launch.
            if Platform.isMac { focused = true }
        }
        .background {
            // ⌘L jumps to the field from anywhere.
            Button("") { focused = true }
                .keyboardShortcut("l", modifiers: .command)
                .hidden()
        }
    }

    private var field: some View {
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
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                }
                .focused($focused)
                .onSubmit(submit)
                .disabled(store.isRunning)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.go)
                #endif
            PlanOptionsMenu(template: $template, quick: $quick, showScenarios: stacked)
                .tourStop(.runOptions)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("field", in: glass)
        .tourStop(.ticketBar)
    }

    @ViewBuilder
    private var action: some View {
        if store.isRunning {
            Button("Stop", systemImage: "stop.fill") { store.cancel() }
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .buttonStyle(.glass)
                .controlSize(.extraLarge)
                .glassEffectID("action", in: glass)
        } else {
            Button("Analyze", systemImage: "sparkles", action: submit)
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .help("Analyze (⌘Return)")
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(PlanStore.extractKey(input) == nil)
                .glassEffectID("action", in: glass)
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

/// Dev / QA switch that sits in the glass input bar. ⌘⇧M flips it.
private struct ModeToggle: View {
    var compact = false
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
                        .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                        .lineLimit(1)
                        .fixedSize()
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .padding(.horizontal, compact ? 10 : 12)
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

/// Quiet in-field menu for per-run options: plan shape and Quick vs Deep.
/// Shows just an icon until something differs from the defaults.
private struct PlanOptionsMenu: View {
    @Binding var template: PlanGenerator.PlanTemplate
    @Binding var quick: Bool
    /// iPhone has no room for the Scenarios pill, so it lives in here.
    var showScenarios = false
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings

    private var summary: String? {
        let scen = showScenarios && settings.scenarioMode != .off ? "Scenarios" : nil
        let parts = [quick ? "Quick" : nil, template == .auto ? nil : template.label, scen].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        Menu {
            Picker("Depth", selection: $quick) {
                Label("Deep — best model and effort", systemImage: "tortoise").tag(false)
                Label("Quick — cheaper model, low effort", systemImage: "hare").tag(true)
            }
            .pickerStyle(.inline)
            Picker("Plan shape", selection: $template) {
                ForEach(PlanGenerator.PlanTemplate.allCases, id: \.self) { t in
                    Text(t == .auto ? "Auto (from ticket type)" : t.label).tag(t)
                }
            }
            .pickerStyle(.inline)
            if showScenarios {
                @Bindable var settings = settings
                Picker("Scenarios", selection: $settings.scenarioMode) {
                    ForEach(ScenarioMode.available) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                if let summary { Text(summary).font(.callout.weight(.semibold)) }
            }
            .foregroundStyle(summary == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.white))
            .padding(.horizontal, summary == nil ? 6 : 10)
            .padding(.vertical, 5)
            .background { if summary != nil { Capsule().fill(Color.orange.gradient) } }
            .contentShape(.capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(store.isRunning)
        .help(summary.map { "This run: \($0)" } ?? "Run options: Quick or Deep, and plan shape")
    }
}

/// Optional scenario generation: off, from related tickets, or tickets + a local codebase.
private struct ScenarioMenu: View {
    var compact = false
    @Environment(AppSettings.self) private var settings
    @Environment(PlanStore.self) private var store

    var body: some View {
        let on = settings.scenarioMode != .off
        Menu {
            ForEach(ScenarioMode.available) { m in
                Button {
                    if m == .ticketsAndCode && settings.codebaseBookmark == nil { settings.chooseCodebase() }
                    if m != .ticketsAndCode || settings.codebaseBookmark != nil { settings.scenarioMode = m }
                } label: {
                    Label(m.label, systemImage: settings.scenarioMode == m ? "checkmark" : icon(m))
                }
            }
            if AppSettings.supportsCodebase {
                Divider()
                if let path = settings.codebasePath {
                    Text("Codebase: \((path as NSString).lastPathComponent)")
                }
                Button(settings.codebasePath == nil ? "Choose Codebase…" : "Change Codebase…", systemImage: "folder") {
                    settings.chooseCodebase()
                }
            }
        } label: {
            Label(on ? settings.scenarioMode.shortLabel : "Scenarios", systemImage: "theatermasks")
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .lineLimit(1)
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

/// Type-erased label style, so a view can switch between icon-only and full labels.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

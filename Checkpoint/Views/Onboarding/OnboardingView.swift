import SwiftUI

/// First-run welcome, shared by the Mac and iOS apps: what Checkpoint does, how you
/// test, your AI provider, trackers and sync. Everything past the intro is skippable
/// and can be changed later in Settings.
struct OnboardingView: View {
    var onFinish: () -> Void

    enum Step: Int, CaseIterable {
        case welcome, how, mode, ai, trackers, sync, ready
    }

    @State private var step: Step = .welcome
    @State private var forward = true
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var compact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            OnboardingBackdrop(step: step)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if step != .welcome && step != .ready {
                        Button("Skip") { go(to: .ready) }
                            .buttonStyle(.plain)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
                .frame(height: 36)
                .padding(.horizontal, 24)
                .padding(.top, 16)

                ZStack {
                    page(step)
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: 620, maxHeight: .infinity)
                .padding(.horizontal, compact ? 20 : 40)
                .clipped()

                if step != .welcome {
                    controls
                        .padding(.horizontal, 24)
                        .padding(.bottom, compact ? 12 : 28)
                }
            }
        }
        .animation(.spring(duration: 0.55, bounce: 0.18), value: step)
    }

    @ViewBuilder
    private func page(_ step: Step) -> some View {
        switch step {
        case .welcome: WelcomePage { go(to: .how) }
        case .how: HowItWorksPage()
        case .mode: ModePage()
        case .ai: AIPage()
        case .trackers: TrackersPage()
        case .sync: SyncPage()
        case .ready: ReadyPage(onFinish: onFinish)
        }
    }

    private var controls: some View {
        HStack {
            Button {
                if let prev = Step(rawValue: step.rawValue - 1) { go(to: prev) }
            } label: {
                Label("Back", systemImage: "chevron.left").labelStyle(.iconOnly)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .opacity(step == .ready ? 0 : 1)
            .disabled(step == .ready)

            Spacer()
            PageDots(count: Step.allCases.count - 1, index: step.rawValue - 1)
            Spacer()

            if step == .ready {
                Color.clear.frame(width: 44, height: 44)
            } else {
                Button {
                    if let next = Step(rawValue: step.rawValue + 1) { go(to: next) }
                } label: {
                    Label("Continue", systemImage: "chevron.right").labelStyle(.iconOnly)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: 620)
    }

    private func go(to new: Step) {
        forward = new.rawValue > step.rawValue
        step = new
    }
}

// MARK: - Backdrop

/// Slow-moving mesh in the app's colours; hue leans with each step.
private struct OnboardingBackdrop: View {
    let step: OnboardingView.Step
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let d = scheme == .dark
            let a = Float(sin(t * 0.35)) * 0.12, b = Float(cos(t * 0.27)) * 0.12
            let shift = Double(step.rawValue) * 0.06
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5 + a, 0], [1, 0],
                    [0, 0.5 - b], [0.5 + b, 0.5 + a], [1, 0.5 + b],
                    [0, 1], [0.5 - a, 1], [1, 1],
                ],
                colors: [
                    tone(.indigo, d, 0 + shift), tone(.purple, d, shift), tone(.teal, d, shift),
                    tone(.blue, d, shift), tone(.mint, d, shift), tone(.indigo, d, shift),
                    tone(.teal, d, shift), tone(.pink, d, shift), tone(.purple, d, shift),
                ])
        }
        .overlay(Color.primary.opacity(0.02))
    }

    private func tone(_ c: Color, _ dark: Bool, _ shift: Double) -> Color {
        dark ? c.opacity(0.55 - shift * 0.3).mix(with: .black, by: 0.55)
             : c.opacity(0.35 + shift * 0.2).mix(with: .white, by: 0.55)
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.35)))
                    .frame(width: i == index ? 22 : 7, height: 7)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .animation(.spring(duration: 0.4), value: index)
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}

/// Title + subtitle block used on every page.
private struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Welcome

private struct WelcomePage: View {
    let start: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            OrbitHero()
                .frame(width: 300, height: 300)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
            VStack(spacing: 12) {
                Text("Checkpoint")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.indigo, .teal], startPoint: .leading, endPoint: .trailing))
                Text("Paste a ticket. Get a test plan.")
                    .font(.title2.weight(.semibold))
                Text("Checkpoint reads the ticket, its comments, children and specs, then tells you exactly what to test and what counts as done.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            .offset(y: appeared ? 0 : 16)
            .opacity(appeared ? 1 : 0)
            Spacer(minLength: 0)
            Button(action: start) {
                Label("Get Started", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.headline)
                    .frame(minWidth: 200)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .opacity(appeared ? 1 : 0)
            .padding(.bottom, 28)
        }
        .onAppear { withAnimation(.spring(duration: 0.9, bounce: 0.25).delay(0.1)) { appeared = true } }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.title; configuration.icon }
    }
}

/// The logo floating in glass, with the things a plan is made of orbiting it.
private struct OrbitHero: View {
    private let chips: [(String, String, Color)] = [
        ("PROJ-123", "ticket", .indigo), ("P0", "exclamationmark.triangle.fill", .red),
        ("Pass", "checkmark.circle.fill", .green), ("AC met", "checkmark.seal.fill", .teal),
        ("ENG-42", "ticket", .purple), ("Blocked", "exclamationmark.circle.fill", .orange),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.indigo.opacity(0.35), .teal.opacity(0.15), .clear],
                                         center: .center, startRadius: 10, endRadius: 150))
                    .scaleEffect(1 + 0.04 * sin(t * 1.2))
                Circle()
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    .padding(22)
                ForEach(Array(chips.enumerated()), id: \.offset) { i, chip in
                    let angle = t * 0.32 + Double(i) / Double(chips.count) * 2 * .pi
                    let rx = 128.0, ry = 112.0
                    OrbitChip(text: chip.0, icon: chip.1, tint: chip.2)
                        .scaleEffect(0.82 + 0.18 * (sin(angle) + 1) / 2)
                        .opacity(0.55 + 0.45 * (sin(angle) + 1) / 2)
                        .offset(x: cos(angle) * rx, y: sin(angle) * ry * 0.55)
                        .zIndex(sin(angle))
                }
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .shadow(color: .indigo.opacity(0.35), radius: 24, y: 10)
                    .offset(y: 5 * sin(t * 1.1))
                    .zIndex(0.5)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct OrbitChip: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.primary)
            .symbolRenderingMode(.multicolor)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassEffect(.regular.tint(tint.opacity(0.18)), in: .capsule)
            .fixedSize()
    }
}

// MARK: - How it works

private struct HowItWorksPage: View {
    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)
            PageHeader(title: "From ticket to tested",
                       subtitle: "No more ten tabs. Checkpoint does the reading and hands you a plan you can tick off.")
            LivePlanDemo()
                .frame(maxWidth: 440)
            HStack(alignment: .top, spacing: 14) {
                Beat(icon: "doc.text.magnifyingglass", title: "Reads", text: "Ticket, comments, children, linked specs")
                Beat(icon: "sparkles", title: "Plans", text: "Steps, expected results, edge cases")
                Beat(icon: "checkmark.seal", title: "Proves", text: "Pass, fail or block every check")
            }
            .frame(maxWidth: 520)
            Spacer(minLength: 0)
        }
    }
}

private struct Beat: View {
    let icon: String
    let title: String
    let text: String
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: bounce)
                .frame(width: 48, height: 48)
                .glassEffect(.regular, in: .circle)
            Text(title).font(.headline)
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .onAppear { bounce.toggle() }
    }
}

/// A tiny plan that ticks itself off, row by row, on a loop.
private struct LivePlanDemo: View {
    private let rows = ["Save a card during checkout", "Guest checkout doesn't offer saving",
                        "Declined card is never saved", "Remove a saved card"]
    @State private var ticked = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("PROJ-123").font(.subheadline.monospaced().weight(.semibold))
                Text("Save a card for next time").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                ZStack {
                    ProgressRing(value: Double(ticked) / Double(rows.count), lineWidth: 4)
                    Text("\(ticked)").font(.caption2.monospacedDigit().weight(.bold))
                }
                .frame(width: 28, height: 28)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                let done = i < ticked
                HStack(spacing: 10) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                    Text(row)
                        .strikethrough(done)
                        .foregroundStyle(done ? .secondary : .primary)
                    Spacer()
                    if i == 0 {
                        Text("P0").font(.caption2.weight(.bold)).foregroundStyle(.red)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(.red.opacity(0.12), in: .capsule)
                    }
                }
                .font(.callout)
                .padding(10)
                .background(.background.opacity(done ? 0.25 : 0.6), in: .rect(cornerRadius: 12))
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(ticked == rows.count ? 2.2 : 0.9))
                withAnimation(.spring(duration: 0.45)) { ticked = ticked == rows.count ? 0 : ticked + 1 }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Mode

private struct ModePage: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)
            PageHeader(title: "How do you test?",
                       subtitle: "Pick your usual. You can flip it for any ticket from the input bar.")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { cards }
                VStack(spacing: 14) { cards }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var cards: some View {
        ModeCard(mode: .dev, title: "I'm the developer",
                 text: "Plans can mention branches, APIs, logs and local setup — for checking your own change.",
                 tint: .indigo, selected: settings.mode == .dev) { settings.mode = .dev }
        ModeCard(mode: .qa, title: "I'm testing the app",
                 text: "Black-box plans in UI terms only, aimed at the hosted environment — for QA and sign-off.",
                 tint: .teal, selected: settings.mode == .qa) { settings.mode = .qa }
    }
}

private struct ModeCard: View {
    let mode: TestMode
    let title: String
    let text: String
    let tint: Color
    let selected: Bool
    let pick: () -> Void

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.35)) { pick() }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: mode.icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(tint.gradient, in: .rect(cornerRadius: 13))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(mode.label).font(.caption.weight(.bold)).foregroundStyle(tint).textCase(.uppercase)
                Text(title).font(.title3.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
            .glassEffect(selected ? .regular.tint(tint.opacity(0.22)).interactive() : .regular.interactive(),
                         in: .rect(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(selected ? tint.opacity(0.7) : .clear, lineWidth: 2))
            .scaleEffect(selected ? 1.02 : 1)
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI

private struct AIPage: View {
    @Environment(AppSettings.self) private var settings
    @State private var testing = false
    @State private var result: Result<String, Error>?

    private let featured: [LLMProvider] = [.anthropic, .openai, .gemini, .xai, .openrouter, .openAICompatible]

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            PageHeader(title: "Choose your AI",
                       subtitle: "Checkpoint uses your own key, sent straight to the provider. Claude writes the best plans.")
            FlowLayout(spacing: 8) {
                ForEach(featured) { p in
                    let on = settings.provider == p
                    Button {
                        withAnimation(.spring(duration: 0.3)) { settings.provider = p; result = nil }
                    } label: {
                        HStack(spacing: 6) {
                            Text(p == .openAICompatible ? "Local model" : p.shortLabel)
                            if p == .anthropic {
                                Image(systemName: "star.fill").font(.caption2)
                                    .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.yellow))
                            }
                        }
                        .font(.callout.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background { if on { Capsule().fill(Color.accentColor.gradient) } }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 520)

            VStack(spacing: 12) {
                if settings.provider.hasEditableBaseURL {
                    field(icon: "link") {
                        TextField("Server URL", text: $settings.llmBaseURL, prompt: Text(settings.provider.defaultBaseURL))
                            .font(.body.monospaced())
                            .noAutocorrect()
                    }
                }
                field(icon: "key.fill") {
                    SecureField(settings.provider.requiresKey ? "API key" : "API key (optional)",
                                text: $settings.llmKey, prompt: Text(settings.provider.keyPrompt))
                        .noAutocorrect()
                }
                HStack {
                    if let url = settings.provider.keyURL {
                        Link(destination: url) { Label("Get a \(settings.provider.shortLabel) key", systemImage: "arrow.up.right") }
                            .font(.callout)
                    }
                    Spacer()
                    Button {
                        test()
                    } label: {
                        if testing { ProgressView().controlSize(.small) } else { Text("Test Key") }
                    }
                    .buttonStyle(.glass)
                    .disabled(!settings.isLLMConfigured || testing)
                }
                if let result {
                    switch result {
                    case .success(let reply):
                        Label("Connected — \(settings.llmConfig.model) replied “\(reply.prefix(20))”", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.callout)
                            .transition(.scale.combined(with: .opacity))
                    case .failure(let error):
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.callout).lineLimit(3)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 520)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))

            Text("Keys stay in this device's Keychain and never sync.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func field<C: View>(icon: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
            content().textFieldStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(.background.opacity(0.6), in: .rect(cornerRadius: 12))
    }

    private func test() {
        testing = true
        result = nil
        Task {
            defer { testing = false }
            do {
                let reply = try await settings.testModel()
                withAnimation(.spring(duration: 0.4)) { result = .success(reply.isEmpty ? "OK" : reply) }
            } catch {
                withAnimation { result = .failure(error) }
            }
        }
    }
}

// MARK: - Trackers

private struct TrackersPage: View {
    @Environment(AppSettings.self) private var settings
    @State private var busy: Tracker?
    @State private var error: String?

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            PageHeader(title: "Connect your tracker",
                       subtitle: "Checkpoint only ever reads. It can't change a ticket, by design.")
            VStack(spacing: 14) {
                TrackerCard(name: "Jira", icon: "square.stack.3d.up.fill", tint: .blue,
                            connected: settings.isAtlassianConfigured, who: settings.atlassianUser,
                            busy: busy == .jira) {
                    TextField("Jira site", text: $settings.site, prompt: Text("yourcompany.atlassian.net"))
                        .textFieldStyle(.plain)
                        .noAutocorrect()
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(.background.opacity(0.6), in: .rect(cornerRadius: 10))
                } connect: {
                    signIn(.jira)
                }
                TrackerCard(name: "Linear", icon: "circle.hexagongrid.fill", tint: .purple,
                            connected: settings.isLinearConfigured, who: settings.linearUser,
                            busy: busy == .linear) {
                    EmptyView()
                } connect: {
                    signIn(.linear)
                }
            }
            .frame(maxWidth: 520)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
            }
            Text("Prefer an API token, or a custom MCP server? Settings has those too.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func signIn(_ tracker: Tracker) {
        busy = tracker
        error = nil
        Task {
            defer { busy = nil }
            do {
                switch tracker {
                case .jira:
                    settings.atlassianAuth = .oauth
                    try await settings.signInAtlassian()
                case .linear:
                    settings.linearAuth = .oauth
                    try await settings.signInLinear()
                }
            } catch MCPOAuth.OAuthError.cancelled {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct TrackerCard<Extra: View>: View {
    let name: String
    let icon: String
    let tint: Color
    let connected: Bool
    let who: String?
    let busy: Bool
    @ViewBuilder var extra: Extra
    let connect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(tint.gradient, in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    if connected {
                        Label(who ?? "Connected", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        Text("Not connected").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if connected {
                    Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(.green)
                        .symbolEffect(.bounce, value: connected)
                } else if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Sign In", action: connect).buttonStyle(.glassProminent)
                }
            }
            if !connected { extra }
        }
        .padding(16)
        .glassEffect(connected ? .regular.tint(.green.opacity(0.12)) : .regular, in: .rect(cornerRadius: 22))
    }
}

// MARK: - Sync

private struct SyncPage: View {
    @Environment(SyncCoordinator.self) private var sync
    @State private var pickingFolder = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            PageHeader(title: "Your plans, everywhere",
                       subtitle: "Start on the Mac, finish testing on your phone. Ticks, notes and photos follow you.")
            DeviceTrio(active: sync.mode != .off)
                .frame(height: 110)
            VStack(spacing: 10) {
                SyncChoice(title: "iCloud", icon: "icloud.fill", tint: .cyan,
                           text: sync.iCloudAvailable ? "Automatic, through your iCloud account." : "Arrives with the App Store version.",
                           badge: sync.iCloudAvailable ? "Recommended" : "Coming soon",
                           selected: sync.mode == .iCloud) { sync.setMode(.iCloud) }
                    .disabled(!sync.iCloudAvailable)
                SyncChoice(title: "Sync folder", icon: "folder.fill", tint: .blue,
                           text: sync.folderPath.map { "Using \($0)" } ?? "A folder in iCloud Drive. Free.",
                           badge: sync.iCloudAvailable ? nil : "Recommended",
                           selected: sync.mode == .folder) {
                    if sync.hasFolder { sync.setMode(.folder) } else { pickingFolder = true }
                }
                SyncChoice(title: "Just this device", icon: "iphone", tint: .gray,
                           text: "You can turn sync on later in Settings.", badge: nil,
                           selected: sync.mode == .off) { sync.setMode(.off) }
            }
            .frame(maxWidth: 520)
            Spacer(minLength: 0)
        }
        .syncFolderPicker(isPresented: $pickingFolder)
    }
}

private struct SyncChoice: View {
    let title: String
    let icon: String
    let tint: Color
    let text: String
    let badge: String?
    let selected: Bool
    let pick: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(tint.gradient, in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge).font(.caption2.weight(.semibold)).foregroundStyle(tint)
                                .padding(.horizontal, 6).padding(.vertical, 1).background(tint.opacity(0.14), in: .capsule)
                        }
                    }
                    Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(14)
            .glassEffect(selected ? .regular.tint(tint.opacity(0.18)).interactive() : .regular.interactive(),
                         in: .rect(cornerRadius: 20))
            .opacity(enabled ? 1 : 0.55)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

/// Laptop, phone and tablet with a pulse travelling between them while sync is on.
private struct DeviceTrio: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = t.truncatingRemainder(dividingBy: 2.4) / 2.4
            HStack(spacing: 34) {
                device("laptopcomputer", size: 52)
                device("iphone", size: 40)
                device("ipad.landscape", size: 46)
            }
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    Capsule()
                        .fill(LinearGradient(colors: [.clear, .cyan.opacity(active ? 0.9 : 0), .clear],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: 60, height: 3)
                        .position(x: w * 0.15 + (w * 0.7) * phase, y: geo.size.height / 2 + 34)
                        .blur(radius: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func device(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .light))
            .foregroundStyle(active ? AnyShapeStyle(LinearGradient(colors: [.indigo, .cyan], startPoint: .top, endPoint: .bottom))
                                    : AnyShapeStyle(.secondary))
            .symbolEffect(.bounce, value: active)
    }
}

// MARK: - Ready

private struct ReadyPage: View {
    let onFinish: () -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @State private var burst = false

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)
            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    Circle()
                        .fill([Color.indigo, .teal, .purple, .cyan, .mint, .pink][i % 6].gradient)
                        .frame(width: 10, height: 10)
                        .offset(y: burst ? -92 : 0)
                        .rotationEffect(.degrees(Double(i) * 30))
                        .opacity(burst ? 0 : 1)
                        .scaleEffect(burst ? 0.4 : 1)
                }
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .symbolEffect(.bounce, value: burst)
                    .shadow(color: .teal.opacity(0.4), radius: 24, y: 8)
            }
            .frame(height: 190)
            PageHeader(title: "You're all set",
                       subtitle: "Paste a ticket key or link and Checkpoint will get reading.")
            VStack(spacing: 0) {
                summary("Testing as", value: settings.mode.label, ok: true)
                Divider().padding(.leading, 44)
                summary("AI", value: settings.isLLMConfigured ? settings.provider.shortLabel : "Not set up yet", ok: settings.isLLMConfigured)
                Divider().padding(.leading, 44)
                summary("Trackers", value: trackers, ok: settings.isAtlassianConfigured || settings.isLinearConfigured)
                Divider().padding(.leading, 44)
                summary("Sync", value: sync.mode == .off ? "This device only" : sync.mode.label, ok: sync.mode != .off)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: 440)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            Spacer(minLength: 0)
            Button(action: onFinish) {
                Label(settings.isConfigured ? "Analyze Your First Ticket" : "Start Using Checkpoint", systemImage: "sparkles")
                    .font(.headline)
                    .frame(minWidth: 240)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) { burst = true }
        }
    }

    private var trackers: String {
        let names = [settings.isAtlassianConfigured ? "Jira" : nil, settings.isLinearConfigured ? "Linear" : nil].compactMap(\.self)
        return names.isEmpty ? "Not connected yet" : names.joined(separator: " + ")
    }

    private func summary(_ label: String, value: String, ok: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                .frame(width: 20)
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}

// MARK: - Helpers

private extension View {
    func noAutocorrect() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
}

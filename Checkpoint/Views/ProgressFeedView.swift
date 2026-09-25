import SwiftUI

struct ProgressFeedView: View {
    @Environment(PlanStore.self) private var store
    @Environment(TicketInspector.self) private var inspector
    /// Follows the bottom only while the user is already there. Scrolling up
    /// to read (or to collapse a long thought) pauses auto-scroll; scrolling
    /// back down resumes it.
    @State private var pinnedToBottom = true

    /// Consecutive tool calls are grouped into one wrapping row of chips.
    private enum Segment: Identifiable {
        case single(FeedItem)
        case tools([FeedItem])
        var id: UUID {
            switch self {
            case .single(let i): i.id
            case .tools(let items): items[0].id
            }
        }
    }

    private var segments: [Segment] {
        var out: [Segment] = []
        for item in store.feed {
            if item.kind == .tool, case .tools(var group)? = out.last {
                group.append(item)
                out[out.count - 1] = .tools(group)
            } else {
                out.append(item.kind == .tool ? .tools([item]) : .single(item))
            }
        }
        return out
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text("Researching \(store.runningKey ?? "")")
                            .font(.title3.weight(.semibold))
                        ModeBadge(mode: store.runningMode)
                        Spacer()
                        if let key = store.runningKey {
                            Button {
                                withAnimation(.smooth) { inspector.toggle(key, tracker: store.runningTracker) }
                            } label: {
                                Label("Ticket details", systemImage: "sidebar.right").font(.callout.weight(.medium))
                            }
                            .buttonStyle(.glass)
                            .keyboardShortcut("i", modifiers: .command)
                        }
                    }

                    LiveStatusCard()
                        .padding(.bottom, 4)

                    ForEach(segments) { segment in
                        Group {
                            switch segment {
                            case .single(let item):
                                FeedRow(item: item, isLive: item.id == store.feed.last?.id)
                            case .tools(let items):
                                FlowLayout(spacing: 8) {
                                    ForEach(items) { FeedRow(item: $0) }
                                }
                            }
                        }
                        .id(segment.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .environment(\.ticketTracker, store.runningTracker)
                .animation(.smooth(duration: 0.3), value: store.feed)
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 96)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            .glassScrollIndicator()
            .onScrollGeometryChange(for: CGFloat.self, of: { geo in
                max(0, geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height)
            }, action: { _, distanceFromBottom in
                pinnedToBottom = distanceFromBottom < 60
            })
            .onChange(of: store.feed) {
                guard pinnedToBottom else { return }
                withAnimation(.smooth) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

/// Glass card showing what's happening now, how long it's taken, and progress.
private struct LiveStatusCard: View {
    @Environment(PlanStore.self) private var store

    var body: some View {
        let tools = store.feed.filter { $0.kind == .tool }
        let tickets = Set(tools.compactMap { PlanStore.extractKey($0.detail) }).count
        let thoughts = store.feed.filter { $0.kind == .thinking }.count

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).contentTransition(.numericText())
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let start = store.startedAt {
                    TimelineView(.periodic(from: start, by: 1)) { ctx in
                        Text(Duration.seconds(ctx.date.timeIntervalSince(start).rounded()),
                             format: .time(pattern: .minuteSecond))
                            .font(.title3.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ProgressBar(fraction: fraction)

            HStack(spacing: 16) {
                Label("\(tickets) ticket\(tickets == 1 ? "" : "s") read", systemImage: "ticket")
                Label("\(tools.count) lookup\(tools.count == 1 ? "" : "s")", systemImage: "arrow.down.doc")
                Label("\(thoughts) thought\(thoughts == 1 ? "" : "s")", systemImage: "brain")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
        }
        .padding(16)
        .glassEffect(.regular.tint(.accentColor.opacity(0.06)), in: .rect(cornerRadius: 20))
        .animation(.smooth, value: store.phase)
    }

    private var icon: String {
        switch store.phase {
        case .connecting: "antenna.radiowaves.left.and.right"
        case .thinking: "brain"
        case .reading: "doc.text.magnifyingglass"
        case .writing: "pencil.and.list.clipboard"
        }
    }

    private var title: String {
        switch store.phase {
        case .connecting: "Connecting…"
        case .thinking(let turn): turn <= 1 ? "Planning the research" : "Thinking"
        case .reading(let done, let total): "Reading \(done) of \(total)"
        case .writing: "Writing your test plan"
        }
    }

    private var subtitle: String {
        switch store.phase {
        case .connecting: "Opening a session with your tracker"
        case .thinking(let turn): turn > 1 ? "Working out what to look at next · step \(turn)" : "Deciding which tickets and docs matter"
        case .reading: "Fetching tickets and docs in parallel"
        case .writing(let n): "\(n.formatted(.number.notation(.compactName))) characters written — big epics take a minute"
        }
    }

    /// Determinate while reading or writing, indeterminate otherwise.
    private var fraction: Double? {
        switch store.phase {
        case .reading(let done, let total): total == 0 ? nil : Double(done) / Double(total)
        // Plans are typically 5–20k characters; ease towards the end without claiming done.
        case .writing(let n): min(0.95, 1 - exp(-Double(n) / 9000))
        default: nil
        }
    }
}

/// Glass progress bar: fills for a known fraction, sweeps when indeterminate.
struct ProgressBar: View {
    let fraction: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary.opacity(0.6))
                if let fraction {
                    Capsule()
                        .fill(LinearGradient(colors: [.indigo, .teal], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * fraction))
                        .animation(.smooth, value: fraction)
                } else {
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        let w = geo.size.width * 0.3
                        Capsule()
                            .fill(LinearGradient(colors: [.indigo.opacity(0), .indigo, .teal, .teal.opacity(0)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: w)
                            .offset(x: -w + (geo.size.width + w) * t)
                    }
                }
            }
            .clipShape(.capsule)
        }
        .frame(height: 6)
    }
}

struct FeedRow: View {
    let item: FeedItem
    /// The newest row while research runs — thinking rows pulse while streaming.
    var isLive = false
    @State private var expanded = false
    @Environment(TicketInspector.self) private var inspector
    @Environment(\.ticketTracker) private var tracker

    var body: some View {
        switch item.kind {
        case .status:
            Label(item.title, systemImage: "circle.dotted")
                .foregroundStyle(.secondary)
                .font(.callout)
        case .tool:
            let key = PlanStore.extractKey(item.detail).flatMap { $0 == item.detail.uppercased() ? $0 : nil }
            Button { if let key { inspector.open(key, tracker: tracker) } } label: { toolChip(key: key) }
                .buttonStyle(.plain)
                .disabled(key == nil)
                .help(key.map { "Show \($0) details" } ?? "")
        case .thinking:
            let multiline = item.detail.contains("\n") || item.detail.count > 160
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.smooth) { expanded.toggle() }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "brain")
                            .symbolEffect(.pulse, options: .repeating, isActive: isLive)
                        // Collapsed rows show the thought itself, filling the row's width.
                        Text(expanded ? "Thinking" : preview)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if multiline {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!multiline)
                .help(expanded ? "Collapse" : "Expand")

                if expanded {
                    Text(item.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.opacity(0.4), in: .rect(cornerRadius: 12))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    /// First line of the thought, falling back to its title.
    private var preview: String {
        let line = item.detail.split(separator: "\n").first.map(String.init) ?? ""
        return line.trimmingCharacters(in: .whitespaces).isEmpty ? item.title : line
    }

    private func toolChip(key: String?) -> some View {
        HStack(spacing: 10) {
            Group {
                switch item.state {
                case .pending: ProgressView().controlSize(.mini)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case nil: Image(systemName: "arrow.down.doc").foregroundStyle(.tint)
                }
            }
            .frame(width: 16)
            .transition(.scale.combined(with: .opacity))
            Text(item.title)
            if !item.detail.isEmpty {
                Text(item.detail)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if key != nil {
                Image(systemName: "sidebar.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(key != nil ? .regular.interactive() : .regular, in: .capsule)
        .opacity(item.state == .pending ? 0.75 : 1)
        .animation(.smooth, value: item.state)
    }
}

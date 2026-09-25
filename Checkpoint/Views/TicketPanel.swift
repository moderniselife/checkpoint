import SwiftUI

/// Floating Liquid Glass panel on the right showing everything about one ticket.
struct TicketPanel: View {
    @Environment(TicketInspector.self) private var inspector
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 10) {
            TicketTabStrip()
            pane
        }
        .background {
            // ⌃Tab / ⌃⇧Tab cycle through open tickets.
            Group {
                Button("") { inspector.cycle(1) }.keyboardShortcut(.tab, modifiers: .control)
                Button("") { inspector.cycle(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
            }
            .hidden()
        }
    }

    private var pane: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.4)
            Group {
                if let key = inspector.currentKey {
                    switch inspector.currentState {
                    case .loaded(let detail): TicketDetailView(detail: detail)
                    case .failed(let msg):
                        ContentUnavailableView {
                            Label("Couldn't load \(key)", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(msg).textSelection(.enabled)
                        } actions: {
                            Button("Retry") { inspector.refresh() }.buttonStyle(.glass)
                        }
                    default:
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading \(key)…").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    /// Loaded issue URL (always right for Linear), else the Jira browse URL.
    private var currentURL: URL? {
        if case .loaded(let d) = inspector.currentState, let url = d.webURL { return url }
        guard let ref = inspector.current, ref.tracker == .jira else { return nil }
        return settings.browseURL(for: ref.key)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            if inspector.canGoBack {
                Button { withAnimation(.smooth) { inspector.back() } } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Back to the previous ticket")
            }
            Text(inspector.currentKey ?? "")
                .font(.headline.monospaced())
            Spacer()
            Button { inspector.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Refresh")
            if let url = currentURL {
                Button {
                    Platform.copy(url.absoluteString)
                } label: { Image(systemName: "link") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Copy link")
                Button { Platform.open(url) } label: { Image(systemName: "arrow.up.right") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Open in \(inspector.current?.tracker.label ?? "tracker")")
            }
            Button { withAnimation(.smooth) { inspector.close() } } label: { Image(systemName: "xmark") }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .keyboardShortcut(.cancelAction)
                .help("Close (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct TicketDetailView: View {
    let detail: TicketDetail
    @Environment(TicketInspector.self) private var inspector
    @State private var tab: Tab = .comments

    enum Tab: String, CaseIterable { case comments = "Comments", worklog = "Work log", history = "History" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Title block
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Chip(text: detail.type)
                        Chip(text: detail.status, tint: statusTint)
                        if let p = detail.priority { Chip(text: p, tint: priorityTint(p)) }
                        if let r = detail.resolution { Chip(text: r, tint: .green) }
                    }
                    Text(detail.summary)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PanelCard { fieldsGrid }

                if !detail.timeTracking.isEmpty {
                    PanelCard(title: "Time tracking", icon: "clock") { TimeTrackingView(tracking: detail.timeTracking) }
                }

                PanelCard(title: "Description", icon: "text.alignleft") {
                    if detail.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("No description").foregroundStyle(.tertiary)
                    } else {
                        MarkdownView(markdown: detail.description)
                    }
                }

                if !detail.attachments.isEmpty {
                    PanelCard(title: "Attachments (\(detail.attachments.count))", icon: "paperclip") {
                        AttachmentsGrid(attachments: detail.attachments, tracker: detail.tracker)
                    }
                }

                if !detail.externalLinks.isEmpty {
                    PanelCard(title: "Links (\(detail.externalLinks.count))", icon: "arrow.up.forward.square") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(detail.externalLinks) { ExternalLinkRow(link: $0) }
                        }
                    }
                }

                if !detail.children.isEmpty {
                    PanelCard(title: "Child issues (\(detail.children.count))", icon: "list.bullet.indent") {
                        ChildIssuesView(children: detail.children, parentKey: detail.key, tracker: detail.tracker)
                    }
                }

                if !detail.subtasks.isEmpty || !detail.links.isEmpty || detail.parent != nil {
                    PanelCard(title: "Related", icon: "link") {
                        VStack(alignment: .leading, spacing: 6) {
                            if let parent = detail.parent { LinkedRow(issue: parent) }
                            ForEach(detail.subtasks) { LinkedRow(issue: $0) }
                            ForEach(detail.links) { LinkedRow(issue: $0) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    // Linear has no work log, and its MCP doesn't expose history.
                    let tabs = Tab.allCases.filter { t in
                        switch t {
                        case .comments: true
                        case .worklog: detail.tracker == .jira
                        case .history: detail.tracker == .jira || !detail.history.isEmpty
                        }
                    }
                    if tabs.count > 1 {
                        Picker("", selection: $tab) {
                            ForEach(tabs, id: \.self) { t in
                                switch t {
                                case .comments: Text("Comments (\(detail.commentTotal))").tag(t)
                                case .worklog: Text("Work log (\(detail.worklogTotal))").tag(t)
                                case .history: Text("History (\(detail.history.count))").tag(t)
                                }
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    } else {
                        Label("Comments (\(detail.commentTotal))", systemImage: "bubble.left.and.bubble.right")
                            .font(.subheadline.weight(.semibold))
                    }

                    switch tabs.contains(tab) ? tab : .comments {
                    case .comments: CommentsList(comments: detail.comments, total: detail.commentTotal)
                    case .worklog: WorklogList(worklogs: detail.worklogs, total: detail.worklogTotal)
                    case .history: HistoryList(entries: detail.history)
                    }
                }

                if !detail.otherFields.isEmpty {
                    PanelCard {
                        DisclosureGroup {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                                ForEach(detail.otherFields) { f in
                                    GridRow {
                                        Text(f.name).font(.caption).foregroundStyle(.secondary)
                                            .gridColumnAlignment(.trailing)
                                        Text(f.value).font(.caption).textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Label("All other fields (\(detail.otherFields.count))", systemImage: "list.bullet.rectangle")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .padding(18)
        }
        .glassScrollIndicator()
        .environment(\.ticketAttachments, Dictionary(detail.attachments.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }))
        .environment(\.ticketTracker, inspector.current?.tracker ?? .jira)
        .environment(\.openURL, OpenURLAction { url in
            // Jira browse links and Linear issue links inside bodies open in the panel.
            if url.path.hasPrefix("/browse/"), let key = PlanStore.extractKey(url.lastPathComponent) {
                inspector.open(key, tracker: .jira, push: true)
                return .handled
            }
            if url.host()?.hasSuffix("linear.app") == true, url.path.contains("/issue/"),
               let key = PlanStore.extractKey(url.path) {
                inspector.open(key, tracker: .linear, push: true)
                return .handled
            }
            return .systemAction
        })
    }

    private var fieldsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            FieldRow("Assignee") { PersonView(person: detail.assignee) }
            FieldRow("Reporter") { PersonView(person: detail.reporter) }
            if !detail.fixVersions.isEmpty { FieldRow("Fix version") { Text(detail.fixVersions.joined(separator: ", ")) } }
            if !detail.components.isEmpty { FieldRow("Components") { Text(detail.components.joined(separator: ", ")) } }
            if !detail.labels.isEmpty {
                FieldRow("Labels") {
                    Text(detail.labels.joined(separator: " · ")).font(.caption.monospaced())
                }
            }
            if let due = detail.dueDate { FieldRow("Due") { Text(due) } }
            FieldRow("Created") { DateText(date: detail.created) }
            FieldRow("Updated") { DateText(date: detail.updated) }
        }
        .font(.callout)
    }

    private var statusTint: Color {
        switch detail.statusCategory {
        case "done": .green
        case "indeterminate": .blue
        default: .gray
        }
    }
}

// MARK: - Sections

private struct PanelCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label(title, systemImage: icon ?? "circle").font(.subheadline.weight(.semibold))
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.5), in: .rect(cornerRadius: 16))
    }
}

private struct FieldRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value
    init(_ label: String, @ViewBuilder value: () -> Value) { self.label = label; self.value = value() }

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value.textSelection(.enabled)
        }
    }
}

private struct PersonView: View {
    let person: TicketDetail.Person?

    var body: some View {
        if let person {
            HStack(spacing: 6) {
                AsyncImage(url: person.avatar) { $0.resizable() } placeholder: { Circle().fill(.quaternary) }
                    .frame(width: 18, height: 18)
                    .clipShape(.circle)
                Text(person.name)
            }
        } else {
            Text("Unassigned").foregroundStyle(.tertiary)
        }
    }
}

private struct DateText: View {
    let date: Date?

    var body: some View {
        if let date {
            Text(date, format: .relative(presentation: .named))
                .help(date.formatted(date: .complete, time: .shortened))
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}

private struct TimeTrackingView: View {
    let tracking: TicketDetail.TimeTracking

    var body: some View {
        let total = max(tracking.spentSeconds + tracking.remainingSeconds, tracking.originalSeconds, 1)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(tracking.spentSeconds > tracking.originalSeconds && tracking.originalSeconds > 0 ? Color.orange : .blue)
                        .frame(width: geo.size.width * CGFloat(tracking.spentSeconds) / CGFloat(total))
                    Rectangle().fill(.quaternary)
                }
                .clipShape(.capsule)
            }
            .frame(height: 8)
            HStack {
                stat("Logged", tracking.spent)
                Spacer()
                stat("Remaining", tracking.remaining)
                Spacer()
                stat("Estimate", tracking.original)
            }
        }
    }

    private func stat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "—").font(.callout.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct LinkedRow: View {
    let issue: TicketDetail.LinkedIssue
    @Environment(TicketInspector.self) private var inspector

    var body: some View {
        Button { withAnimation(.smooth) { inspector.open(issue.key, tracker: inspector.current?.tracker ?? .jira, push: true) } } label: {
            HStack(spacing: 8) {
                Text(issue.relation).font(.caption).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
                Text(issue.key).font(.callout.monospaced().weight(.medium))
                Text(issue.summary).font(.callout).lineLimit(1).foregroundStyle(.primary)
                Spacer(minLength: 4)
                if !issue.status.isEmpty { Text(issue.status).font(.caption).foregroundStyle(.secondary) }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct CommentsList: View {
    let comments: [TicketDetail.Comment]
    let total: Int
    @State private var newestFirst = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if comments.isEmpty {
                Text("No comments").foregroundStyle(.tertiary)
            } else {
                Toggle("Newest first", isOn: $newestFirst).toggleStyle(.switch).controlSize(.mini).font(.caption)
            }
            ForEach(newestFirst ? comments.reversed() : comments) { c in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        PersonView(person: c.author).font(.callout.weight(.medium))
                        Spacer()
                        DateText(date: c.created).font(.caption).foregroundStyle(.secondary)
                    }
                    MarkdownView(markdown: c.body)
                }
                .padding(12)
                .background(.background.opacity(0.5), in: .rect(cornerRadius: 14))
            }
            if total > comments.count {
                Text("Showing \(comments.count) of \(total) comments — open in Jira for the rest.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct WorklogList: View {
    let worklogs: [TicketDetail.Worklog]
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if worklogs.isEmpty { Text("No work logged").foregroundStyle(.tertiary) }
            ForEach(worklogs) { w in
                HStack(alignment: .top, spacing: 10) {
                    Text(w.timeSpent)
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .frame(width: 60, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            PersonView(person: w.author).font(.callout)
                            Spacer()
                            DateText(date: w.started).font(.caption).foregroundStyle(.secondary)
                        }
                        if !w.comment.isEmpty {
                            Text(w.comment).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                .padding(10)
                .background(.background.opacity(0.5), in: .rect(cornerRadius: 12))
            }
            if total > worklogs.count {
                Text("Showing \(worklogs.count) of \(total) entries.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct HistoryList: View {
    let entries: [TicketDetail.HistoryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if entries.isEmpty { Text("No history returned").foregroundStyle(.tertiary) }
            ForEach(entries) { e in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(e.author).font(.caption.weight(.medium))
                        Spacer()
                        DateText(date: e.created).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(e.changes.enumerated()), id: \.offset) { _, c in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(c.field.capitalized).font(.caption.weight(.semibold))
                            Text(c.from.isEmpty ? "∅" : c.from).font(.caption).foregroundStyle(.secondary).strikethrough()
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                            Text(c.to.isEmpty ? "∅" : c.to).font(.caption)
                        }
                        .lineLimit(2)
                    }
                }
                Divider().opacity(0.4)
            }
        }
    }
}

// MARK: - Attachments

private struct AttachmentsGrid: View {
    let attachments: [TicketDetail.Attachment]
    var tracker: Tracker = .jira
    @Environment(AppSettings.self) private var settings
    @State private var preview: TicketDetail.Attachment?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                ForEach(attachments) { a in
                    AttachmentTile(attachment: a) {
                        if a.isImage { preview = a } else if let url = settings.browserURL(for: a) { Platform.open(url) }
                    }
                }
            }
            if tracker == .jira && settings.attachmentCredentials.basicHeader == nil {
                Text("Image previews use your Atlassian API token if one is saved in Settings; otherwise click to open in your browser.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .sheet(item: $preview) { a in AttachmentPreview(attachment: a) }
    }
}

private struct AttachmentTile: View {
    let attachment: TicketDetail.Attachment
    let action: () -> Void
    @Environment(AppSettings.self) private var settings
    @State private var image: PlatformImage?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5))
                    if let image {
                        Image(platformImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: icon).font(.title).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 78)
                .clipShape(.rect(cornerRadius: 10))
                Text(attachment.filename).font(.caption2).lineLimit(1).truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .help("\(attachment.filename) — \(attachment.author)")
        .task(id: attachment.id) {
            guard attachment.isImage else { return }
            if let data = await AttachmentLoader.shared.data(for: attachment, full: false, creds: settings.attachmentCredentials) {
                image = PlatformImage(data: data)
            }
        }
    }

    private var icon: String {
        let m = attachment.mimeType
        if m.hasPrefix("image/") { return "photo" }
        if m.hasPrefix("video/") { return "film" }
        if m.contains("pdf") { return "doc.richtext" }
        if m.contains("zip") || m.contains("compressed") { return "doc.zipper" }
        if m.contains("json") || m.contains("text") { return "doc.plaintext" }
        return "doc"
    }
}

private struct AttachmentPreview: View {
    let attachment: TicketDetail.Attachment
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var image: PlatformImage?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(attachment.filename).font(.headline).lineLimit(1)
                Spacer()
                if let url = settings.browserURL(for: attachment) {
                    Link("Open in browser", destination: url)
                }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            Group {
                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(platformImage: image).resizable().scaledToFit()
                            .frame(maxWidth: max(image.size.width, 400))
                    }
                } else if failed {
                    ContentUnavailableView("Preview unavailable", systemImage: "photo",
                                           description: Text("Save an Atlassian API token in Settings, or open it in your browser."))
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 480)
        .task {
            if let data = await AttachmentLoader.shared.data(for: attachment, full: true, creds: settings.attachmentCredentials) {
                image = PlatformImage(data: data)
            } else {
                failed = true
            }
        }
    }
}

func priorityTint(_ p: String) -> Color {
    switch p.lowercased() {
    case "highest", "blocker", "critical": .red
    case "high": .orange
    case "medium": .yellow
    default: .gray
    }
}

private struct ExternalLinkRow: View {
    let link: TicketDetail.ExternalLink

    var body: some View {
        Button { Platform.open(link.url) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(.tint).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(link.title).font(.callout).lineLimit(1).foregroundStyle(.primary)
                    if !link.subtitle.isEmpty {
                        Text(link.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(link.url.absoluteString)
    }

    private var icon: String {
        let host = link.url.host() ?? ""
        if host.contains("github") || host.contains("gitlab") || host.contains("bitbucket") { return "arrow.triangle.pull" }
        if host.contains("figma") { return "paintpalette" }
        if host.contains("sentry") { return "ant" }
        if host.contains("slack") { return "bubble.left" }
        return "link"
    }
}

// MARK: - Tabs

/// Open tickets as floating glass tabs; click to switch, × to close.
private struct TicketTabStrip: View {
    @Environment(TicketInspector.self) private var inspector
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(inspector.tabs, id: \.self) { ref in
                            TicketTab(ref: ref, isActive: ref == inspector.active)
                                .glassEffectID(ref.cacheKey, in: glass)
                                .id(ref)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                .onChange(of: inspector.active) { _, new in
                    withAnimation(.smooth) { proxy.scrollTo(new, anchor: .center) }
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: inspector.tabs)
        .animation(.smooth(duration: 0.3), value: inspector.active)
    }
}

private struct TicketTab: View {
    let ref: TicketInspector.Ref
    let isActive: Bool
    @Environment(TicketInspector.self) private var inspector
    @Environment(AppSettings.self) private var settings
    @State private var hovering = false

    private var detail: TicketDetail? {
        if case .loaded(let d) = inspector.state(for: ref) { return d }
        return nil
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(ref.key)
                .font(.caption.monospaced().weight(isActive ? .semibold : .medium))
            if isActive, let title = detail?.summary, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            if isActive || hovering {
                Button { withAnimation(.smooth) { inspector.closeTab(ref) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 14, height: 14)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close tab")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, isActive || hovering ? 6 : 10)
        .padding(.vertical, 7)
        .contentShape(.capsule)
        .glassEffect(
            isActive ? .regular.tint(.accentColor.opacity(0.22)).interactive() : .regular.interactive(),
            in: .capsule
        )
        .onTapGesture { withAnimation(.smooth) { inspector.activate(ref) } }
        .onHover { hovering = $0 }
        .help(detail.map { "\(ref.key) — \($0.summary)" } ?? ref.key)
        .contextMenu {
            Button("Close Tab") { inspector.closeTab(ref) }
            Button("Close Other Tabs") { inspector.closeOtherTabs(ref) }
            if let url = detail?.webURL ?? (ref.tracker == .jira ? settings.browseURL(for: ref.key) : nil) {
                Divider()
                Button("Open in \(ref.tracker.label)") { Platform.open(url) }
            }
        }
    }

    private var statusColor: Color {
        switch detail?.statusCategory {
        case "done": .green
        case "indeterminate": .blue
        case .some: .gray
        case nil: .secondary.opacity(0.4)
        }
    }
}

/// Epic children with a done / in-progress / to-do breakdown and a filter.
private struct ChildIssuesView: View {
    let children: [TicketDetail.LinkedIssue]
    var parentKey: String = ""
    var tracker: Tracker = .jira
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var filter = "all"
    @State private var showingBatch = false

    private var counts: (done: Int, active: Int, todo: Int) {
        (children.filter { $0.category == "done" }.count,
         children.filter { $0.category == "indeterminate" }.count,
         children.filter { $0.category != "done" && $0.category != "indeterminate" }.count)
    }

    private var shown: [TicketDetail.LinkedIssue] {
        switch filter {
        case "done": children.filter { $0.category == "done" }
        case "active": children.filter { $0.category == "indeterminate" }
        case "todo": children.filter { $0.category != "done" && $0.category != "indeterminate" }
        default: children
        }
    }

    var body: some View {
        let c = counts
        let total = max(children.count, 1)
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(.green).frame(width: geo.size.width * CGFloat(c.done) / CGFloat(total))
                    Rectangle().fill(.blue).frame(width: geo.size.width * CGFloat(c.active) / CGFloat(total))
                    Rectangle().fill(.quaternary)
                }
                .clipShape(.capsule)
            }
            .frame(height: 6)
            Picker("", selection: $filter) {
                Text("All \(children.count)").tag("all")
                Text("Done \(c.done)").tag("done")
                Text("In progress \(c.active)").tag("active")
                Text("To do \(c.todo)").tag("todo")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shown) { LinkedRow(issue: $0) }
            }
            Button("Plan each child", systemImage: "tray.and.arrow.down") { showingBatch = true }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(store.batchRunning)
        }
        .sheet(isPresented: $showingBatch) {
            BatchSheet(initialKeys: children.map(\.key), initialTracker: tracker,
                       initialFolderName: "\(parentKey) children")
                .environment(store)
                .environment(settings)
        }
    }
}

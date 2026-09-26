import SwiftUI

/// The built-in Unfinished folder (runs that paused, failed or were cut off) and the Bin
/// (discarded runs, deleted for good after 30 days).
struct DraftsView: View {
    let bin: Bool
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var confirmingEmpty = false

    private var drafts: [ResearchDraft] { bin ? store.binnedDrafts : store.unfinishedDrafts }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if drafts.isEmpty {
                    ContentUnavailableView(
                        bin ? "Bin is empty" : "Nothing unfinished",
                        systemImage: bin ? "trash" : "checkmark.circle",
                        description: Text(bin
                            ? "Discarded runs wait here for \(ResearchDraft.binDays) days."
                            : "Pause a run, or let one fail, and it waits here to pick up where it stopped.")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(drafts) { draft in
                        DraftCard(draft: draft, bin: bin)
                    }
                }
            }
            .padding(Platform.isMac ? 24 : 16)
            .padding(.top, Platform.isMac ? 64 : 0)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Empty the bin?", isPresented: $confirmingEmpty) {
            Button("Delete \(drafts.count) Run\(drafts.count == 1 ? "" : "s")", role: .destructive) { store.emptyBin() }
        } message: {
            Text("They're deleted for good.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                if Platform.isMac {
                    Text(bin ? "Bin" : "Unfinished").font(.largeTitle.weight(.bold))
                }
                Text(bin
                    ? "Discarded runs. Each is deleted for good \(ResearchDraft.binDays) days after it was binned."
                    : "Runs that stopped part-way. Resume one and it carries on from its last finished step.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if bin && !drafts.isEmpty {
                Button("Empty Bin", role: .destructive) { confirmingEmpty = true }
                    .buttonStyle(.glass)
            }
        }
    }
}

private struct DraftCard: View {
    let draft: ResearchDraft
    let bin: Bool
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var showingFeed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusTint)
                Text(draft.key)
                    .font(.headline.monospaced())
                    .lineLimit(1)
                ModeBadge(mode: draft.mode, compact: true)
                Text(draft.trackerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(draft.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(statusLine).font(.callout.weight(.medium))
                if let message = draft.errorMessage, !message.isEmpty {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(draft.status == .failed ? .red : .secondary)
                        .lineLimit(4)
                }
                Text(draft.progressSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let days = draft.daysLeftInBin {
                    Text(days == 0 ? "Deleted today" : "Deleted in \(days) day\(days == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if !draft.feed.isEmpty {
                DisclosureGroup("What it did so far", isExpanded: $showingFeed) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(draft.feed.suffix(40)) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: icon(for: item))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)
                                Text(item.title)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.callout)
            }

            HStack(spacing: 10) {
                if bin {
                    Button("Restore", systemImage: "arrow.uturn.backward") { store.restoreFromBin(draft.id) }
                        .buttonStyle(.glass)
                    Spacer()
                    Button("Delete Now", systemImage: "trash", role: .destructive) { store.deleteDraft(draft.id) }
                        .buttonStyle(.glass)
                } else {
                    Button("Resume", systemImage: "play.fill") { store.resume(draft.id, settings: settings) }
                        .buttonStyle(.glassProminent)
                        .disabled(store.isRunning)
                        .help(store.isRunning ? "Another run is going. Pause it first." : "Carry on from the last finished step")
                    Spacer()
                    Button("Move to Bin", systemImage: "trash") { store.moveToBin(draft.id) }
                        .buttonStyle(.glass)
                }
            }
            .controlSize(Platform.isMac ? .regular : .large)
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 20))
        .contextMenu {
            if bin {
                Button("Restore", systemImage: "arrow.uturn.backward") { store.restoreFromBin(draft.id) }
                Button("Delete Now", systemImage: "trash", role: .destructive) { store.deleteDraft(draft.id) }
            } else {
                Button("Resume", systemImage: "play.fill") { store.resume(draft.id, settings: settings) }
                    .disabled(store.isRunning)
                Button("Move to Bin", systemImage: "trash") { store.moveToBin(draft.id) }
            }
        }
    }

    private var statusLine: String {
        if bin { return "Discarded" }
        switch draft.status {
        case .failed: return "Failed"
        case .paused: return draft.errorMessage == nil ? "Paused" : "Stopped"
        case .running: return "Running"
        }
    }

    private var statusIcon: String {
        if bin { return "trash.circle.fill" }
        switch draft.status {
        case .failed: return "exclamationmark.circle.fill"
        case .paused: return "pause.circle.fill"
        case .running: return "play.circle.fill"
        }
    }

    private var statusTint: Color {
        if bin { return .gray }
        switch draft.status {
        case .failed: return .red
        case .paused: return .orange
        case .running: return .green
        }
    }

    private func icon(for item: FeedItem) -> String {
        switch item.kind {
        case .status: "info.circle"
        case .thinking: "brain"
        case .tool: item.state == .failed ? "exclamationmark.triangle" : "doc.text"
        }
    }
}

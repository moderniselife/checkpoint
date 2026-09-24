import SwiftUI

struct ProgressFeedView: View {
    @Environment(PlanStore.self) private var store

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("Researching \(store.runningKey ?? "")")
                            .font(.title3.weight(.semibold))
                        ModeBadge(mode: store.runningMode)
                    }
                    .padding(.bottom, 6)

                    ForEach(store.feed) { item in
                        FeedRow(item: item)
                            .id(item.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 96)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: store.feed.count) {
                withAnimation(.smooth) { proxy.scrollTo(store.feed.last?.id, anchor: .bottom) }
            }
        }
    }
}

private struct FeedRow: View {
    let item: FeedItem
    @State private var expanded = false
    @Environment(TicketInspector.self) private var inspector

    var body: some View {
        switch item.kind {
        case .status:
            Label(item.title, systemImage: "circle.dotted")
                .foregroundStyle(.secondary)
                .font(.callout)
        case .tool:
            let key = PlanStore.extractKey(item.detail).flatMap { $0 == item.detail.uppercased() ? $0 : nil }
            Button { if let key { inspector.open(key) } } label: { toolChip(key: key) }
                .buttonStyle(.plain)
                .disabled(key == nil)
                .help(key.map { "Show \($0) details" } ?? "")
        case .thinking:
            let multiline = item.detail.contains("\n") || item.detail.count > 90
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.smooth) { expanded.toggle() }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "brain")
                        Text(expanded ? "Thinking" : item.title)
                            .lineLimit(1)
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

    private func toolChip(key: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .foregroundStyle(.tint)
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
    }
}

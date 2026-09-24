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

    var body: some View {
        switch item.kind {
        case .status:
            Label(item.title, systemImage: "circle.dotted")
                .foregroundStyle(.secondary)
                .font(.callout)
        case .tool:
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        case .thinking:
            VStack(alignment: .leading, spacing: 6) {
                Label(item.title, systemImage: "brain")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 1)
                if expanded {
                    Text(item.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .contentShape(.rect)
            .onTapGesture { withAnimation(.smooth) { expanded.toggle() } }
        }
    }
}

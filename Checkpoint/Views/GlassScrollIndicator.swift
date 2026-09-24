import SwiftUI

extension View {
    /// Replaces the system scroller with a thin Liquid Glass pill that fades in
    /// while scrolling, widens on hover, and can be dragged.
    func glassScrollIndicator() -> some View { modifier(GlassScrollIndicator()) }
}

private struct ScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
    var container: CGFloat = 0
    var scrollable: CGFloat { max(0, content - container) }
}

private struct GlassScrollIndicator: ViewModifier {
    @State private var metrics = ScrollMetrics()
    @State private var position = ScrollPosition(edge: .top)
    @State private var visible = false
    @State private var hovering = false
    @State private var dragStartOffset: CGFloat?
    @State private var hideTask: Task<Void, Never>?

    private let inset: CGFloat = 6

    func body(content: Content) -> some View {
        content
            // `.hidden` is only a hint on macOS — with "Show scroll bars: Always" (or a mouse
            // attached) the system scroller still draws. `.never` removes it outright.
            .scrollIndicators(.never)
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollMetrics.self) { g in
                ScrollMetrics(
                    offset: g.contentOffset.y + g.contentInsets.top,
                    content: g.contentSize.height,
                    container: g.containerSize.height
                )
            } action: { old, new in
                metrics = new
                if old.offset != new.offset { flash() }
            }
            .overlay(alignment: .topTrailing) { thumb }
    }

    @ViewBuilder
    private var thumb: some View {
        if metrics.scrollable > 1 {
            let track = metrics.container - inset * 2
            let height = max(36, track * metrics.container / max(metrics.content, 1))
            let progress = min(1, max(0, metrics.offset / metrics.scrollable))
            let y = inset + (track - height) * progress
            let active = hovering || dragStartOffset != nil

            Capsule()
                .fill(.clear)
                .frame(width: active ? 8 : 5, height: height)
                .glassEffect(.regular.tint(.primary.opacity(active ? 0.25 : 0.12)).interactive(), in: .capsule)
                .padding(.horizontal, 4)            // bigger hit target than the visible pill
                .contentShape(.rect)
                .offset(y: y)
                .padding(.trailing, 2)
                .opacity(visible || active ? 1 : 0)
                .animation(.smooth(duration: 0.2), value: active)
                .animation(.easeOut(duration: 0.35), value: visible)
                .onHover { inside in
                    hovering = inside
                    if inside { flash(hold: true) } else { flash() }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let start = dragStartOffset ?? metrics.offset
                            dragStartOffset = start
                            let perPoint = metrics.scrollable / max(track - height, 1)
                            let target = min(metrics.scrollable, max(0, start + value.translation.height * perPoint))
                            position.scrollTo(y: target)
                        }
                        .onEnded { _ in dragStartOffset = nil; flash() }
                )
        }
    }

    /// Show the pill, then fade it out after a pause unless it's being hovered.
    private func flash(hold: Bool = false) {
        visible = true
        hideTask?.cancel()
        guard !hold else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, !hovering, dragStartOffset == nil else { return }
            visible = false
        }
    }
}

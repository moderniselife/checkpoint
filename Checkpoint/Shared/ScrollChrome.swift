import SwiftUI
import Observation

/// Safari-style: the floating ticket bar slides away while you scroll down a page
/// and comes back as soon as you scroll up (or return to the top).
@Observable
@MainActor
final class ScrollChrome {
    private(set) var barHidden = false
    @ObservationIgnored private var travel: CGFloat = 0

    func scrolled(from old: CGFloat, to new: CGFloat) {
        if new < 60 { show(); return }
        let delta = new - old
        // Accumulate small moves so trackpad jitter doesn't flicker the bar.
        travel = (delta > 0) == (travel > 0) ? travel + delta : delta
        if travel > 24 { hide() } else if travel < -12 { show() }
    }

    func show() {
        travel = 0
        guard barHidden else { return }
        withAnimation(.smooth(duration: 0.3)) { barHidden = false }
    }

    private func hide() {
        guard !barHidden else { return }
        withAnimation(.smooth(duration: 0.3)) { barHidden = true }
    }
}

extension EnvironmentValues {
    @Entry var scrollChrome: ScrollChrome? = nil
}

extension View {
    /// Reports this scroll view's movement so the ticket bar can hide and reappear.
    func drivesScrollChrome() -> some View {
        modifier(ScrollChromeReporter())
    }
}

private struct ScrollChromeReporter: ViewModifier {
    @Environment(\.scrollChrome) private var chrome

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { old, new in
                chrome?.scrolled(from: old, to: new)
            }
            .onDisappear { chrome?.show() }
    }
}

import SwiftUI

/// How much room the main area has, so content and the ticket bar can grow on big Mac windows
/// instead of sitting in a narrow column. iOS keeps the defaults.
struct LayoutMetrics: Equatable {
    /// Widest the reading column should get.
    var readableWidth: CGFloat = 820
    /// 1 on normal windows, up to 1.3 on very wide ones: text and controls in the ticket bar.
    var scale: CGFloat = 1

    /// From the width of the area beside the sidebar.
    init(mainWidth: CGFloat) {
        readableWidth = min(max(mainWidth * 0.74, 820), 1400)
        scale = min(max(1 + (mainWidth - 1100) / 800 * 0.3, 1), 1.3)
    }

    init() {}
}

extension EnvironmentValues {
    @Entry var layout = LayoutMetrics()
}

extension Font {
    /// A system font that grows with the layout scale (base sizes are the Mac's defaults).
    static func scaled(_ size: CGFloat, _ scale: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: (size * scale).rounded(), weight: weight)
    }
}

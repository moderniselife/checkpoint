import SwiftUI

extension Tracker {
    /// Brand tile in the asset catalog.
    var logoAsset: String { self == .jira ? "JiraLogo" : "LinearLogo" }
}

/// Jira or Linear brand tile, rounded like an app icon.
struct TrackerLogo: View {
    let tracker: Tracker
    var size: CGFloat = 22

    var body: some View {
        Image(tracker.logoAsset)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityLabel(tracker.label)
    }
}

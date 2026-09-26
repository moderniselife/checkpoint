import SwiftUI
import Observation

/// Places the tour points at. Views mark themselves with `.tourStop(_:)`.
enum TourStop: String, CaseIterable, Identifiable {
    case ticketBar, modeToggle, runOptions, sidebar
    case planHeader, criteria, taskFilter, taskRow, panes
    case finish

    var id: Self { self }

    /// Stops inside a plan; the guide opens one (the sample, if need be) before showing them.
    var needsPlan: Bool {
        switch self {
        case .planHeader, .criteria, .taskFilter, .taskRow, .panes: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .ticketBar: "Start with a ticket"
        case .modeToggle: "Dev or QA"
        case .runOptions: "Run options"
        case .sidebar: "Your plans"
        case .planHeader: "Progress at a glance"
        case .criteria: "Acceptance criteria"
        case .taskFilter: "Filter and focus"
        case .taskRow: "Work through each task"
        case .panes: "Research and chat"
        case .finish: "That's the tour"
        }
    }

    var text: String {
        switch self {
        case .ticketBar:
            Platform.isMac
                ? "Type a Jira or Linear key, or paste a link, then Analyze. ⌘L jumps here from anywhere."
                : "Type a Jira or Linear key, or paste a link, then tap ✨."
        case .modeToggle:
            "Dev plans can mention code, branches and local setup. QA plans stay in UI terms for the hosted app."
                + (Platform.isMac ? " ⌘⇧M flips it." : "")
        case .runOptions:
            "Quick or Deep, and a Bug, Feature or Epic template when the ticket type isn't enough."
                + (Platform.isMac ? "" : " Scenarios live here too.")
        case .sidebar:
            "Folders, smart folders that fill themselves, pins and search. "
                + (Platform.isMac ? "Right-click a plan" : "Touch and hold a plan") + " to tag, pin, move or archive it."
        case .planHeader:
            "The rings show tasks tested and criteria met. Below: the time estimate, a testing timer, tags"
                + (Platform.isMac ? " (⌘T)" : "") + " and reminders."
        case .criteria:
            (Platform.isMac ? "Click" : "Tap") + " a seal to mark a criterion met. ⚠︎ flags vague wording with questions to ask, and ⊕ drafts a task for anything uncovered."
        case .taskFilter:
            "Switch between To do, Failed and Blocked, or narrow to the five-minute smoke subset or just the P0s."
        case .taskRow:
            Platform.isMac
                ? "Click the circle to pass. The ⋯ menu marks fail or blocked, adds a note, attaches evidence or drafts a bug report. Drag screenshots straight onto a task to attach them."
                : "Tap the circle to pass. The ⋯ menu marks fail or blocked, adds a note, attaches a photo or file, or drafts a bug report."
        case .panes:
            "Research shows everything Checkpoint read and what it cost. Chat takes follow-up questions and can fold the answers back into the plan."
        case .finish:
            Platform.isMac
                ? "There's more in Export and the ⋯ menu. The Help menu has guides, shortcuts and this tour again."
                : "There's more under ⋯ in each plan. Settings has help, sync and this tour again."
        }
    }
}

/// Runs the spotlight tour. Views report their frames; the overlay dims everything else.
@Observable
@MainActor
final class TourGuide {
    private(set) var isActive = false
    private(set) var index = 0
    /// Window-space frames of whatever is on screen right now.
    var frames: [TourStop: CGRect] = [:]

    let stops: [TourStop] = [.ticketBar, .modeToggle, .runOptions, .sidebar,
                             .planHeader, .criteria, .taskFilter, .taskRow, .panes, .finish]

    @ObservationIgnored weak var store: PlanStore?

    var current: TourStop? { isActive ? stops[index] : nil }

    func start() {
        index = 0
        withAnimation(.smooth) { isActive = true }
    }

    func next() {
        guard index + 1 < stops.count else { end(); return }
        index += 1
        openPlanIfNeeded()
    }

    func back() {
        guard index > 0 else { return }
        index -= 1
        openPlanIfNeeded()
    }

    func end() {
        withAnimation(.smooth) { isActive = false }
    }

    /// Plan stops need a plan on screen: use the selected one, or open (and if need be add) the sample.
    private func openPlanIfNeeded() {
        guard let store, stops[index].needsPlan, store.selected == nil else { return }
        store.openSamplePlan()
    }
}

extension EnvironmentValues {
    @Entry var tourGuide: TourGuide? = nil
}

extension View {
    /// Marks this view as a tour stop so the spotlight can find it.
    func tourStop(_ stop: TourStop) -> some View {
        modifier(TourStopMarker(stop: stop))
    }

    /// Draws the tour over this view (put it on the window's root view).
    @ViewBuilder
    func tourOverlay(_ guide: TourGuide?) -> some View {
        if let guide {
            overlay { TourOverlay(guide: guide) }
                .environment(\.tourGuide, guide)
        } else {
            self
        }
    }
}

private struct TourStopMarker: ViewModifier {
    let stop: TourStop
    @Environment(\.tourGuide) private var guide

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { guide?.frames[stop] = $0 }
            .onDisappear { guide?.frames[stop] = nil }
    }
}

private struct TourOverlay: View {
    let guide: TourGuide

    var body: some View {
        if guide.isActive, let stop = guide.current {
            GeometryReader { geo in
                let origin = geo.frame(in: .global).origin
                let hole = guide.frames[stop].map { $0.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -8, dy: -8) }
                    .flatMap { geo.frame(in: .local).intersects($0) ? $0 : nil }
                ZStack(alignment: .topLeading) {
                    Spotlight(hole: hole)
                        .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))
                        .contentShape(Rectangle())
                        .onTapGesture {}
                    if let hole {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                            .frame(width: hole.width, height: hole.height)
                            .offset(x: hole.minX, y: hole.minY)
                            .allowsHitTesting(false)
                    }
                    TourCallout(guide: guide, stop: stop)
                        .frame(width: min(340, geo.size.width - 32))
                        .position(calloutCenter(hole: hole, in: geo.size))
                }
                .animation(.spring(duration: 0.45, bounce: 0.15), value: hole)
                .animation(.spring(duration: 0.45, bounce: 0.15), value: stop)
            }
            // One coordinate space for the dimming, the hole and the callout: the whole window.
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    /// Under the spotlight when there's room, otherwise above it; centred when there's no target.
    private func calloutCenter(hole: CGRect?, in size: CGSize) -> CGPoint {
        let width = min(340, size.width - 32), height: CGFloat = 200
        guard let hole else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let x = min(max(hole.midX, width / 2 + 16), size.width - width / 2 - 16)
        let margin: CGFloat = Platform.isMac ? 24 : 60
        if hole.maxY + height + margin < size.height {
            return CGPoint(x: x, y: hole.maxY + 16 + height / 2)
        }
        if hole.minY - height - margin > 0 {
            return CGPoint(x: x, y: hole.minY - 16 - height / 2)
        }
        return CGPoint(x: x, y: size.height - height / 2 - margin)
    }
}

/// A full-screen rectangle with a rounded hole, filled even-odd.
private struct Spotlight: Shape {
    var hole: CGRect?

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            let h = hole ?? .zero
            return AnimatablePair(AnimatablePair(h.minX, h.minY), AnimatablePair(h.width, h.height))
        }
        set {
            guard hole != nil else { return }
            hole = CGRect(x: newValue.first.first, y: newValue.first.second,
                          width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path(rect.insetBy(dx: -2000, dy: -2000))
        if let hole { p.addRoundedRect(in: hole, cornerSize: CGSize(width: 18, height: 18)) }
        return p
    }
}

private struct TourCallout: View {
    let guide: TourGuide
    let stop: TourStop

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(guide.index + 1) of \(guide.stops.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Skip Tour") { guide.end() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(stop.title).font(.title3.weight(.semibold))
            Text(stop.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if guide.index > 0 {
                    Button("Back") { withAnimation(.smooth) { guide.back() } }
                        .buttonStyle(.glass)
                }
                Spacer()
                Button(stop == .finish ? "Done" : "Next") { withAnimation(.smooth) { guide.next() } }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
    }
}

import Foundation

/// A plan run that hasn't finished yet: what was asked for, what the feed showed, and the
/// research conversation after its last finished step, so it can carry on from there.
///
/// Drafts live in the built-in **Unfinished** smart folder until they finish or are binned.
/// The bin keeps them for 30 days, then they're deleted for good. Drafts stay on this device
/// (they hold full tool results, which can be large) and don't sync.
nonisolated struct ResearchDraft: Codable, Identifiable, Hashable, Sendable {
    enum Status: String, Codable, Sendable { case running, paused, failed }

    var id = UUID()
    var key: String
    var mode: TestMode
    var tracker: Tracker
    var customTrackerID: UUID?
    var customTrackerName: String?
    var template: String?
    var modelOverride: String?
    var effortOverride: String?
    var folderID: UUID?
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var status: Status = .running
    /// Why it failed, or why it was paused when that wasn't the person's doing.
    var errorMessage: String?
    var feed: [FeedItem] = []
    var researchSeconds: TimeInterval = 0
    var snapshot: ResearchSnapshot?
    var binnedAt: Date?

    init(key: String, mode: TestMode, tracker: Tracker, customTrackerID: UUID? = nil, customTrackerName: String? = nil,
         template: String? = nil, modelOverride: String? = nil, effortOverride: String? = nil, folderID: UUID? = nil) {
        self.key = key
        self.mode = mode
        self.tracker = tracker
        self.customTrackerID = customTrackerID
        self.customTrackerName = customTrackerName
        self.template = template
        self.modelOverride = modelOverride
        self.effortOverride = effortOverride
        self.folderID = folderID
    }

    static let binDays = 30

    var trackerName: String { tracker == .custom ? (customTrackerName ?? Tracker.custom.label) : tracker.label }

    /// Same ticket, mode and tracker: a fresh run of it supersedes this one.
    func sameRun(as other: ResearchDraft) -> Bool {
        key == other.key && mode == other.mode && tracker == other.tracker && customTrackerID == other.customTrackerID
    }

    /// "3 research steps done", "Research done — plan not written", "Not started".
    var progressSummary: String {
        guard let snapshot else { return "Starts from the beginning" }
        if snapshot.researchDone { return "Research done, plan not written yet" }
        return "\(snapshot.turn) research step\(snapshot.turn == 1 ? "" : "s") done"
    }

    /// Days left before the bin deletes it.
    var daysLeftInBin: Int? {
        guard let binnedAt else { return nil }
        let left = Self.binDays - (Calendar.current.dateComponents([.day], from: binnedAt, to: .now).day ?? 0)
        return max(left, 0)
    }
}

enum DraftError: LocalizedError {
    case serverGone(String)

    var errorDescription: String? {
        switch self {
        case .serverGone(let name): "\(name) isn't set up any more. Add it again in \(Platform.settingsName) to resume."
        }
    }
}

/// Why the live run is being stopped, so the catch knows whether to pause, bin or report.
enum RunStopReason {
    case none
    case pause
    case discard
    /// Paused by the system, e.g. iOS ending background time; the text is shown on the draft.
    case system(String)
}

extension PlanStore {
    private var draftsURL: URL {
        URL.applicationSupportDirectory.appending(path: "Checkpoint/drafts.json")
    }

    /// Runs waiting to be resumed, newest first (the live one isn't listed).
    var unfinishedDrafts: [ResearchDraft] {
        drafts.filter { $0.binnedAt == nil && $0.id != runningDraftID }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var binnedDrafts: [ResearchDraft] {
        drafts.filter { $0.binnedAt != nil }.sorted { ($0.binnedAt ?? .now) > ($1.binnedAt ?? .now) }
    }

    static let unfinishedTag = "unfinished"
    static let binTag = "bin"

    var showingUnfinished: Bool { selection == Self.unfinishedTag }
    var showingBin: Bool { selection == Self.binTag }

    // MARK: Actions

    func resume(_ id: UUID, settings: AppSettings) {
        guard let draft = drafts.first(where: { $0.id == id }) else { return }
        guard settings.isLLMConfigured else {
            error = "Set up an AI provider in \(Platform.settingsName) to resume."
            return
        }
        startDraft(draft, settings: settings)
    }

    func moveToBin(_ id: UUID) {
        guard let i = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[i].binnedAt = .now
        saveDrafts()
    }

    func restoreFromBin(_ id: UUID) {
        guard let i = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[i].binnedAt = nil
        drafts[i].updatedAt = .now
        saveDrafts()
    }

    func deleteDraft(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        saveDrafts()
    }

    func emptyBin() {
        drafts.removeAll { $0.binnedAt != nil }
        saveDrafts()
    }

    // MARK: Run bookkeeping (called by the runners)

    func upsertDraft(_ draft: ResearchDraft) {
        if let i = drafts.firstIndex(where: { $0.id == draft.id }) { drafts[i] = draft } else { drafts.append(draft) }
        saveDrafts()
    }

    /// After every finished research step: keep the conversation and the feed so far.
    func saveSnapshot(_ snapshot: ResearchSnapshot, for id: UUID) {
        guard let i = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[i].snapshot = snapshot
        drafts[i].feed = feed
        drafts[i].updatedAt = .now
        saveDrafts()
    }

    /// The plan was written: the draft is done.
    func finishDraft(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        saveDrafts()
    }

    /// The run stopped early. Paused and discarded runs are kept quietly; failures say what happened.
    func draftStopped(_ id: UUID, error: Error, reportError: Bool = true) {
        let reason = stopReason
        stopReason = .none
        guard let i = drafts.firstIndex(where: { $0.id == id }) else { return }
        var d = drafts[i]
        d.feed = feed.map { item in
            var item = item
            if item.state == .pending { item.state = .failed }
            return item
        }
        if let startedAt { d.researchSeconds += Date().timeIntervalSince(startedAt) }
        d.updatedAt = .now
        let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
        // Dropped in the background (iOS suspended the app, the connection went): no alarm,
        // just carry on when the app is back in front.
        let lostInBackground = appInBackground && !cancelled && Self.isConnectionLoss(error)
        if case .system = reason { autoResumeDraftID = id }
        if lostInBackground { autoResumeDraftID = id }
        switch reason {
        case .discard:
            d.status = .paused
            d.binnedAt = .now
        case .pause:
            d.status = .paused
            d.errorMessage = nil
        case .system(let why):
            d.status = .paused
            d.errorMessage = why
        case .none where cancelled:
            d.status = .paused
            d.errorMessage = nil
        case .none where lostInBackground:
            d.status = .paused
            d.errorMessage = "The connection dropped while Checkpoint was in the background."
        case .none:
            d.status = .failed
            d.errorMessage = error.localizedDescription
            if reportError {
                self.error = "\(error.localizedDescription) Saved to Unfinished, so you can resume it from where it stopped."
            }
        }
        drafts[i] = d
        saveDrafts()
    }

    /// Back in front: carry on with a run that iOS stopped or cut off in the background.
    func resumeAfterBackground(settings: AppSettings) {
        guard let id = autoResumeDraftID else { return }
        autoResumeDraftID = nil
        guard !isRunning, drafts.contains(where: { $0.id == id && $0.binnedAt == nil }) else { return }
        resume(id, settings: settings)
    }

    nonisolated static func isConnectionLoss(_ error: Error) -> Bool {
        let codes: Set<URLError.Code> = [.networkConnectionLost, .notConnectedToInternet, .timedOut,
                                         .cannotConnectToHost, .dataNotAllowed, .backgroundSessionWasDisconnected,
                                         .secureConnectionFailed]
        if let url = error as? URLError { return codes.contains(url.code) }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return codes.contains(URLError.Code(rawValue: ns.code)) }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isConnectionLoss(underlying) }
        return false
    }

    // MARK: Storage

    func loadDrafts() {
        guard let data = try? Data(contentsOf: draftsURL),
              var saved = try? JSONDecoder().decode([ResearchDraft].self, from: data) else { return }
        // A run marked running at launch means the app was closed or killed mid-run.
        for i in saved.indices where saved[i].status == .running {
            saved[i].status = .paused
            saved[i].errorMessage = "Interrupted: Checkpoint closed before it finished."
        }
        drafts = saved
        purgeBin()
    }

    func saveDrafts() {
        purgeBin()
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        try? data.write(to: draftsURL, options: .atomic)
    }

    /// Anything in the bin for 30 days or more is deleted for good.
    private func purgeBin() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -ResearchDraft.binDays, to: .now) ?? .distantPast
        drafts.removeAll { ($0.binnedAt ?? .distantFuture) < cutoff }
    }
}

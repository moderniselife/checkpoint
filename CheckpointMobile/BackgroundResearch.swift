import BackgroundTasks
import Foundation
import os

/// Keeps a plan being written after you leave the app. iOS 26's continued-processing
/// tasks run work the person started, show its progress on the Lock Screen and in the
/// Dynamic Island, and let them stop it from there.
///
/// If iOS ends the task anyway, the run is paused (not failed) and picks up from its last
/// finished research step when you come back to the app.
@MainActor
final class BackgroundResearch {
    static let shared = BackgroundResearch()
    private static let prefix = "com.josephshenton.checkpoint.analyze"
    private let log = Logger(subsystem: "com.josephshenton.checkpoint", category: "background")

    private var task: BGContinuedProcessingTask?
    private var watcher: Task<Void, Never>?
    /// Submitted but not started yet; a second run mustn't submit another.
    private var pendingID: String?

    /// Call when a run starts, while the app is in front. One task covers a whole batch:
    /// iOS only accepts new requests from the foreground.
    func begin(key: String, store: PlanStore) {
        if let task {
            task.updateTitle(Self.title(key), subtitle: "Starting…")
            return
        }
        guard pendingID == nil else { return }
        let id = "\(Self.prefix).\(UUID().uuidString)"
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self, weak store] task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            MainActor.assumeIsolated {
                guard let self, let store, store.isRunning else {
                    task.setTaskCompleted(success: true)
                    self?.pendingID = nil
                    return
                }
                self.attach(task, store: store)
            }
        }
        guard registered else {
            log.error("Couldn't register \(id, privacy: .public)")
            return
        }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: Self.title(key), subtitle: "Reading the ticket…")
        // Only worth doing now; if the system can't start it straight away, skip it.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            pendingID = id
        } catch {
            log.error("Submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func attach(_ task: BGContinuedProcessingTask, store: PlanStore) {
        log.info("Background task started")
        pendingID = nil
        self.task = task
        // Fine-grained units so every tick moves the bar: iOS treats a task whose progress
        // stops moving as stuck, and long model turns can sit in one phase for minutes.
        task.progress.totalUnitCount = 1000
        task.expirationHandler = { [weak self, weak store] in
            Task { @MainActor in
                self?.log.notice("Background task expired by the system")
                store?.pause(reason: .system("iOS stopped it in the background. It carries on when you open Checkpoint."))
                self?.task = nil
            }
        }
        watcher = Task { [weak self, weak store] in
            while !Task.isCancelled, let store, store.isRunning {
                let (target, detail) = Self.progress(for: store.phase)
                let current = task.progress.completedUnitCount
                task.progress.completedUnitCount = min(max(current + 1, target), 990)
                task.updateTitle(Self.title(store.runningKey ?? ""), subtitle: detail)
                try? await Task.sleep(for: .milliseconds(700))
            }
            self?.end(success: store?.error == nil)
        }
    }

    func end(success: Bool) {
        watcher?.cancel()
        watcher = nil
        guard let task else { return }
        log.info("Background task finished, success: \(success)")
        task.progress.completedUnitCount = task.progress.totalUnitCount
        task.setTaskCompleted(success: success)
        self.task = nil
    }

    private static func title(_ key: String) -> String { "Writing a test plan for \(key)" }

    /// A rough 0–1000 from the live phase: reading dominates, writing finishes it off.
    private static func progress(for phase: LivePhase) -> (Int64, String) {
        switch phase {
        case .connecting:
            (50, "Connecting to your tracker…")
        case .thinking(let turn):
            (Int64(min(150 + turn * 60, 550)), "Researching the ticket…")
        case .reading(let done, let total):
            (Int64(200 + (total > 0 ? 500 * done / total : 0)), "Read \(done) of \(total) linked items")
        case .writing(let characters):
            (Int64(min(750 + characters / 50, 970)), "Writing the plan…")
        }
    }
}

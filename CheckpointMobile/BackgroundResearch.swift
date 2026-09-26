import BackgroundTasks
import Foundation

/// Keeps a plan being written after you leave the app. iOS 26's continued-processing
/// tasks run work the person started, show its progress on the Lock Screen and in the
/// Dynamic Island, and let them stop it from there.
@MainActor
final class BackgroundResearch {
    static let shared = BackgroundResearch()
    private static let prefix = "com.josephshenton.checkpoint.analyze"

    private var task: BGContinuedProcessingTask?
    private var watcher: Task<Void, Never>?

    /// Call when an analysis starts, while the app is in front.
    func begin(key: String, store: PlanStore) {
        end(success: true)
        let id = "\(Self.prefix).\(UUID().uuidString)"
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self, weak store] task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            MainActor.assumeIsolated {
                guard let self, let store else { task.setTaskCompleted(success: false); return }
                self.attach(task, key: key, store: store)
            }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: "Writing a test plan for \(key)",
                                                       subtitle: "Reading the ticket…")
        // Only worth doing now; if the system can't start it straight away, skip it.
        request.strategy = .fail
        try? BGTaskScheduler.shared.submit(request)
    }

    private func attach(_ task: BGContinuedProcessingTask, key: String, store: PlanStore) {
        self.task = task
        task.progress.totalUnitCount = 100
        task.expirationHandler = { [weak store] in
            Task { @MainActor in store?.cancel() }
        }
        watcher = Task { [weak self, weak store] in
            while !Task.isCancelled, let store, store.isRunning {
                let (done, detail) = Self.progress(for: store.phase)
                task.progress.completedUnitCount = done
                task.updateTitle("Writing a test plan for \(key)", subtitle: detail)
                try? await Task.sleep(for: .milliseconds(700))
            }
            self?.end(success: store?.error == nil)
        }
    }

    func end(success: Bool) {
        watcher?.cancel()
        watcher = nil
        guard let task else { return }
        task.progress.completedUnitCount = task.progress.totalUnitCount
        task.setTaskCompleted(success: success)
        self.task = nil
    }

    /// A rough 0–100 from the live phase: reading dominates, writing finishes it off.
    private static func progress(for phase: LivePhase) -> (Int64, String) {
        switch phase {
        case .connecting:
            (5, "Connecting to your tracker…")
        case .thinking(let turn):
            (Int64(min(15 + turn * 6, 55)), "Researching the ticket…")
        case .reading(let done, let total):
            (Int64(20 + (total > 0 ? 50 * done / total : 0)), "Read \(done) of \(total) linked items")
        case .writing(let characters):
            (Int64(min(75 + characters / 500, 97)), "Writing the plan…")
        }
    }
}

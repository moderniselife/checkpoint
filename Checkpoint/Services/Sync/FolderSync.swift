import Foundation

/// Syncs through a folder the user picks (iCloud Drive, Dropbox, a network share).
/// One JSON file per plan, folder and smart folder, a tombstone list for deletes,
/// and evidence files mirrored alongside. Where both sides changed a plan, the newer
/// `updatedAt` wins. The OS moves the files between devices; this only reads and writes.
///
///     <folder>/plans/<id>.json
///     <folder>/folders/<uuid>.json
///     <folder>/smart/<uuid>.json
///     <folder>/deleted.json
///     <folder>/evidence/<plan id>/<task id>/<file>
nonisolated final class FolderSyncIO: @unchecked Sendable {
    let root: URL
    private let fm = FileManager.default

    init(root: URL) { self.root = root }

    struct Tombstones: Codable, Sendable {
        var plans: [String: Date] = [:]
        var folders: [UUID: Date] = [:]
        var smart: [UUID: Date] = [:]

        mutating func merge(_ other: Tombstones) {
            plans.merge(other.plans) { max($0, $1) }
            folders.merge(other.folders) { max($0, $1) }
            smart.merge(other.smart) { max($0, $1) }
        }

        /// Forget deletes older than 90 days so the file doesn't grow forever.
        mutating func prune() {
            let cutoff = Date.now.addingTimeInterval(-90 * 86400)
            plans = plans.filter { $0.value > cutoff }
            folders = folders.filter { $0.value > cutoff }
            smart = smart.filter { $0.value > cutoff }
        }
    }

    struct Remote: Sendable {
        var plans: [SavedPlan] = []
        var folders: [PlanFolder] = []
        var smartFolders: [SmartFolder] = []
        var tombstones = Tombstones()
        /// Files still downloading from iCloud; the next pass picks them up.
        var pending = 0
    }

    private var plansDir: URL { root.appending(path: "plans", directoryHint: .isDirectory) }
    private var foldersDir: URL { root.appending(path: "folders", directoryHint: .isDirectory) }
    private var smartDir: URL { root.appending(path: "smart", directoryHint: .isDirectory) }
    private var evidenceDir: URL { root.appending(path: "evidence", directoryHint: .isDirectory) }
    private var tombstoneURL: URL { root.appending(path: "deleted.json") }

    func prepare() throws {
        for dir in [plansDir, foldersDir, smartDir, evidenceDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: Reading

    func readAll() -> Remote {
        var r = Remote()
        r.plans = readDir(plansDir, as: SavedPlan.self, pending: &r.pending)
        r.folders = readDir(foldersDir, as: PlanFolder.self, pending: &r.pending)
        r.smartFolders = readDir(smartDir, as: SmartFolder.self, pending: &r.pending)
        if let data = coordinatedRead(tombstoneURL),
           let t = try? JSONDecoder().decode(Tombstones.self, from: data) {
            r.tombstones = t
        }
        return r
    }

    private func readDir<T: Decodable>(_ dir: URL, as: T.Type, pending: inout Int) -> [T] {
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        var out: [T] = []
        for name in names {
            // iCloud Drive on iOS keeps not-yet-downloaded files as ".name.icloud" placeholders.
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                let real = dir.appending(path: String(name.dropFirst().dropLast(7)))
                try? fm.startDownloadingUbiquitousItem(at: real)
                pending += 1
                continue
            }
            guard name.hasSuffix(".json"), let data = coordinatedRead(dir.appending(path: name)),
                  let value = try? JSONDecoder().decode(T.self, from: data) else { continue }
            out.append(value)
        }
        return out
    }

    private func coordinatedRead(_ url: URL) -> Data? {
        var result: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { url in
            result = try? Data(contentsOf: url)
        }
        return result
    }

    // MARK: Writing

    func write(plan: SavedPlan) { write(plan, to: plansDir.appending(path: SyncNames.file(forPlan: plan.id))) }
    func write(folder: PlanFolder) { write(folder, to: foldersDir.appending(path: "\(folder.id.uuidString).json")) }
    func write(smart: SmartFolder) { write(smart, to: smartDir.appending(path: "\(smart.id.uuidString).json")) }

    func removePlan(_ id: String) {
        remove(plansDir.appending(path: SyncNames.file(forPlan: id)))
        remove(evidenceDir.appending(path: SyncNames.file(forPlan: id).replacingOccurrences(of: ".json", with: ""),
                                     directoryHint: .isDirectory))
    }
    func removeFolder(_ id: UUID) { remove(foldersDir.appending(path: "\(id.uuidString).json")) }
    func removeSmart(_ id: UUID) { remove(smartDir.appending(path: "\(id.uuidString).json")) }

    func writeTombstones(_ t: Tombstones) {
        var merged = t
        if let data = coordinatedRead(tombstoneURL), let existing = try? JSONDecoder().decode(Tombstones.self, from: data) {
            merged.merge(existing)
        }
        merged.prune()
        write(merged, to: tombstoneURL)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &error) { url in
            try? data.write(to: url, options: .atomic)
        }
    }

    private func remove(_ url: URL) {
        guard fm.fileExists(atPath: url.path) else { return }
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { url in
            try? fm.removeItem(at: url)
        }
    }

    // MARK: Evidence

    /// Copies evidence named in `plan` both ways, so each side ends up with every file.
    /// Returns true if anything arrived locally.
    @discardableResult
    func mirrorEvidence(for plan: SavedPlan, localRoot: URL) -> Bool {
        let remotePlan = evidenceDir.appending(path: SyncNames.file(forPlan: plan.id).replacingOccurrences(of: ".json", with: ""),
                                               directoryHint: .isDirectory)
        let localPlan = localRoot.appending(path: plan.id, directoryHint: .isDirectory)
        var arrived = false
        for (taskID, names) in plan.evidence {
            let r = remotePlan.appending(path: taskID, directoryHint: .isDirectory)
            let l = localPlan.appending(path: taskID, directoryHint: .isDirectory)
            for name in names {
                let rf = r.appending(path: name), lf = l.appending(path: name)
                let hasR = fm.fileExists(atPath: rf.path), hasL = fm.fileExists(atPath: lf.path)
                if hasL && !hasR {
                    try? fm.createDirectory(at: r, withIntermediateDirectories: true)
                    var error: NSError?
                    NSFileCoordinator().coordinate(writingItemAt: rf, options: .forReplacing, error: &error) { url in
                        try? fm.copyItem(at: lf, to: url)
                    }
                } else if hasR && !hasL {
                    try? fm.createDirectory(at: l, withIntermediateDirectories: true)
                    var error: NSError?
                    NSFileCoordinator().coordinate(readingItemAt: rf, options: [], error: &error) { url in
                        if (try? fm.copyItem(at: url, to: lf)) != nil { arrived = true }
                    }
                } else if !hasR && !hasL {
                    // Maybe still in iCloud.
                    let placeholder = r.appending(path: ".\(name).icloud")
                    if fm.fileExists(atPath: placeholder.path) { try? fm.startDownloadingUbiquitousItem(at: rf) }
                }
            }
        }
        return arrived
    }
}

/// Drives `FolderSyncIO`: first merge, then pushes local changes and polls for remote ones.
@MainActor
final class FolderSyncBackend {
    private let io: FolderSyncIO
    private let root: URL
    private weak var store: PlanStore?
    private let report: (SyncStatus) -> Void
    private var pollTask: Task<Void, Never>?
    private var busy = false

    init(root: URL, store: PlanStore, report: @escaping (SyncStatus) -> Void) {
        self.root = root
        self.io = FolderSyncIO(root: root)
        self.store = store
        self.report = report
    }

    func start() {
        do {
            try io.prepare()
        } catch {
            report(.failed("Couldn't use that folder: \(error.localizedDescription)"))
            return
        }
        Task { await sync(initial: true) }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await self?.sync(initial: false)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        root.stopAccessingSecurityScopedResource()
    }

    func syncNow() { Task { await sync(initial: false) } }

    /// Writes local changes straight away; remote changes arrive on the next poll.
    func push(_ c: StoreChanges) {
        guard let store else { return }
        let io = io
        let localRoot = store.evidenceRootURL
        var tomb = FolderSyncIO.Tombstones()
        let now = Date.now
        for id in c.deletedPlans { tomb.plans[id] = now }
        for id in c.deletedFolders { tomb.folders[id] = now }
        for id in c.deletedSmartFolders { tomb.smart[id] = now }
        Task.detached {
            for p in c.plans {
                io.write(plan: p)
                io.mirrorEvidence(for: p, localRoot: localRoot)
            }
            for f in c.folders { io.write(folder: f) }
            for s in c.smartFolders { io.write(smart: s) }
            for id in c.deletedPlans { io.removePlan(id) }
            for id in c.deletedFolders { io.removeFolder(id) }
            for id in c.deletedSmartFolders { io.removeSmart(id) }
            if !(tomb.plans.isEmpty && tomb.folders.isEmpty && tomb.smart.isEmpty) { io.writeTombstones(tomb) }
        }
        report(.synced(.now))
    }

    private func sync(initial: Bool) async {
        guard !busy, let store else { return }
        busy = true
        defer { busy = false }
        if initial { report(.syncing) }
        let io = io
        let remote = await Task.detached { io.readAll() }.value
        let local = store.snapshot
        let localByID = Dictionary(local.plans.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let remoteByID = Dictionary(remote.plans.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var incoming = StoreChanges()
        var outgoing = StoreChanges()

        // Plans: newer wins; tombstones beat anything older than the delete.
        for r in remote.plans {
            if let deleted = remote.tombstones.plans[r.id], deleted >= r.updatedAt { continue }
            if let l = localByID[r.id] {
                if r.updatedAt > l.updatedAt { incoming.plans.append(r) }
                else if l.updatedAt > r.updatedAt { outgoing.plans.append(l) }
            } else {
                incoming.plans.append(r)
            }
        }
        for l in local.plans where remoteByID[l.id] == nil {
            if let deleted = remote.tombstones.plans[l.id], deleted >= l.updatedAt {
                incoming.deletedPlans.append(l.id)
            } else {
                outgoing.plans.append(l)
            }
        }

        // Folders and smart folders have no edit time: the remote copy wins,
        // and local-only ones are uploaded unless they were deleted elsewhere.
        let remoteFolders = Dictionary(remote.folders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for f in remote.folders where remote.tombstones.folders[f.id] == nil {
            if local.folders.first(where: { $0.id == f.id }) != f { incoming.folders.append(f) }
        }
        for f in local.folders where remoteFolders[f.id] == nil {
            if remote.tombstones.folders[f.id] != nil { incoming.deletedFolders.append(f.id) } else { outgoing.folders.append(f) }
        }
        let remoteSmart = Dictionary(remote.smartFolders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for f in remote.smartFolders where remote.tombstones.smart[f.id] == nil {
            if local.smartFolders.first(where: { $0.id == f.id }) != f { incoming.smartFolders.append(f) }
        }
        for f in local.smartFolders where remoteSmart[f.id] == nil {
            if remote.tombstones.smart[f.id] != nil { incoming.deletedSmartFolders.append(f.id) } else { outgoing.smartFolders.append(f) }
        }

        store.applyRemote(incoming)
        if !outgoing.isEmpty { push(outgoing) }

        // Evidence for every live plan, both directions.
        let localRoot = store.evidenceRootURL
        let plans = store.snapshot.plans.filter { !$0.evidence.isEmpty }
        let arrived = await Task.detached { plans.filter { io.mirrorEvidence(for: $0, localRoot: localRoot) }.map(\.id) }.value
        for id in arrived { store.noteRemoteEvidence(planID: id) }

        report(remote.pending > 0 ? .waitingForDownloads(remote.pending) : .synced(.now))
    }
}

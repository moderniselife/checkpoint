import CloudKit
import Foundation

/// iCloud sync through CloudKit's private database, driven by `CKSyncEngine`.
///
/// Only runs in builds that set `CheckpointCloudKitContainer` in Info.plist (via the
/// `CHECKPOINT_CLOUDKIT_CONTAINER` build setting) *and* carry the matching iCloud
/// entitlement — creating a container without the entitlement crashes, so the app
/// never touches CloudKit unless the container is configured. See docs/sync.md.
///
/// Records live in one zone: `Plan` (JSON payload as an asset, plus `updatedAt`),
/// `Folder` and `SmartFolder` (small JSON payloads), and `Evidence` (one file each).
@MainActor
final class CloudKitSyncBackend {
    /// The configured container, or nil in builds without iCloud.
    nonisolated static var containerID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "CheckpointCloudKitContainer") as? String,
              !id.isEmpty, !id.hasPrefix("$(") else { return nil }
        return id
    }

    private static let zoneID = CKRecordZone.ID(zoneName: "Checkpoint")

    private weak var store: PlanStore?
    private let report: (SyncStatus) -> Void
    private var engine: CKSyncEngine?
    private var delegate: EngineDelegate?
    private let container: CKContainer

    /// Server system fields per record, so saves update rather than conflict.
    private var systemFields: [String: Data] = [:]
    /// Evidence already uploaded, as "planID/taskID/name".
    private var uploadedEvidence: Set<String> = []

    private let stateDir: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Checkpoint/CloudKit", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private var engineStateURL: URL { stateDir.appending(path: "engine-state.plist") }
    private var fieldsURL: URL { stateDir.appending(path: "system-fields.plist") }
    private var assetsDir: URL {
        let dir = URL.cachesDirectory.appending(path: "CheckpointCloudKitAssets", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init?(store: PlanStore, report: @escaping (SyncStatus) -> Void) {
        guard let id = Self.containerID else { return nil }
        self.store = store
        self.report = report
        self.container = CKContainer(identifier: id)
    }

    func start() {
        report(.syncing)
        if let data = try? Data(contentsOf: fieldsURL),
           let saved = try? PropertyListDecoder().decode([String: Data].self, from: data) {
            systemFields = saved
        }
        uploadedEvidence = Set(UserDefaults.standard.stringArray(forKey: "cloudKitUploadedEvidence") ?? [])
        let state: CKSyncEngine.State.Serialization? = (try? Data(contentsOf: engineStateURL))
            .flatMap { try? PropertyListDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        let delegate = EngineDelegate(backend: self)
        self.delegate = delegate
        let config = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                stateSerialization: state, delegate: delegate)
        let engine = CKSyncEngine(config)
        self.engine = engine
        if state == nil {
            // First run on this device: create the zone and offer everything local.
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            if let store { enqueue(everything: store.snapshot) }
        }
        Task { await syncNow() }
    }

    func stop() {
        engine = nil
        delegate = nil
    }

    func syncNow() async {
        guard let engine else { return }
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            report(.synced(.now))
        } catch {
            report(.failed(Self.describe(error)))
        }
    }

    func push(_ c: StoreChanges) {
        guard let engine else { return }
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        for p in c.plans {
            pending.append(.saveRecord(Self.recordID("plan", SyncNames.file(forPlan: p.id))))
            pending += evidenceChanges(for: p)
        }
        pending += c.deletedPlans.map { .deleteRecord(Self.recordID("plan", SyncNames.file(forPlan: $0))) }
        pending += c.folders.map { .saveRecord(Self.recordID("folder", $0.id.uuidString)) }
        pending += c.deletedFolders.map { .deleteRecord(Self.recordID("folder", $0.uuidString)) }
        pending += c.smartFolders.map { .saveRecord(Self.recordID("smart", $0.id.uuidString)) }
        pending += c.deletedSmartFolders.map { .deleteRecord(Self.recordID("smart", $0.uuidString)) }
        engine.state.add(pendingRecordZoneChanges: pending)
    }

    private func enqueue(everything s: StoreSnapshot) {
        var c = StoreChanges()
        c.plans = s.plans
        c.folders = s.folders
        c.smartFolders = s.smartFolders
        push(c)
    }

    private func evidenceChanges(for plan: SavedPlan) -> [CKSyncEngine.PendingRecordZoneChange] {
        var out: [CKSyncEngine.PendingRecordZoneChange] = []
        for (taskID, names) in plan.evidence {
            for name in names {
                let key = "\(plan.id)/\(taskID)/\(name)"
                guard !uploadedEvidence.contains(key) else { continue }
                out.append(.saveRecord(Self.recordID("evidence", Self.evidenceName(key))))
            }
        }
        return out
    }

    // MARK: Records

    private static func recordID(_ kind: String, _ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(kind)-\(name)", zoneID: zoneID)
    }

    private static func evidenceName(_ key: String) -> String {
        Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
    }

    private func blankRecord(type: String, id: CKRecord.ID) -> CKRecord {
        if let data = systemFields[id.recordName], let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
            coder.requiresSecureCoding = true
            if let record = CKRecord(coder: coder) { return record }
        }
        return CKRecord(recordType: type, recordID: id)
    }

    private func remember(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        systemFields[record.recordID.recordName] = coder.encodedData
        if let data = try? PropertyListEncoder().encode(systemFields) { try? data.write(to: fieldsURL, options: .atomic) }
    }

    /// Builds the record to upload for a pending id from current local data, or nil if it's gone.
    fileprivate func record(for id: CKRecord.ID) -> CKRecord? {
        guard let store else { return nil }
        let name = id.recordName
        let snap = store.snapshot
        if name.hasPrefix("plan-") {
            let planID = SyncNames.plan(fromFile: String(name.dropFirst(5)))
            guard let plan = snap.plans.first(where: { $0.id == planID }),
                  let data = try? JSONEncoder().encode(plan) else { return nil }
            let file = assetsDir.appending(path: "\(name).json")
            guard (try? data.write(to: file, options: .atomic)) != nil else { return nil }
            let r = blankRecord(type: "Plan", id: id)
            r["planID"] = plan.id
            r["updatedAt"] = plan.updatedAt
            r["payload"] = CKAsset(fileURL: file)
            return r
        }
        if name.hasPrefix("folder-") {
            guard let f = snap.folders.first(where: { "folder-\($0.id.uuidString)" == name }),
                  let data = try? JSONEncoder().encode(f) else { return nil }
            let r = blankRecord(type: "Folder", id: id)
            r["payload"] = data
            return r
        }
        if name.hasPrefix("smart-") {
            guard let f = snap.smartFolders.first(where: { "smart-\($0.id.uuidString)" == name }),
                  let data = try? JSONEncoder().encode(f) else { return nil }
            let r = blankRecord(type: "SmartFolder", id: id)
            r["payload"] = data
            return r
        }
        if name.hasPrefix("evidence-") {
            for plan in snap.plans {
                for (taskID, names) in plan.evidence {
                    for file in names where "evidence-\(Self.evidenceName("\(plan.id)/\(taskID)/\(file)"))" == name {
                        let url = store.evidenceDir(planID: plan.id, taskID: taskID).appending(path: file)
                        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                        let r = blankRecord(type: "Evidence", id: id)
                        r["planID"] = plan.id
                        r["taskID"] = taskID
                        r["name"] = file
                        r["file"] = CKAsset(fileURL: url)
                        return r
                    }
                }
            }
        }
        return nil
    }

    // MARK: Engine events

    fileprivate func handle(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let e):
            if let data = try? PropertyListEncoder().encode(e.stateSerialization) {
                try? data.write(to: engineStateURL, options: .atomic)
            }
        case .accountChange(let e):
            switch e.changeType {
            case .signIn: report(.syncing)
            case .signOut: report(.failed("Signed out of iCloud. Sign in from Settings to keep syncing."))
            case .switchAccounts:
                // Different person's data: start over rather than mix accounts.
                systemFields = [:]
                try? FileManager.default.removeItem(at: engineStateURL)
                report(.failed("The iCloud account changed. Turn iCloud sync off and on to start fresh."))
            @unknown default: break
            }
        case .fetchedRecordZoneChanges(let e):
            applyFetched(e.modifications.map(\.record), deletions: e.deletions.map(\.recordID))
        case .sentRecordZoneChanges(let e):
            e.savedRecords.forEach(remember)
            for saved in e.savedRecords where saved.recordType == "Evidence" {
                if let p = saved["planID"] as? String, let t = saved["taskID"] as? String, let n = saved["name"] as? String {
                    uploadedEvidence.insert("\(p)/\(t)/\(n)")
                }
            }
            UserDefaults.standard.set(Array(uploadedEvidence), forKey: "cloudKitUploadedEvidence")
            var retry: [CKSyncEngine.PendingRecordZoneChange] = []
            for failure in e.failedRecordSaves {
                let id = failure.record.recordID
                switch failure.error.code {
                case .serverRecordChanged:
                    // Someone else saved first: newer plan wins, otherwise keep ours on top of theirs.
                    if let server = failure.error.serverRecord {
                        remember(server)
                        let serverDate = server["updatedAt"] as? Date ?? .distantPast
                        let localDate = failure.record["updatedAt"] as? Date ?? .distantPast
                        if serverDate > localDate { applyFetched([server], deletions: []) } else { retry.append(.saveRecord(id)) }
                    }
                case .zoneNotFound, .userDeletedZone:
                    engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                    retry.append(.saveRecord(id))
                case .unknownItem:
                    systemFields[id.recordName] = nil
                    retry.append(.saveRecord(id))
                case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                    break  // CKSyncEngine retries these itself.
                case .quotaExceeded:
                    report(.failed("Your iCloud storage is full."))
                default:
                    report(.failed(Self.describe(failure.error)))
                }
            }
            if !retry.isEmpty { engine?.state.add(pendingRecordZoneChanges: retry) }
            report(.synced(.now))
        case .didFetchChanges, .didSendChanges:
            report(.synced(.now))
        default:
            break
        }
    }

    private func applyFetched(_ records: [CKRecord], deletions: [CKRecord.ID]) {
        guard let store else { return }
        let snap = store.snapshot
        var c = StoreChanges()
        var requeue: [CKSyncEngine.PendingRecordZoneChange] = []
        for r in records {
            remember(r)
            switch r.recordType {
            case "Plan":
                guard let url = (r["payload"] as? CKAsset)?.fileURL, let data = try? Data(contentsOf: url),
                      let plan = try? JSONDecoder().decode(SavedPlan.self, from: data) else { continue }
                if let local = snap.plans.first(where: { $0.id == plan.id }), local.updatedAt > plan.updatedAt {
                    requeue.append(.saveRecord(r.recordID))
                } else {
                    c.plans.append(plan)
                }
            case "Folder":
                if let data = r["payload"] as? Data, let f = try? JSONDecoder().decode(PlanFolder.self, from: data) { c.folders.append(f) }
            case "SmartFolder":
                if let data = r["payload"] as? Data, let f = try? JSONDecoder().decode(SmartFolder.self, from: data) { c.smartFolders.append(f) }
            case "Evidence":
                guard let p = r["planID"] as? String, let t = r["taskID"] as? String, let n = r["name"] as? String,
                      let src = (r["file"] as? CKAsset)?.fileURL else { continue }
                let dir = store.evidenceDir(planID: p, taskID: t)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appending(path: n)
                if !FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.copyItem(at: src, to: dest) }
                uploadedEvidence.insert("\(p)/\(t)/\(n)")
                store.noteRemoteEvidence(planID: p)
            default: break
            }
        }
        for id in deletions {
            let name = id.recordName
            systemFields[name] = nil
            if name.hasPrefix("plan-"), let planID = SyncNames.plan(fromFile: String(name.dropFirst(5))) {
                c.deletedPlans.append(planID)
            } else if name.hasPrefix("folder-"), let uuid = UUID(uuidString: String(name.dropFirst(7))) {
                c.deletedFolders.append(uuid)
            } else if name.hasPrefix("smart-"), let uuid = UUID(uuidString: String(name.dropFirst(6))) {
                c.deletedSmartFolders.append(uuid)
            }
        }
        store.applyRemote(c)
        if !requeue.isEmpty { engine?.state.add(pendingRecordZoneChanges: requeue) }
    }

    fileprivate func batch(_ context: CKSyncEngine.SendChangesContext, _ engine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = engine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            await self.record(for: id)
        }
    }

    private static func describe(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated: return "Sign in to iCloud in Settings to sync."
            case .networkUnavailable, .networkFailure: return "Offline — changes will sync when you're back online."
            case .quotaExceeded: return "Your iCloud storage is full."
            default: break
            }
        }
        return error.localizedDescription
    }
}

/// CKSyncEngine wants a Sendable delegate; this hops each call onto the main actor.
private final class EngineDelegate: CKSyncEngineDelegate, @unchecked Sendable {
    weak var backend: CloudKitSyncBackend?

    init(backend: CloudKitSyncBackend) { self.backend = backend }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await MainActor.run { backend?.handle(event) }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard let backend = await MainActor.run(body: { self.backend }) else { return nil }
        return await backend.batch(context, syncEngine)
    }
}

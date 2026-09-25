import Foundation
import Observation
#if os(macOS)
import AppKit
#endif

nonisolated enum SyncStatus: Equatable, Sendable {
    case off
    case syncing
    case synced(Date)
    case waitingForDownloads(Int)
    case failed(String)

    var summary: String {
        switch self {
        case .off: "Off"
        case .syncing: "Syncing…"
        case .synced(let d): "Up to date · \(d.formatted(.relative(presentation: .named)))"
        case .waitingForDownloads(let n): "Downloading \(n) file\(n == 1 ? "" : "s") from iCloud…"
        case .failed(let m): m
        }
    }

    var isError: Bool { if case .failed = self { true } else { false } }
}

/// Owns the sync choice and whichever backend is running. Plans, folders, tags,
/// verdicts, notes and evidence sync; API keys and sign-ins stay on each device.
@Observable
@MainActor
final class SyncCoordinator {
    private(set) var mode: SyncMode
    private(set) var status: SyncStatus = .off
    /// Display path of the sync folder, if one is chosen.
    private(set) var folderPath: String?

    /// iCloud needs a build signed with an iCloud container (App Store builds).
    var iCloudAvailable: Bool { CloudKitSyncBackend.containerID != nil }

    @ObservationIgnored private let store: PlanStore
    @ObservationIgnored private var folderBackend: FolderSyncBackend?
    @ObservationIgnored private var cloudBackend: CloudKitSyncBackend?
    @ObservationIgnored private var folderBookmark: Data? {
        didSet { UserDefaults.standard.set(folderBookmark, forKey: "syncFolderBookmark") }
    }

    init(store: PlanStore) {
        self.store = store
        let saved = SyncMode(rawValue: UserDefaults.standard.string(forKey: "syncMode") ?? "") ?? .off
        folderBookmark = UserDefaults.standard.data(forKey: "syncFolderBookmark")
        folderPath = UserDefaults.standard.string(forKey: "syncFolderPath")
        // An App Store build that loses its container (or a self-build) quietly drops back.
        mode = saved == .iCloud && CloudKitSyncBackend.containerID == nil ? .off : saved
        store.onLocalChange = { [weak self] changes in self?.localChanged(changes) }
    }

    @ObservationIgnored private var started = false

    /// Called when a window appears; only the first one starts sync.
    func startIfNeeded() {
        guard !started else { return }
        started = true
        start()
    }

    func start() {
        stopBackends()
        switch mode {
        case .off:
            status = .off
        case .folder:
            guard let root = resolveFolder() else {
                status = .failed("Choose the sync folder again — access to it was lost.")
                return
            }
            let backend = FolderSyncBackend(root: root, store: store) { [weak self] in self?.status = $0 }
            folderBackend = backend
            backend.start()
        case .iCloud:
            guard let backend = CloudKitSyncBackend(store: store, report: { [weak self] in self?.status = $0 }) else {
                status = .failed("iCloud sync isn't available in this build.")
                return
            }
            cloudBackend = backend
            backend.start()
        }
    }

    func setMode(_ new: SyncMode) {
        guard new != mode else { return }
        if new == .iCloud && !iCloudAvailable { return }
        if new == .folder && folderBookmark == nil { return }  // choose a folder first
        mode = new
        UserDefaults.standard.set(new.rawValue, forKey: "syncMode")
        start()
    }

    func syncNow() {
        folderBackend?.syncNow()
        if let cloudBackend { Task { await cloudBackend.syncNow() } }
    }

    private func localChanged(_ c: StoreChanges) {
        folderBackend?.push(c)
        cloudBackend?.push(c)
    }

    private func stopBackends() {
        folderBackend?.stop()
        folderBackend = nil
        cloudBackend?.stop()
        cloudBackend = nil
    }

    // MARK: Sync folder

    /// Uses `url` (or a "Checkpoint" folder inside it) as the sync folder and turns folder sync on.
    func useFolder(_ picked: URL) {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        var url = picked
        if picked.lastPathComponent.lowercased() != "checkpoint" {
            url = picked.appending(path: "Checkpoint", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = .withSecurityScope
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        guard let data = try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            status = .failed("Couldn't keep access to that folder.")
            return
        }
        folderBookmark = data
        folderPath = Self.displayPath(url)
        UserDefaults.standard.set(folderPath, forKey: "syncFolderPath")
        mode = .folder
        UserDefaults.standard.set(SyncMode.folder.rawValue, forKey: "syncMode")
        start()
    }

    func forgetFolder() {
        if mode == .folder { setModeOff() }
        folderBookmark = nil
        folderPath = nil
        UserDefaults.standard.removeObject(forKey: "syncFolderPath")
    }

    private func setModeOff() {
        mode = .off
        UserDefaults.standard.set(SyncMode.off.rawValue, forKey: "syncMode")
        start()
    }

    var hasFolder: Bool { folderBookmark != nil }

    private func resolveFolder() -> URL? {
        guard let data = folderBookmark else { return nil }
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = .withSecurityScope
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        guard let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        _ = url.startAccessingSecurityScopedResource()
        if stale {
            #if os(macOS)
            let create: URL.BookmarkCreationOptions = .withSecurityScope
            #else
            let create: URL.BookmarkCreationOptions = []
            #endif
            if let fresh = try? url.bookmarkData(options: create, includingResourceValuesForKeys: nil, relativeTo: nil) {
                folderBookmark = fresh
            }
        }
        return url
    }

    /// "iCloud Drive › Checkpoint" rather than a Mobile Documents path.
    private static func displayPath(_ url: URL) -> String {
        let path = url.path
        if let r = path.range(of: "com~apple~CloudDocs") {
            return "iCloud Drive" + path[r.upperBound...].replacingOccurrences(of: "/", with: " › ")
        }
        if path.contains("/Mobile Documents/") || path.contains("CloudDocs") { return "iCloud Drive › \(url.lastPathComponent)" }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    #if os(macOS)
    /// Mac: a folder picker that opens in iCloud Drive, the recommended place.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Sync Here"
        panel.message = "Pick a folder for Checkpoint to sync through — iCloud Drive works on every Apple device. A “Checkpoint” folder is made inside it."
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            let drive = URL(fileURLWithPath: String(cString: home)).appending(path: "Library/Mobile Documents/com~apple~CloudDocs")
            if FileManager.default.fileExists(atPath: drive.path) { panel.directoryURL = drive }
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        useFolder(url)
    }
    #endif
}

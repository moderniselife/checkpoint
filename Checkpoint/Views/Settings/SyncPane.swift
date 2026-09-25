import SwiftUI
import UniformTypeIdentifiers

struct SyncPane: View {
    @Environment(SyncCoordinator.self) private var sync
    var body: some View {
        SettingsPane(section: .sync) {
            Section {
                SyncModeRow(mode: .off, title: "Off", detail: "Plans stay on this device.", icon: "iphone.slash") {
                    sync.setMode(.off)
                }
                SyncModeRow(mode: .folder, title: "Sync folder",
                            detail: "Keep plans in a folder that syncs — iCloud Drive, or your company's OneDrive, Google Drive or Dropbox. Free, and works in any build.",
                            icon: "folder.badge.gearshape") {
                    if sync.hasFolder { sync.setMode(.folder) } else { sync.requestFolder() }
                }
                SyncModeRow(mode: .iCloud, title: "iCloud",
                            detail: sync.iCloudAvailable
                                ? "Syncs straight through your iCloud account — nothing to set up. Recommended."
                                : "Comes with the App Store version. Builds you make yourself can use a sync folder in iCloud Drive instead.",
                            icon: "icloud", recommended: sync.iCloudAvailable) {
                    sync.setMode(.iCloud)
                }
                .disabled(!sync.iCloudAvailable)
            } header: {
                Text("Sync with")
            }

            if sync.mode == .folder || sync.hasFolder {
                Section("Sync folder") {
                    LabeledContent("Folder") {
                        Text(sync.folderPath ?? "None")
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        #if os(macOS)
                        Menu("Change Folder…") {
                            Button("In iCloud Drive…", systemImage: "icloud") { sync.requestFolder(start: .iCloudDrive) }
                            Button("In OneDrive, Google Drive or Dropbox…", systemImage: "externaldrive.connected.to.line.below") {
                                sync.requestFolder(start: .cloudStorage)
                            }
                            Button("Somewhere Else…", systemImage: "folder") { sync.requestFolder(start: .anywhere) }
                        }
                        .fixedSize()
                        #else
                        Button("Change Folder…") { sync.requestFolder() }
                        #endif
                        Spacer()
                        Button("Stop Using This Folder", role: .destructive) { sync.forgetFolder() }
                    }
                }
            }

            #if os(macOS)
            if !sync.hasFolder {
                Section {
                    HStack {
                        Text("Work laptop?").foregroundStyle(.secondary)
                        Spacer()
                        Button("Use OneDrive, Google Drive or Dropbox…") { sync.requestFolder(start: .cloudStorage) }
                    }
                } footer: {
                    Text("Their desktop apps sync a normal folder, so Checkpoint's data stays in your company's storage rather than a personal iCloud.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            #endif

            if sync.mode != .off {
                Section {
                    HStack {
                        Label(sync.status.summary, systemImage: statusIcon)
                            .foregroundStyle(sync.status.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        Spacer()
                        Button("Sync Now", action: sync.syncNow)
                    }
                } footer: {
                    Text("Plans, folders, tags, verdicts, notes and evidence sync. API keys and tracker sign-ins stay on each device, in its Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .syncFolderPicker()
    }

    private var statusIcon: String {
        switch sync.status {
        case .failed: "exclamationmark.icloud"
        case .syncing, .waitingForDownloads: "arrow.triangle.2.circlepath"
        default: "checkmark.icloud"
        }
    }
}

private struct SyncModeRow: View {
    let mode: SyncMode
    let title: String
    let detail: String
    let icon: String
    var recommended = false
    let select: () -> Void
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                        if recommended {
                            Text("Recommended")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(.cyan.opacity(0.12), in: .capsule)
                        }
                    }
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: sync.mode == mode ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(sync.mode == mode ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .contentShape(.rect)
            .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// iOS: presents the Files folder picker when the sync coordinator asks for one.
    func syncFolderPicker() -> some View {
        modifier(SyncFolderPicker())
    }
}

private struct SyncFolderPicker: ViewModifier {
    @Environment(SyncCoordinator.self) private var sync

    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        @Bindable var sync = sync
        content.fileImporter(isPresented: $sync.wantsFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { sync.useFolder(url) }
        }
        #endif
    }
}

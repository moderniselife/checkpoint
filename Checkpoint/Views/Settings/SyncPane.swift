import SwiftUI
import UniformTypeIdentifiers

struct SyncPane: View {
    @Environment(SyncCoordinator.self) private var sync
    @State private var pickingFolder = false

    var body: some View {
        SettingsPane(section: .sync) {
            Section {
                SyncModeRow(mode: .off, title: "Off", detail: "Plans stay on this device.", icon: "iphone.slash") {
                    sync.setMode(.off)
                }
                SyncModeRow(mode: .folder, title: "Sync folder",
                            detail: "Keep plans in a folder you choose — iCloud Drive syncs it to your other devices. Free, and works in any build.",
                            icon: "folder.badge.gearshape") {
                    if sync.hasFolder { sync.setMode(.folder) } else { pickingFolder = true }
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
                        Button("Change Folder…") { pickingFolder = true }
                        Spacer()
                        Button("Stop Using This Folder", role: .destructive) { sync.forgetFolder() }
                    }
                }
            }

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
        .syncFolderPicker(isPresented: $pickingFolder)
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
    /// Presents the platform's folder picker and hands the result to the sync coordinator.
    func syncFolderPicker(isPresented: Binding<Bool>) -> some View {
        modifier(SyncFolderPicker(isPresented: isPresented))
    }
}

private struct SyncFolderPicker: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(SyncCoordinator.self) private var sync

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onChange(of: isPresented) {
            guard isPresented else { return }
            isPresented = false
            sync.chooseFolder()
        }
        #else
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { sync.useFolder(url) }
        }
        #endif
    }
}

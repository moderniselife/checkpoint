import SwiftUI

/// System Settings-style window: a searchable sidebar of areas and a grouped
/// form for each. Resizable, so it fits a 13" MacBook and grows on a monitor.
///
/// To add an area: add a `SettingsSection` case and its pane in `detail(for:)`.
struct SettingsView: View {
    static let windowID = "settings"
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    /// Mac opens on AI Provider; iPhone starts on the list.
    @State private var selection: SettingsSection? = Platform.isMac ? .aiProvider : nil
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 280)
        } detail: {
            detail(for: selection ?? .aiProvider)
        }
        #if os(macOS)
        .frame(minWidth: 680, idealWidth: 860, minHeight: 480, idealHeight: 620)
        #endif
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(SettingsSection.Group.allCases, id: \.rawValue) { group in
                let rows = group.sections.filter { $0.matches(query) }
                let custom = group == .trackers ? serverRows(settings.trackerServers)
                    : group == .intelligence ? serverRows(settings.researchTools) : []
                if !rows.isEmpty || !custom.isEmpty {
                    Section(group.rawValue) {
                        ForEach(rows, id: \.id) { section in
                            SettingsSidebarRow(title: section.title, icon: section.icon, tint: section.tint,
                                               logo: section.logo, status: status(for: section))
                                .tag(section)
                        }
                        ForEach(custom) { tracker in
                            let research = tracker.role == .research
                            SettingsSidebarRow(title: tracker.displayName,
                                               icon: research ? "wand.and.stars" : "server.rack",
                                               tint: research ? .pink : .teal)
                                .padding(.leading, 12)
                                .tag(research ? SettingsSection.researchTools(id: tracker.id) : .customMCP(id: tracker.id))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $query, placement: .sidebar, prompt: "Search")
        #if os(iOS)
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        #endif
    }

    /// Each custom server gets its own row: trackers under Trackers, research tools under Intelligence.
    private func serverRows(_ servers: [CustomMCPTracker]) -> [CustomMCPTracker] {
        servers.filter {
            query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.endpoint.localizedCaseInsensitiveContains(query)
        }
    }

    private func status(for section: SettingsSection) -> StatusDot.State {
        switch section {
        case .aiProvider: settings.isLLMConfigured ? .ok : .warn
        case .jira: settings.isAtlassianConfigured ? .ok : .none
        case .linear: settings.isLinearConfigured ? .ok : .none
        case .sync: sync.status.isError ? .warn : (sync.mode == .off ? .none : .ok)
        case .customMCP, .researchTools, .testing, .scenarios, .advanced: .none
        }
    }

    @ViewBuilder
    private func detail(for section: SettingsSection) -> some View {
        switch section {
        case .aiProvider: AIProviderPane()
        case .jira: JiraPane()
        case .linear: LinearPane()
        case .customMCP(let id):
            if let id, settings.trackerServers.contains(where: { $0.id == id }) {
                CustomMCPDetailPane(trackerID: id, selection: $selection).id(id)
            } else {
                CustomMCPListPane(selection: $selection)
            }
        case .researchTools(let id):
            if let id, settings.researchTools.contains(where: { $0.id == id }) {
                CustomMCPDetailPane(trackerID: id, selection: $selection).id(id)
            } else {
                CustomMCPListPane(role: .research, selection: $selection)
            }
        case .testing: TestingPane()
        case .scenarios: ScenariosPane()
        case .sync: SyncPane()
        case .advanced: AdvancedPane()
        }
    }
}

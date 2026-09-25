import SwiftUI

/// macOS System Settings-style container: searchable sidebar + scrollable
/// detail. Resizable by design — the sidebar has a bounded width, the detail
/// is a ScrollView with a centered max-width column, so it fits a 13"
/// MacBook and stretches on a desktop monitor.
///
/// To add a settings area: add a `SettingsSection` case, a row in its group,
/// and a pane in `detail(for:)` below. See `SettingsSection.swift`.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var selection: SettingsSection? = .aiProvider
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 300)
        } detail: {
            detail(for: selection ?? .aiProvider)
                .navigationSplitViewColumnWidth(min: 420, ideal: 640)
        }
        // Same mesh wash as the main window (cf. Backdrop in ContentView) so
        // Settings feels like the app, not a system panel. The sidebar list is
        // translucent and detail ScrollViews are transparent, so it glows through.
        .background { Backdrop() }
        // Flexible window: small floor for MacBooks, grows on desktop.
        // (No fixed .frame(width:) / .fixedSize — that's what clipped before.)
        .frame(minWidth: 680, idealWidth: 960, minHeight: 480, idealHeight: 620)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(SettingsSection.Group.allCases, id: \.rawValue) { group in
                let rows = group.sections.filter { $0.matches(query) }
                if !rows.isEmpty {
                    Section(group.rawValue) {
                        ForEach(rows, id: \.id) { section in
                            SettingsSidebarRow(
                                section: section,
                                selected: selection?.id == section.id,
                                status: status(for: section)
                            )
                            .tag(section)
                        }
                        // Custom servers get one row each under Trackers.
                        if group == .trackers, query.isEmpty || "custom".contains(query.lowercased()) {
                            ForEach(settings.customTrackers.filter {
                                query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)
                                    || $0.endpoint.localizedCaseInsensitiveContains(query)
                            }) { tracker in
                                let section = SettingsSection.customMCP(id: tracker.id)
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.teal.gradient)
                                            .frame(width: 28, height: 28)
                                        Image(systemName: "cable.connector")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(.white)
                                    }
                                    Text(tracker.displayName)
                                        .font(.body)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .padding(.leading, 16)
                                .background(selection?.id == section.id ? Color.accentColor.gradient : Color.clear.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .foregroundStyle(selection?.id == section.id ? .white : .primary)
                                .tag(section)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .searchable(text: $query, prompt: "Search")
        .navigationTitle("Checkpoint Settings")
    }

    private func status(for section: SettingsSection) -> StatusDot.State {
        switch section {
        case .aiProvider: settings.isLLMConfigured ? .ok : .warn
        case .jira: settings.isAtlassianConfigured ? .ok : .warn
        case .linear: settings.isLinearConfigured ? .ok : .warn
        case .customMCP: .none
        case .testing, .scenarios, .advanced: .none
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private func detail(for section: SettingsSection) -> some View {
        switch section {
        case .aiProvider: AIProviderPane()
        case .jira: JiraPane()
        case .linear: LinearPane()
        case .customMCP(let id):
            if let id, settings.customTrackers.contains(where: { $0.id == id }) {
                CustomMCPDetailPane(trackerID: id, selection: $selection)
            } else {
                CustomMCPListPane(selection: $selection)
            }
        case .testing: TestingPane()
        case .scenarios: ScenariosPane()
        case .advanced: AdvancedPane()
        }
    }
}

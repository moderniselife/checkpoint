import SwiftUI

/// Rounded gradient tile with a white symbol, like System Settings.
struct SettingsIconTile: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.52, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: size * 0.26, style: .continuous))
    }
}

/// Sidebar row: icon tile, title and an optional status dot. Selection is the list's own.
struct SettingsSidebarRow: View {
    let title: String
    let icon: String
    let tint: Color
    var logo: Tracker? = nil
    var status: StatusDot.State = .none

    var body: some View {
        HStack(spacing: 8) {
            if let logo { TrackerLogo(tracker: logo) } else { SettingsIconTile(icon: icon, tint: tint) }
            Text(title).lineLimit(1)
            Spacer(minLength: 4)
            StatusDot(state: status)
        }
    }
}

/// Grouped form with a compact header, used by every settings pane.
struct SettingsPane<Content: View>: View {
    let section: SettingsSection
    var title: String?
    @ViewBuilder var content: Content

    init(section: SettingsSection, title: String? = nil, @ViewBuilder content: () -> Content) {
        self.section = section
        self.title = title
        self.content = content()
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    if let logo = section.logo {
                        TrackerLogo(tracker: logo, size: 40)
                    } else {
                        SettingsIconTile(icon: section.icon, tint: section.tint, size: 40)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title ?? section.title).font(.title3.weight(.semibold))
                        Text(section.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            content
        }
        .formStyle(.grouped)
        .navigationTitle(title ?? section.title)
    }
}

/// Small connection dot for the sidebar: green = ready, orange = needs setup.
struct StatusDot: View {
    enum State { case ok, warn, none }
    var state: State

    var body: some View {
        switch state {
        case .ok: Circle().fill(.green).frame(width: 7, height: 7).help("Connected")
        case .warn: Circle().fill(.orange).frame(width: 7, height: 7).help("Needs setup")
        case .none: EmptyView()
        }
    }
}

enum ConnectionTestState: Equatable {
    case idle, testing, ok(String, Int), failed(String)
}

/// "Test" button plus its result, on one form row.
struct TestRow: View {
    let title: String
    let state: ConnectionTestState
    let disabled: Bool
    let action: () -> Void
    let success: (String, Int) -> String

    var body: some View {
        HStack {
            Button(title, action: action)
                .disabled(disabled || state == .testing)
            switch state {
            case .idle: EmptyView()
            case .testing: ProgressView().controlSize(.small)
            case .ok(let a, let n): Label(success(a, n), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let msg): Text(msg).foregroundStyle(.red).font(.caption).lineLimit(3)
            }
        }
    }
}

/// The server's MCP tools with read badges, folded away until opened.
struct MCPToolsView: View {
    let tools: [MCPClient.Tool]

    var body: some View {
        if !tools.isEmpty {
            let readOnly = tools.filter { PlanGenerator.isReadOnly($0.name) }.count
            DisclosureGroup {
                ForEach(tools, id: \.name) { tool in
                    let ro = PlanGenerator.isReadOnly(tool.name)
                    HStack(spacing: 8) {
                        Text(tool.name).font(.callout.monospaced()).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(ro ? "read" : "not used")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ro ? .green : .secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((ro ? Color.green : Color.secondary).opacity(0.12), in: .capsule)
                    }
                    .help(tool.description.isEmpty ? tool.name : tool.description)
                }
            } label: {
                Text("\(tools.count) tools · \(readOnly) read-only")
            }
        }
    }
}

#if os(macOS)
/// Native combo box: type any value, or pick one from the dropdown.
struct ComboBox: NSViewRepresentable {
    @Binding var text: String
    var items: [String]
    var placeholder: String = ""
    var monospaced = true

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.usesDataSource = false
        box.completes = true
        box.isButtonBordered = false
        box.numberOfVisibleItems = 12
        box.delegate = context.coordinator
        box.target = context.coordinator
        box.action = #selector(Coordinator.changed(_:))
        box.font = monospaced ? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) : .systemFont(ofSize: NSFont.systemFontSize)
        box.alignment = .right
        box.isBordered = false
        box.drawsBackground = false
        box.focusRingType = .none
        box.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return box
    }

    func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if box.stringValue != text { box.stringValue = text }
        box.placeholderString = placeholder
        let current = box.objectValues.compactMap { $0 as? String }
        if current != items {
            box.removeAllItems()
            box.addItems(withObjectValues: items)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: ComboBox
        init(_ parent: ComboBox) { self.parent = parent }

        @objc func changed(_ sender: NSComboBox) { parent.text = sender.stringValue }

        func controlTextDidChange(_ note: Notification) {
            if let box = note.object as? NSComboBox { parent.text = box.stringValue }
        }

        func comboBoxSelectionDidChange(_ note: Notification) {
            guard let box = note.object as? NSComboBox, box.indexOfSelectedItem >= 0,
                  let value = box.itemObjectValue(at: box.indexOfSelectedItem) as? String else { return }
            parent.text = value
        }
    }
}
#else
/// iOS: a text field with a menu of known values.
struct ComboBox: View {
    @Binding var text: String
    var items: [String]
    var placeholder: String = ""
    var monospaced = true

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .font(monospaced ? .body.monospaced() : .body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !items.isEmpty {
                Menu {
                    ForEach(items, id: \.self) { m in Button(m) { text = m } }
                } label: {
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
            }
        }
    }
}

/// iOS: a whole-row model setting that opens a searchable list. Big targets instead of a
/// text field with a tiny menu chevron; typing a name that isn't listed offers "Use …".
struct ModelPickerRow: View {
    let title: String
    @Binding var text: String
    var items: [String]
    var placeholder: String
    /// When set, an option that clears the value (e.g. "Same as main model").
    var emptyLabel: String? = nil
    var loading = false
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        NavigationLink {
            ModelPickerList(title: title, text: $text, items: items, placeholder: placeholder,
                            emptyLabel: emptyLabel, loading: loading, onRefresh: onRefresh)
        } label: {
            LabeledContent(title) {
                Text(text.isEmpty ? (emptyLabel ?? placeholder) : text)
                    .font(text.isEmpty ? .callout : .callout.monospaced())
                    .foregroundStyle(text.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct ModelPickerList: View {
    let title: String
    @Binding var text: String
    let items: [String]
    let placeholder: String
    let emptyLabel: String?
    let loading: Bool
    let onRefresh: (() -> Void)?
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var typed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filtered: [String] {
        typed.isEmpty ? items : items.filter { $0.localizedCaseInsensitiveContains(typed) }
    }

    var body: some View {
        List {
            if let emptyLabel, typed.isEmpty {
                Section { row(emptyLabel, value: "", monospaced: false) }
            }
            if !typed.isEmpty && !items.contains(typed) {
                Section("Not in the list") {
                    Button { pick(typed) } label: {
                        Label("Use “\(typed)”", systemImage: "keyboard")
                    }
                }
            }
            if !text.isEmpty && !items.contains(text) && typed.isEmpty {
                Section("Current") { row(text, value: text) }
            }
            if !filtered.isEmpty {
                Section(items.count > 1 ? "\(items.count) models" : "Models") {
                    ForEach(filtered, id: \.self) { row($0, value: $0) }
                }
            } else if items.isEmpty {
                Section {
                    Text(loading ? "Loading models…" : "No list from this provider yet. Type a model name in the search field\(onRefresh == nil ? "" : ", or refresh the list").")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search or type a model name")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { if !typed.isEmpty { pick(filtered.count == 1 ? filtered[0] : typed) } }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onRefresh {
                ToolbarItem(placement: .primaryAction) {
                    if loading {
                        ProgressView()
                    } else {
                        Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                    }
                }
            }
        }
    }

    private func row(_ label: String, value: String, monospaced: Bool = true) -> some View {
        Button { pick(value) } label: {
            HStack {
                Text(label)
                    .font(monospaced ? .body.monospaced() : .body)
                    .foregroundStyle(.primary)
                Spacer()
                if text == value { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold) }
            }
            .contentShape(.rect)
        }
        .tint(.primary)
    }

    private func pick(_ value: String) {
        text = value
        dismiss()
    }
}
#endif


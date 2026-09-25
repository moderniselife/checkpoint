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
    var status: StatusDot.State = .none

    var body: some View {
        HStack(spacing: 8) {
            SettingsIconTile(icon: icon, tint: tint)
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
                    SettingsIconTile(icon: section.icon, tint: section.tint, size: 40)
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

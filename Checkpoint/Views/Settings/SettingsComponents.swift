import SwiftUI

/// Big header: glowing gradient tile echoing the app logo, title, subtitle.
struct SettingsHeader: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
            }
            .shadow(color: tint.opacity(0.5), radius: 20, y: 6)
            Text(title)
                .font(.title.weight(.bold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// Card container in the app's Liquid Glass style (cf. PlanView header,
/// TicketInputBar pills): glass material, generous radius, no flat fills.
struct SettingsCard<Content: View, Footer: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    init(title: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
            }
            content
            footer
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension SettingsCard where Footer == EmptyView {
    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self.footer = EmptyView()
    }
}

/// One row inside a SettingsCard. Dividers are drawn between rows by the parent.
struct SettingsRow<Content: View>: View {
    var label: String
    var systemImage: String? = nil
    var tint: Color = .secondary
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 22)
            }
            Text(label)
                .frame(width: 130, alignment: .leading)
                .foregroundStyle(.primary)
            content
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct CardDivider: View {
    var body: some View {
        Divider().padding(.leading, 50)
    }
}

/// Small connection dot for the sidebar: green = ready, orange = needs setup.
struct StatusDot: View {
    enum State { case ok, warn, none }
    var state: State

    var body: some View {
        switch state {
        case .ok:
            Circle().fill(.green).frame(width: 8, height: 8)
        case .warn:
            Circle().fill(.orange).frame(width: 8, height: 8)
        case .none:
            EmptyView()
        }
    }
}

enum ConnectionTestState: Equatable {
    case idle, testing, ok(String, Int), failed(String)
}

/// Lists MCP tools discovered via tools/list, with read-only badges.
/// This is the "reads the mcp tools" mapping view — any server works.
struct MCPToolsView: View {
    let tools: [MCPClient.Tool]
    var maxShown: Int = 12

    var body: some View {
        if tools.isEmpty {
            Text("Test the connection to list this server's MCP tools here.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 10)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                let readOnly = tools.filter { PlanGenerator.isReadOnly($0.name) }
                HStack {
                    Label("\(tools.count) tools", systemImage: "wrench.and.screwdriver")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(readOnly.count) read-only")
                        .font(.caption).foregroundStyle(.green)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                CardDivider()
                ForEach(tools.prefix(maxShown), id: \.name) { tool in
                    HStack(spacing: 8) {
                        Text(tool.name)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if PlanGenerator.isReadOnly(tool.name) {
                            Text("READ")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.green.opacity(0.12), in: .capsule)
                        } else {
                            Text("WRITE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.orange.opacity(0.12), in: .capsule)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 5)
                    .help(tool.description.isEmpty ? tool.name : tool.description)
                }
                if tools.count > maxShown {
                    Text("+\(tools.count - maxShown) more — Checkpoint only calls read-only tools for Jira/custom servers.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
        }
    }
}

/// Sidebar row with macOS-style icon tile.
struct SettingsSidebarRow: View {
    let section: SettingsSection
    let selected: Bool
    var status: StatusDot.State = .none

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(section.tint.gradient)
                    .frame(width: 28, height: 28)
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text(section.title)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 4)
            StatusDot(state: status)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.gradient : Color.clear.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(selected ? .white : .primary)
    }
}

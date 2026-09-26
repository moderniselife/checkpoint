import Foundation

/// A rule-based virtual folder (IDEA-101): membership is computed live from
/// ticket metadata instead of filed by hand. Convertible to a static folder.
nonisolated struct SmartFolder: Codable, Sendable, Identifiable, Hashable {
    nonisolated enum Kind: String, Codable, Sendable, CaseIterable {
        case label, component, fixVersion, epic

        var label: String {
            switch self {
            case .label: "Label"
            case .component: "Component"
            case .fixVersion: "Fix version"
            case .epic: "Epic / parent"
            }
        }

        var icon: String {
            switch self {
            case .label: "tag"
            case .component: "square.stack.3d.up"
            case .fixVersion: "flag"
            case .epic: "list.bullet.indent"
            }
        }

        var valuePrompt: String {
            switch self {
            case .label: "e.g. checkout"
            case .component: "e.g. payments"
            case .fixVersion: "e.g. Sprint 20"
            case .epic: "e.g. PROJ-100"
            }
        }
    }

    var id = UUID()
    var name: String
    var kind: Kind
    var value: String

    /// Live membership: non-archived plans whose ticket matches the rule.
    /// Epic rules also include the epic's own plan.
    func matches(_ saved: SavedPlan) -> Bool {
        guard !saved.archived else { return false }
        let t = saved.plan.ticket
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !v.isEmpty else { return false }
        switch kind {
        case .label:
            return t.labels.contains { $0.lowercased() == v }
        case .component:
            return t.components.contains { $0.lowercased() == v }
        case .fixVersion:
            return t.fixVersions.contains { $0.lowercased() == v }
        case .epic:
            return t.key.lowercased() == v || t.parentKey?.lowercased() == v
        }
    }
}

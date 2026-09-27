import Foundation

/// Something Checkpoint should know on every future plan: a correction to a wrong assumption
/// ("there's no assurance performer role, log in as a Company Admin") or a standing fact about
/// the product. Scoped to one project's tickets (the key prefix, like "PROJ") or to all of them.
nonisolated struct PlanMemory: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var text: String
    /// Project key prefix ("PROJ"); empty means every ticket.
    var scope: String = ""
    var enabled = true
    var createdAt: Date = .now
    /// Where it came from, e.g. "PROJ-12 · Evidence type is read-only in Perform".
    var source: String?
    /// Saved by Checkpoint itself while researching, rather than by you.
    var learned = false

    init(text: String, scope: String = "", source: String? = nil, learned: Bool = false) {
        self.text = text
        self.scope = scope
        self.source = source
        self.learned = learned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        source = try c.decodeIfPresent(String.self, forKey: .source)
        learned = try c.decodeIfPresent(Bool.self, forKey: .learned) ?? false
    }

    /// Whether this memory is told to the planner for a ticket.
    func applies(to ticketKey: String) -> Bool {
        enabled && (scope.isEmpty || Self.project(of: ticketKey) == scope.uppercased())
    }

    var scopeLabel: String { scope.isEmpty ? "All tickets" : "\(scope.uppercased()) tickets" }

    /// "PROJ" from "PROJ-123"; nil for ids without a project prefix.
    static func project(of ticketKey: String) -> String? {
        guard let dash = ticketKey.firstIndex(of: "-") else { return nil }
        let prefix = ticketKey[..<dash].uppercased()
        return prefix.isEmpty || !prefix.allSatisfy({ $0.isLetter || $0.isNumber }) ? nil : prefix
    }
}

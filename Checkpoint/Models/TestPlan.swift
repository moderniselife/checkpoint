import Foundation

nonisolated struct TestPlan: Codable, Sendable, Hashable {
    struct Ticket: Codable, Sendable, Hashable {
        var key: String
        var title: String
        var type: String
        var status: String
        var url: String
    }

    struct Source: Codable, Sendable, Hashable, Identifiable {
        var key: String
        var title: String
        var relation: String
        var url: String
        var id: String { key + relation }
    }

    struct Criterion: Codable, Sendable, Hashable, Identifiable {
        var id: String
        var text: String
        /// Ticket key the criterion came from, or "derived" when inferred.
        var source: String
    }

    enum Priority: String, Codable, Sendable, Hashable, CaseIterable {
        case high, medium, low
    }

    struct Task: Codable, Sendable, Hashable, Identifiable {
        var id: String
        var title: String
        var ticketKey: String
        var area: String
        var priority: Priority
        var steps: [String]
        var expected: String
        var covers: [String]
    }

    var ticket: Ticket
    var summary: String
    var preconditions: [String]
    var acceptanceCriteria: [Criterion]
    var tasks: [Task]
    var edgeCases: [String]
    var openQuestions: [String]
    var sources: [Source]
}

nonisolated extension TestPlan {
    /// JSON schema handed to `output_config.format` so the final answer always decodes.
    static let jsonSchema: JSONValue = {
        func obj(_ props: [String: JSONValue]) -> JSONValue {
            .object([
                "type": "object",
                "properties": .object(props),
                "required": .array(props.keys.sorted().map { .string($0) }),
                "additionalProperties": false,
            ])
        }
        func arr(_ items: JSONValue) -> JSONValue { ["type": "array", "items": items] }
        let str: JSONValue = ["type": "string"]

        return obj([
            "ticket": obj(["key": str, "title": str, "type": str, "status": str, "url": str]),
            "summary": str,
            "preconditions": arr(str),
            "acceptanceCriteria": arr(obj(["id": str, "text": str, "source": str])),
            "tasks": arr(obj([
                "id": str, "title": str, "ticketKey": str, "area": str,
                "priority": ["type": "string", "enum": ["high", "medium", "low"]],
                "steps": arr(str), "expected": str, "covers": arr(str),
            ])),
            "edgeCases": arr(str),
            "openQuestions": arr(str),
            "sources": arr(obj(["key": str, "title": str, "relation": str, "url": str])),
        ])
    }()

    func markdown(done: Set<String>, met: Set<String> = []) -> String {
        var md = "# \(ticket.key) — \(ticket.title)\n\n\(ticket.url)\n\n\(summary)\n"
        if !preconditions.isEmpty {
            md += "\n## Before you start\n" + preconditions.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if !acceptanceCriteria.isEmpty {
            md += "\n## Acceptance criteria\n"
                + acceptanceCriteria.map { "- [\(met.contains($0.id) ? "x" : " ")] **\($0.id)** \($0.text) _(\($0.source))_" }
                    .joined(separator: "\n") + "\n"
        }
        md += "\n## Test tasks\n"
        for t in tasks {
            md += "- [\(done.contains(t.id) ? "x" : " ")] **\(t.title)** (\(t.ticketKey), \(t.priority.rawValue))\n"
            for (i, s) in t.steps.enumerated() { md += "    \(i + 1). \(s)\n" }
            md += "    - Expected: \(t.expected)\n"
        }
        if !edgeCases.isEmpty {
            md += "\n## Edge cases\n" + edgeCases.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if !openQuestions.isEmpty {
            md += "\n## Open questions\n" + openQuestions.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        return md
    }
}

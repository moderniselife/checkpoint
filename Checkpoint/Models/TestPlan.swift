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

    /// An end-to-end journey that exercises the change in context (optional feature).
    struct Scenario: Codable, Sendable, Hashable, Identifiable {
        var id: String
        var title: String
        /// Who's doing it, e.g. "Returning customer with a saved card".
        var role: String
        var goal: String
        var steps: [String]
        var expected: String
        var relatedTickets: [String]
        /// What it's grounded in: "tickets", "codebase" or "tickets+codebase".
        var basis: String
    }

    var ticket: Ticket
    var summary: String
    var preconditions: [String]
    var acceptanceCriteria: [Criterion]
    var tasks: [Task]
    var edgeCases: [String]
    var openQuestions: [String]
    var sources: [Source]
    /// Empty unless scenario generation was on for this run.
    var scenarios: [Scenario] = []
}

nonisolated extension TestPlan {
    // Plans saved before scenarios existed have no "scenarios" key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ticket = try c.decode(Ticket.self, forKey: .ticket)
        summary = try c.decode(String.self, forKey: .summary)
        preconditions = try c.decode([String].self, forKey: .preconditions)
        acceptanceCriteria = try c.decode([Criterion].self, forKey: .acceptanceCriteria)
        tasks = try c.decode([Task].self, forKey: .tasks)
        edgeCases = try c.decode([String].self, forKey: .edgeCases)
        openQuestions = try c.decode([String].self, forKey: .openQuestions)
        sources = try c.decode([Source].self, forKey: .sources)
        scenarios = try c.decodeIfPresent([Scenario].self, forKey: .scenarios) ?? []
    }
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
            "scenarios": arr(obj([
                "id": str, "title": str, "role": str, "goal": str, "steps": arr(str), "expected": str,
                "relatedTickets": arr(str),
                "basis": ["type": "string", "enum": ["tickets", "codebase", "tickets+codebase"]],
            ])),
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
        if !scenarios.isEmpty {
            md += "\n## Scenarios\n"
            for sc in scenarios {
                md += "- [\(done.contains("scenario:" + sc.id) ? "x" : " ")] **\(sc.title)** — \(sc.role)\n"
                md += "    - Goal: \(sc.goal)\n"
                for (i, s) in sc.steps.enumerated() { md += "    \(i + 1). \(s)\n" }
                md += "    - Expected: \(sc.expected)\n"
                if !sc.relatedTickets.isEmpty { md += "    - Related: \(sc.relatedTickets.joined(separator: ", "))\n" }
            }
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

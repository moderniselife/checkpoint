import Foundation

nonisolated struct TestPlan: Codable, Sendable, Hashable {
    struct Ticket: Codable, Sendable, Hashable {
        var key: String
        var title: String
        var type: String
        var status: String
        var url: String
        /// Ticket metadata for smart folders (IDEA-101). Empty on old plans.
        var labels: [String] = []
        var components: [String] = []
        var fixVersions: [String] = []
        /// Parent/epic key for child issues, if any.
        var parentKey: String? = nil

        enum CodingKeys: String, CodingKey {
            case key, title, type, status, url, labels, components, fixVersions, parentKey
        }

        init(key: String, title: String, type: String, status: String, url: String,
             labels: [String] = [], components: [String] = [], fixVersions: [String] = [], parentKey: String? = nil) {
            self.key = key
            self.title = title
            self.type = type
            self.status = status
            self.url = url
            self.labels = labels
            self.components = components
            self.fixVersions = fixVersions
            self.parentKey = parentKey
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decode(String.self, forKey: .key)
            title = try c.decode(String.self, forKey: .title)
            type = try c.decode(String.self, forKey: .type)
            status = try c.decode(String.self, forKey: .status)
            url = try c.decode(String.self, forKey: .url)
            labels = try c.decodeIfPresent([String].self, forKey: .labels) ?? []
            components = try c.decodeIfPresent([String].self, forKey: .components) ?? []
            fixVersions = try c.decodeIfPresent([String].self, forKey: .fixVersions) ?? []
            parentKey = try c.decodeIfPresent(String.self, forKey: .parentKey)
        }
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
        /// Concrete sample inputs (IDEA-003). Empty on old plans.
        var testData: [String] = []
        /// Rough manual minutes (IDEA-012). Nil hides the estimate.
        var estimateMin: Int? = nil
        /// Where this task came from (IDEA-011). Empty on old plans.
        var sources: [TaskSource] = []

        enum CodingKeys: String, CodingKey {
            case id, title, ticketKey, area, priority, steps, expected, covers, testData, estimateMin, sources
        }

        init(id: String, title: String, ticketKey: String, area: String, priority: Priority,
             steps: [String], expected: String, covers: [String],
             testData: [String] = [], estimateMin: Int? = nil, sources: [TaskSource] = []) {
            self.id = id
            self.title = title
            self.ticketKey = ticketKey
            self.area = area
            self.priority = priority
            self.steps = steps
            self.expected = expected
            self.covers = covers
            self.testData = testData
            self.estimateMin = estimateMin
            self.sources = sources
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            ticketKey = try c.decode(String.self, forKey: .ticketKey)
            area = try c.decode(String.self, forKey: .area)
            priority = try c.decode(Priority.self, forKey: .priority)
            steps = try c.decode([String].self, forKey: .steps)
            expected = try c.decode(String.self, forKey: .expected)
            covers = try c.decode([String].self, forKey: .covers)
            testData = try c.decodeIfPresent([String].self, forKey: .testData) ?? []
            estimateMin = try c.decodeIfPresent(Int.self, forKey: .estimateMin)
            sources = try c.decodeIfPresent([TaskSource].self, forKey: .sources) ?? []
        }

        /// P0/P1/P2 badge derived from priority (IDEA-002).
        var risk: String {
            switch priority {
            case .high: "P0"
            case .medium: "P1"
            case .low: "P2"
            }
        }

        /// Smoke-subset rank: high priority first (IDEA-001).
        var smokeRank: Int {
            switch priority {
            case .high: 0
            case .medium: 1
            case .low: 2
            }
        }
    }

    /// A pointer back to what caused a task (IDEA-011).
    struct TaskSource: Codable, Sendable, Hashable {
        /// Ticket key, or "derived".
        var ticketKey: String
        /// "ac", "comment", "page", "code", "spec".
        var kind: String
        /// AC id, comment hint, page title — whatever identifies it.
        var ref: String
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

    /// 5-minute smoke subset (IDEA-001): highest-risk tasks first, plan order kept.
    var smokeSubset: [Task] {
        let ranked = tasks.enumerated().sorted {
            $0.element.smokeRank != $1.element.smokeRank
                ? $0.element.smokeRank < $1.element.smokeRank : $0.offset < $1.offset
        }
        let ids = Set(ranked.prefix(6).map(\.element.id))
        return tasks.filter { ids.contains($0.id) }
    }

    /// Rough total minutes, if any task carries an estimate (IDEA-012).
    var estimatedMinutes: Int? {
        let vals = tasks.compactMap(\.estimateMin)
        return vals.isEmpty ? nil : vals.reduce(0, +)
    }
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
            "ticket": obj(["key": str, "title": str, "type": str, "status": str, "url": str,
                           "labels": arr(str), "components": arr(str), "fixVersions": arr(str),
                           "parentKey": ["type": ["string", "null"]]]),
            "summary": str,
            "preconditions": arr(str),
            "acceptanceCriteria": arr(obj(["id": str, "text": str, "source": str])),
            "tasks": arr(obj([
                "id": str, "title": str, "ticketKey": str, "area": str,
                "priority": ["type": "string", "enum": ["high", "medium", "low"]],
                "steps": arr(str), "expected": str, "covers": arr(str),
                "testData": arr(str),
                "estimateMin": ["type": ["integer", "null"]],
                "sources": arr(obj(["ticketKey": str, "kind": str, "ref": str])),
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

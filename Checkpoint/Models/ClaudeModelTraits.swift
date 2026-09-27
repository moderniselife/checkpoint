import Foundation

/// How Checkpoint asks a Claude model to think.
nonisolated enum ThinkingMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Per model: adaptive where supported, otherwise a fixed budget, otherwise none.
    case auto
    case adaptive
    /// A fixed thinking budget sized by effort.
    case budget
    case off

    var id: Self { self }

    var label: String {
        switch self {
        case .auto: "Automatic"
        case .adaptive: "Adaptive"
        case .budget: "Fixed budget"
        case .off: "Off"
        }
    }
}

/// What a Claude model accepts, so requests don't fail on options it doesn't support.
/// Starts from a table of known models; anything the API rejects is learned and remembered
/// per model, so new or odd models sort themselves out after one refusal.
nonisolated struct ClaudeModelTraits: Sendable, Equatable {
    enum Thinking: Sendable, Equatable {
        case adaptive
        case budget(Int)
        case off
    }

    var thinking: Thinking
    /// `output_config.effort`.
    var effort: Bool
    /// `output_config.format` (schema-enforced plans).
    var schema: Bool

    /// What to send for this model, given the setting and effort.
    static func resolve(model: String, mode: ThinkingMode, effort: String) -> ClaudeModelTraits {
        let known = knownSupport(model)
        let learned = Learned.quirks(for: model)
        let canAdaptive = known.adaptive && !learned.contains(.noAdaptive)
        let canThink = known.thinking && !learned.contains(.noThinking)
        let budget = Thinking.budget(budgetTokens(for: effort))
        let thinking: Thinking
        switch mode {
        case .off: thinking = .off
        case .budget: thinking = canThink ? budget : .off
        case .adaptive: thinking = canAdaptive ? .adaptive : (canThink ? budget : .off)
        case .auto: thinking = canAdaptive ? .adaptive : (canThink ? budget : .off)
        }
        return ClaudeModelTraits(thinking: thinking,
                                 effort: known.effort && !learned.contains(.noEffort),
                                 schema: known.schema && !learned.contains(.noSchema))
    }

    /// One line for Settings: what Automatic does for this model.
    static func summary(model: String, mode: ThinkingMode, effort: String) -> String {
        let t = resolve(model: model, mode: mode, effort: effort)
        let name = model.isEmpty ? "This model" : model
        var parts: [String]
        switch t.thinking {
        case .adaptive: parts = ["\(name) thinks adaptively"]
        case .budget(let n):
            parts = [mode == .budget ? "\(name) thinks with a fixed budget of \(n.formatted()) tokens"
                     : "\(name) doesn't support adaptive thinking, so it gets a fixed budget of \(n.formatted()) tokens"]
        case .off: parts = [mode == .off ? "Thinking is off" : "\(name) doesn't support extended thinking, so it answers without it"]
        }
        if !t.effort { parts.append("effort isn't sent") }
        if !t.schema { parts.append("plans are asked for as JSON in the instructions") }
        return parts.joined(separator: "; ") + "."
    }

    /// Thinking budget for the fixed-budget mode (must stay under max_tokens).
    static func budgetTokens(for effort: String) -> Int {
        switch effort {
        case "low": 4_096
        case "medium": 8_192
        case "xhigh": 24_000
        default: 16_000
        }
    }

    /// Known support by model family. Unknown models are assumed current.
    static func knownSupport(_ model: String) -> (adaptive: Bool, thinking: Bool, effort: Bool, schema: Bool) {
        let m = model.lowercased()
        // Claude 3 and 3.5: no extended thinking, effort or structured outputs.
        if m.contains("claude-3-5") || m.contains("claude-3-opus") || m.contains("claude-3-sonnet") || m.contains("claude-3-haiku") {
            return (false, false, false, false)
        }
        // Claude 3.7 Sonnet: budget thinking only.
        if m.contains("claude-3-7") { return (false, true, false, false) }
        // Claude 4 family before adaptive thinking: budget thinking; effort only on Opus 4.5.
        let claude4 = ["claude-haiku-4", "claude-sonnet-4", "claude-opus-4-0", "claude-opus-4-1", "claude-opus-4-5",
                       "claude-opus-4-2", "claude-opus-4-3", "claude-opus-4-4", "claude-4-"]
        if claude4.contains(where: { m.hasPrefix($0) }) || m == "claude-opus-4" {
            return (false, true, m.hasPrefix("claude-opus-4-5"), true)
        }
        return (true, true, true, true)
    }

    // MARK: Learning from refusals

    enum Quirk: String, Sendable { case noAdaptive, noThinking, noEffort, noSchema }

    /// Works out which option a 400 refused, records it for the model, and returns the
    /// adjusted traits plus a line for the feed; nil when the error isn't about options.
    func adjusted(after error: ClaudeClient.ClaudeError, model: String, effort: String) -> (ClaudeModelTraits, String)? {
        guard case .http(400, let body) = error else { return nil }
        let b = body.lowercased()
        var next = self
        if b.contains("adaptive"), thinking == .adaptive {
            Learned.add(.noAdaptive, for: model)
            next.thinking = .budget(Self.budgetTokens(for: effort))
            return (next, "\(model) doesn't support adaptive thinking; using a fixed thinking budget instead.")
        }
        if b.contains("thinking"), thinking != .off,
           ["not supported", "does not support", "unsupported", "not available", "not enabled", "extra inputs"].contains(where: b.contains) {
            Learned.add(.noThinking, for: model)
            next.thinking = .off
            return (next, "\(model) doesn't support extended thinking; carrying on without it.")
        }
        if b.contains("effort"), self.effort {
            Learned.add(.noEffort, for: model)
            next.effort = false
            return (next, "\(model) doesn't take an effort setting; leaving it out.")
        }
        if schema, b.contains("output_config") || b.contains("json_schema") || b.contains("structured output") || b.contains("output format") {
            Learned.add(.noSchema, for: model)
            next.schema = false
            return (next, "\(model) can't lock the plan format; asking for JSON in the instructions instead.")
        }
        return nil
    }

    /// Per-model quirks learned from the API, kept in preferences.
    enum Learned {
        private static let key = "claudeModelQuirks"

        static func quirks(for model: String) -> Set<Quirk> {
            let all = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
            return Set((all[model] ?? []).compactMap(Quirk.init(rawValue:)))
        }

        static func add(_ quirk: Quirk, for model: String) {
            var all = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
            var list = Set(all[model] ?? [])
            list.insert(quirk.rawValue)
            all[model] = list.sorted()
            UserDefaults.standard.set(all, forKey: key)
        }

        /// Settings → "Forget learned model quirks".
        static func reset() { UserDefaults.standard.removeObject(forKey: key) }

        static var isEmpty: Bool { (UserDefaults.standard.dictionary(forKey: key) ?? [:]).isEmpty }
    }
}

import Foundation

/// Token usage + rough cost for one plan run (IDEA-080).
nonisolated struct LLMUsage: Codable, Sendable, Hashable {
    var input: Int = 0
    var output: Int = 0

    var isEmpty: Bool { input == 0 && output == 0 }

    mutating func add(input: Int, output: Int) {
        self.input += max(input, 0)
        self.output += max(output, 0)
    }

    mutating func add(_ other: LLMUsage) {
        add(input: other.input, output: other.output)
    }

    /// Approximate USD. Prices move — table is a snapshot, unknown models return nil.
    func cost(provider: LLMProvider, model: String) -> Double? {
        let m = model.lowercased()
        // (dollars per 1M input, per 1M output)
        let rate: (Double, Double)?
        switch provider {
        case .anthropic, .anthropicCompatible:
            if m.contains("opus") || m.contains("fable") { rate = (15, 75) }
            else if m.contains("sonnet") { rate = (3, 15) }
            else if m.contains("haiku") { rate = (1, 5) }
            else { rate = nil }
        case .openai:
            if m.contains("gpt-5") { rate = (2.5, 10) }
            else { rate = nil }
        case .gemini:
            if m.contains("2.5") { rate = (1.25, 10) }
            else { rate = nil }
        case .xai:
            if m.contains("grok") { rate = (3, 15) }
            else { rate = nil }
        case .openrouter, .openAICompatible:
            rate = nil // varies by model / is local
        }
        guard let (ri, ro) = rate else { return nil }
        return Double(input) / 1_000_000 * ri + Double(output) / 1_000_000 * ro
    }

    /// "12.4k in · 8.1k out" / with cost "· ≈$0.42".
    func display(provider: LLMProvider, model: String) -> String {
        func k(_ n: Int) -> String {
            n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
        }
        var s = "\(k(input)) in · \(k(output)) out"
        if let c = cost(provider: provider, model: model) {
            s += String(format: " · ≈$%.2f", c)
        }
        return s
    }
}

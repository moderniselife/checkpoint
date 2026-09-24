import Foundation

/// Which AI service writes the plan. Two wire formats cover all of them:
/// Anthropic Messages (Claude and Anthropic-compatible servers) and OpenAI
/// Chat Completions (OpenAI, Gemini, Grok, OpenRouter and local servers).
nonisolated enum LLMProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case anthropic
    case openai
    case gemini
    case xai
    case openrouter
    case openAICompatible
    case anthropicCompatible

    enum Style: Sendable { case anthropic, openAIChat }

    var id: Self { self }

    var label: String {
        switch self {
        case .anthropic: "Anthropic (Claude)"
        case .openai: "OpenAI"
        case .gemini: "Google Gemini"
        case .xai: "xAI Grok"
        case .openrouter: "OpenRouter"
        case .openAICompatible: "Local / OpenAI-compatible"
        case .anthropicCompatible: "Local / Anthropic-compatible"
        }
    }

    var shortLabel: String {
        switch self {
        case .anthropic: "Claude"
        case .openai: "OpenAI"
        case .gemini: "Gemini"
        case .xai: "Grok"
        case .openrouter: "OpenRouter"
        case .openAICompatible, .anthropicCompatible: "Local model"
        }
    }

    var style: Style {
        switch self {
        case .anthropic, .anthropicCompatible: .anthropic
        default: .openAIChat
        }
    }

    /// Base URL the API paths hang off (`/v1/messages` for Anthropic style, `/chat/completions` otherwise).
    var defaultBaseURL: String {
        switch self {
        case .anthropic: "https://api.anthropic.com"
        case .openai: "https://api.openai.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .xai: "https://api.x.ai/v1"
        case .openrouter: "https://openrouter.ai/api/v1"
        case .openAICompatible: "http://localhost:11434/v1"
        case .anthropicCompatible: "http://localhost:4000"
        }
    }

    /// Local servers usually don't need a key; hosted ones always do.
    var requiresKey: Bool { self != .openAICompatible && self != .anthropicCompatible }

    /// Hosted providers use a fixed endpoint; local ones let you set it.
    var hasEditableBaseURL: Bool { self == .openAICompatible || self == .anthropicCompatible }

    /// A starting model; "Fetch models" in Settings lists what the provider actually offers.
    var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5"
        case .openai: "gpt-5"
        case .gemini: "gemini-2.5-pro"
        case .xai: "grok-4"
        case .openrouter: "anthropic/claude-opus-4.5"
        case .openAICompatible: "llama3.1"
        case .anthropicCompatible: "claude-opus-5"
        }
    }

    var keyPrompt: String {
        switch self {
        case .anthropic, .anthropicCompatible: "sk-ant-…"
        case .openai: "sk-…"
        case .gemini: "AIza…"
        case .xai: "xai-…"
        case .openrouter: "sk-or-…"
        case .openAICompatible: "optional"
        }
    }

    var keyURL: URL? {
        switch self {
        case .anthropic: URL(string: "https://platform.claude.com/settings/keys")
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .xai: URL(string: "https://console.x.ai")
        case .openrouter: URL(string: "https://openrouter.ai/keys")
        case .openAICompatible, .anthropicCompatible: nil
        }
    }

    /// Keychain account for this provider's key (Anthropic keeps its original account name).
    var keychainAccount: String { self == .anthropic ? "anthropic" : "llm-key-\(rawValue)" }
}

/// Everything a plan run needs to talk to the chosen model.
nonisolated struct LLMConfig: Sendable {
    var provider: LLMProvider
    var apiKey: String
    var baseURL: String
    var model: String
    /// low / medium / high / xhigh — mapped per provider where supported.
    var effort: String
}

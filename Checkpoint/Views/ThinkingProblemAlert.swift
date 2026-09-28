import SwiftUI

/// When a run fails because the model won't think the way it was asked, offer to change the
/// Thinking setting and carry on from where it stopped, rather than leaving a bare error.
struct ThinkingProblemAlert: ViewModifier {
    @Environment(PlanStore.self) private var store
    @Environment(AppSettings.self) private var settings

    func body(content: Content) -> some View {
        let problem = store.thinkingProblem
        content.alert(
            "\(settings.llmConfig.model.isEmpty ? "This model" : settings.llmConfig.model) can't think that way",
            isPresented: Binding(get: { problem != nil }, set: { if !$0 { store.thinkingProblem = nil } }),
            presenting: problem
        ) { p in
            if settings.provider.style == .anthropic && settings.thinkingMode != .budget {
                Button("Use a Fixed Budget and Resume") { fix(p, .budget) }
            }
            Button("Turn Off Thinking and Resume") { fix(p, .off) }
            Button("Not Now", role: .cancel) { store.thinkingProblem = nil }
        } message: { p in
            Text("\(p.key) stopped: \(p.message)\n\nChange Thinking in \(Platform.settingsName) → AI Provider and resume it from where it stopped?")
        }
    }

    private func fix(_ p: ThinkingProblem, _ mode: ThinkingMode) {
        settings.thinkingMode = mode
        store.thinkingProblem = nil
        store.resume(p.draftID, settings: settings)
    }
}

extension View {
    func thinkingProblemAlert() -> some View { modifier(ThinkingProblemAlert()) }
}

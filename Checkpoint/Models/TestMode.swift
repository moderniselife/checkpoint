import Foundation

/// Who the plan is written for.
nonisolated enum TestMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Developer verifying their own change: may reference code, branches, local setup.
    case dev
    /// QA tester on the hosted app: black-box, UI-only, no code or local setup.
    case qa

    var id: Self { self }
    var label: String { self == .dev ? "Dev" : "QA" }
    var icon: String { self == .dev ? "hammer" : "checkmark.shield" }
    var help: String {
        self == .dev
            ? "Dev mode — plans can reference code, branches and local setup"
            : "QA mode — black-box plans for testing the hosted app"
    }
}

import Foundation

/// Optional end-to-end scenario generation.
nonisolated enum ScenarioMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Just the test plan.
    case off
    /// Scenarios built from the ticket plus related tickets (same epic, components, labels, area).
    case tickets
    /// Also reads a local codebase (read-only) to trace real flows, screens and permissions.
    case ticketsAndCode

    var id: Self { self }

    /// Modes this platform can run: reading a local codebase is Mac-only.
    static var available: [ScenarioMode] {
        #if os(macOS)
        allCases
        #else
        [.off, .tickets]
        #endif
    }

    var label: String {
        switch self {
        case .off: "No scenarios"
        case .tickets: "Scenarios from related tickets"
        case .ticketsAndCode: "Scenarios from tickets + codebase"
        }
    }

    var shortLabel: String {
        switch self {
        case .off: "Off"
        case .tickets: "Tickets"
        case .ticketsAndCode: "Tickets + code"
        }
    }
}

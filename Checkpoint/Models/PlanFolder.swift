import SwiftUI

/// A folder in the plan sidebar. Folders nest to any depth via `parentID`.
nonisolated struct PlanFolder: Codable, Sendable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var color: FolderColor = .indigo
    var parentID: UUID?
    var createdAt: Date = .now
}

nonisolated enum FolderColor: String, Codable, Sendable, CaseIterable, Identifiable {
    case indigo, blue, teal, mint, green, yellow, orange, red, pink, purple, gray
    var id: Self { self }

    var color: Color {
        switch self {
        case .indigo: .indigo
        case .blue: .blue
        case .teal: .teal
        case .mint: .mint
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        case .purple: .purple
        case .gray: .gray
        }
    }
}

import Foundation

/// Where plans sync to. Keys and sign-ins never sync — they stay in each device's Keychain.
nonisolated enum SyncMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case off
    /// A folder the user picks — iCloud Drive, Dropbox, a network share. Free, works in any build.
    case folder
    /// CloudKit private database. Needs an App Store / signed build with an iCloud container.
    case iCloud

    var id: Self { self }

    var label: String {
        switch self {
        case .off: "Off"
        case .folder: "Sync folder"
        case .iCloud: "iCloud"
        }
    }
}

/// What changed locally since the last save, handed to the active sync backend.
nonisolated struct StoreChanges: Sendable {
    var plans: [SavedPlan] = []
    var deletedPlans: [String] = []
    var folders: [PlanFolder] = []
    var deletedFolders: [UUID] = []
    var smartFolders: [SmartFolder] = []
    var deletedSmartFolders: [UUID] = []

    var isEmpty: Bool {
        plans.isEmpty && deletedPlans.isEmpty && folders.isEmpty && deletedFolders.isEmpty
            && smartFolders.isEmpty && deletedSmartFolders.isEmpty
    }
}

/// Everything local, for a backend's first full pass.
nonisolated struct StoreSnapshot: Sendable {
    var plans: [SavedPlan]
    var folders: [PlanFolder]
    var smartFolders: [SmartFolder]
}

/// Names for records and files. Plan ids contain ":" (bad in Finder and some servers).
nonisolated enum SyncNames {
    static func file(forPlan id: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.")
        return (id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id) + ".json"
    }

    static func plan(fromFile name: String) -> String? {
        guard name.hasSuffix(".json") else { return nil }
        return String(name.dropLast(5)).removingPercentEncoding
    }
}

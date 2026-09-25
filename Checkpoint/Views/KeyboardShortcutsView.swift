import SwiftUI

/// Help → Keyboard Shortcuts (⌘/).
struct KeyboardShortcutsView: View {
    static let windowID = "shortcuts"

    private struct Group: Identifiable {
        let title: String
        let items: [(String, String)]
        var id: String { title }
    }

    private let groups: [Group] = [
        Group(title: "Anywhere", items: [
            ("⌘L", "Jump to the ticket field"),
            ("⌘↩", "Analyze"),
            ("⌘⇧M", "Switch Dev / QA"),
            ("⌘,", "Settings"),
            ("⌘/", "This list"),
        ]),
        Group(title: "In a plan", items: [
            ("⌘I", "Show or hide ticket details"),
            ("⌘T", "Edit tags"),
            ("⌃Tab  ⌃⇧Tab", "Next / previous ticket tab"),
        ]),
        Group(title: "Task list (click it first)", items: [
            ("J  K  ↓  ↑", "Move between tasks"),
            ("Space", "Pass / untick"),
            ("F", "Fail, with what happened"),
            ("B", "Blocked, with why"),
            ("N", "Add a note"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title).font(.headline)
                    ForEach(group.items, id: \.0) { key, action in
                        HStack {
                            Text(action)
                            Spacer(minLength: 24)
                            Text(key)
                                .font(.callout.monospaced().weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.quaternary, in: .rect(cornerRadius: 6))
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

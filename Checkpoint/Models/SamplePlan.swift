import Foundation

/// A realistic finished plan for the tour and for exploring before you've connected anything.
nonisolated enum SamplePlan {
    static let key = "DEMO-123"

    static func make() -> SavedPlan {
        func t(_ id: String, _ title: String, _ area: String, _ p: TestPlan.Priority, _ steps: [String], _ exp: String,
               _ covers: [String], data: [String] = [], est: Int? = nil) -> TestPlan.Task {
            .init(id: id, title: title, ticketKey: key, area: area, priority: p, steps: steps, expected: exp, covers: covers,
                  testData: data, estimateMin: est, sources: covers.map { .init(ticketKey: key, kind: "ac", ref: $0) })
        }
        let plan = TestPlan(
            ticket: .init(key: key, title: "Sample: let shoppers save a card for next time", type: "Story", status: "In QA",
                          url: "https://example.com/browse/\(key)", labels: ["checkout", "sample"], components: ["Web"],
                          fixVersions: ["2.14"]),
            summary: "A sample plan to explore. Shoppers can tick “Save card” when paying; saved cards are offered at their next checkout, showing only the last four digits, and can be removed from their profile.",
            preconditions: ["Staging, signed in as a shopper with no saved cards", "Test card 4242 4242 4242 4242, any future expiry"],
            acceptanceCriteria: [
                .init(id: "AC1", text: "A “Save card for next time” checkbox appears at the payment step for signed-in shoppers", source: key),
                .init(id: "AC2", text: "At the next checkout the saved card is preselected, showing brand and last four digits only", source: key),
                .init(id: "AC3", text: "Guest checkout never offers to save a card", source: "derived"),
                .init(id: "AC4", text: "Card removal works correctly", source: key),
                .init(id: "AC5", text: "Saved cards are hidden after the shopper changes their password", source: key),
            ],
            tasks: [
                t("T1", "Save a card during checkout", "Payments", .high,
                  ["Add any item to the cart", "Pay with a new card and tick Save card for next time", "Start a second checkout"],
                  "The saved card is preselected, showing “Visa •••• 4242” and nothing more", ["AC1", "AC2"],
                  data: ["4242 4242 4242 4242", "12/29", "CVC 123"], est: 6),
                t("T2", "Guest checkout doesn't offer saving", "Payments", .high,
                  ["Sign out", "Check out as a guest"], "No Save card checkbox; the order completes", ["AC3"], est: 4),
                t("T3", "Remove a saved card", "Profile", .medium,
                  ["Open Profile → Payment methods", "Remove the saved card", "Start a checkout"],
                  "The card is gone and the form is empty", ["AC4"], est: 3),
                t("T4", "Mobile Safari layout", "Mobile", .low,
                  ["Open checkout on an iPhone", "Look at the payment step"], "Checkbox and card label fit without wrapping", ["AC1"], est: 3),
            ],
            edgeCases: ["An expired card is saved, then offered", "Two tabs checking out at the same time"],
            openQuestions: ["Can shoppers set a default when they have several cards?"],
            sources: [.init(key: key, title: "Save card for next time", relation: "this ticket", url: "https://example.com/browse/\(key)")])
        var saved = SavedPlan(plan: plan, mode: .qa, tracker: .jira, createdAt: .now, done: [])
        saved.failed = ["T2": "Guest checkout shows the Save card checkbox"]
        saved.notes = ["T1": "Worked in Safari and Chrome."]
        saved.tags = ["sample"]
        saved.chat = [
            .init(role: .user, text: "What about shoppers with two saved cards?"),
            .init(role: .assistant, text: "Worth a task: with two saved cards, the most recently used one is preselected and the other is one tap away."),
        ]
        return saved
    }
}

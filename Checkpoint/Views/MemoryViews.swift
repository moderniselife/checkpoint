import SwiftUI

// MARK: - Settings → Memories

/// Everything Checkpoint remembers across plans: your corrections and what it learned itself.
struct MemoriesPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlanStore.self) private var store
    @State private var adding = false
    @State private var editing: PlanMemory?
    @State private var query = ""

    private var shown: [PlanMemory] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.memories }
        return store.memories.filter { $0.text.lowercased().contains(q) || $0.scope.lowercased().contains(q) }
    }

    var body: some View {
        @Bindable var settings = settings
        SettingsPane(section: .memories) {
            Section {
                Toggle("Learn while researching", isOn: $settings.learnMemories)
            } footer: {
                Text("Every plan is told the memories for its project and can search the rest. With this on, Checkpoint also saves lasting facts it confirms while researching (up to \(MemoryTools.maxSavesPerRun) a plan), marked Learned.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if store.memories.count > 6 {
                    TextField("Search", text: $query, prompt: Text("Search memories"))
                }
                if shown.isEmpty {
                    Text(store.memories.isEmpty
                         ? "Nothing yet. Use Correct This… on a task, or add one here."
                         : "No memories match.")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { memory in
                    MemoryRow(memory: memory) { editing = memory }
                }
                HStack {
                    Spacer()
                    Button("Add Memory…", systemImage: "plus") { adding = true }
                }
            } header: {
                Text(store.memories.isEmpty ? "Memories" : "Memories · \(store.memories.count)")
            }
        }
        .sheet(isPresented: $adding) {
            MemoryEditor(memory: nil) { text, scope in store.addMemory(text, scope: scope) }
        }
        .sheet(item: $editing) { memory in
            MemoryEditor(memory: memory) { text, scope in
                var m = memory
                m.text = text
                m.scope = scope.uppercased()
                store.updateMemory(m)
            }
        }
    }
}

private struct MemoryRow: View {
    let memory: PlanMemory
    let edit: () -> Void
    @Environment(PlanStore.self) private var store
    @State private var confirmingDelete = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { memory.enabled },
                set: { var m = memory; m.enabled = $0; store.updateMemory(m) }
            ))
            .labelsHidden()
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
            VStack(alignment: .leading, spacing: 4) {
                Text(memory.text)
                    .foregroundStyle(memory.enabled ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(memory.scopeLabel)
                    if memory.learned {
                        Text("Learned")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15), in: .capsule)
                            .foregroundStyle(.purple)
                    }
                    if let source = memory.source { Text(source).lineLimit(1) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Menu {
                Button("Edit…", systemImage: "pencil", action: edit)
                Button(memory.enabled ? "Turn Off" : "Turn On", systemImage: memory.enabled ? "pause.circle" : "play.circle") {
                    var m = memory; m.enabled.toggle(); store.updateMemory(m)
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .contentShape(.rect)
        .onTapGesture(perform: edit)
        .confirmationDialog("Delete this memory?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { store.removeMemory(memory.id) }
        } message: {
            Text("Future plans won't be told it any more.")
        }
    }
}

/// Add or edit one memory.
struct MemoryEditor: View {
    let memory: PlanMemory?
    /// Suggested project, e.g. from the plan you're in.
    var project: String? = nil
    let onSave: (_ text: String, _ scope: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var scope = ""

    var body: some View {
        FormSheet(title: memory == nil ? "Add Memory" : "Edit Memory", confirmTitle: "Save",
                  canConfirm: text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5) {
            onSave(text, scope.trimmingCharacters(in: .whitespaces))
            dismiss()
        } content: {
            Section {
                TextField("Memory", text: $text,
                          prompt: Text("e.g. There's no assurance performer role. Perform assurance tasks as a Company Admin."),
                          axis: .vertical)
                    .lineLimit(3...8)
            } footer: {
                Text("Write it the way you'd tell a new tester. Plans follow it over their own assumptions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                TextField("Project", text: $scope, prompt: Text("e.g. PROJ, or empty for all tickets"))
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    #endif
            } header: {
                Text("Applies to")
            } footer: {
                Text(scope.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "Every ticket, in every project."
                     : "Only \(scope.uppercased())-… tickets.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            text = memory?.text ?? ""
            scope = memory?.scope ?? project ?? ""
        }
    }
}

// MARK: - Correct a task

/// From a task's ⋯ menu: tell Checkpoint what it got wrong, remember it for future plans,
/// and optionally fix this plan straight away.
struct CorrectionSheet: View {
    /// nil: a correction to the plan as a whole (preconditions, roles, environment…).
    let task: TestPlan.Task?
    let saved: SavedPlan
    @Environment(AppSettings.self) private var settings
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var projectOnly = true
    @State private var fixNow = true

    private var project: String? { PlanMemory.project(of: saved.plan.ticket.key) }

    var body: some View {
        FormSheet(title: task == nil ? "Correct This Plan" : "Correct This Task", confirmTitle: "Save",
                  canConfirm: text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5, width: 520) {
            save()
        } content: {
            if let task {
                Section("The task") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title).font(.headline)
                        ForEach(Array(task.steps.prefix(4).enumerated()), id: \.offset) { i, step in
                            Text("\(i + 1). \(step)").font(.callout).foregroundStyle(.secondary)
                        }
                        if task.steps.count > 4 {
                            Text("…").foregroundStyle(.secondary)
                        }
                    }
                    .textSelection(.enabled)
                }
            } else if !saved.plan.preconditions.isEmpty {
                Section("Before you start") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(saved.plan.preconditions, id: \.self) { Text("• \($0)").font(.callout).foregroundStyle(.secondary) }
                    }
                    .textSelection(.enabled)
                }
            }
            Section {
                TextField("Correction", text: $text,
                          prompt: Text("e.g. We don't have an assurance performer role. Log in with a Company Admin role."),
                          axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("What should Checkpoint know instead?")
            }
            Section {
                if let project {
                    Picker("Remember for", selection: $projectOnly) {
                        Text("\(project) tickets").tag(true)
                        Text("All tickets").tag(false)
                    }
                }
                Toggle("Fix this plan now", isOn: $fixNow)
            } footer: {
                Text("Saved in \(Platform.settingsName) → Memories, where you can edit or remove it. Future plans follow it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        store.addMemory(clean, scope: projectOnly ? (project ?? "") : "",
                           source: "\(saved.plan.ticket.key)" + (task.map { " · \($0.title)" } ?? ""))
        if fixNow {
            let target = task.map { "the task “\($0.title)” and anywhere else in the plan it matters" }
                ?? "every part of the plan it affects, preconditions included"
            store.applyChatRevision("Correction from the tester: \(clean)\nApply it to \(target).",
                                    in: saved.id, settings: settings)
        }
        dismiss()
    }
}

// MARK: - Context for one run

/// Extra context for the next analysis only, e.g. "test on the demo tenant; ignore the mobile app".
struct RunContextSheet: View {
    @Binding var context: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        FormSheet(title: "Context for This Run", confirmTitle: "Done", width: 480) {
            context = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            dismiss()
        } content: {
            Section {
                TextField("Context", text: $draft,
                          prompt: Text("e.g. Test as a Company Admin on the demo tenant. Only the web app changed."),
                          axis: .vertical)
                    .lineLimit(4...10)
            } footer: {
                Text("Told to the planner for this ticket only, and kept for its re-runs. For things every plan should know, add a memory instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !context.isEmpty {
                Section {
                    Button("Clear Context", role: .destructive) {
                        context = ""
                        dismiss()
                    }
                }
            }
        }
        .onAppear { draft = context }
    }
}

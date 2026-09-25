import SwiftUI

/// Detail view for a selected folder: breadcrumb, rolled-up metrics, subfolders and plans.
struct FolderOverview: View {
    let folder: PlanFolder
    @Environment(PlanStore.self) private var store
    @State private var showingSuite = false

    var body: some View {
        let all = store.allPlans(under: folder.id)
        let tasksDone = all.reduce(0) { $0 + $1.tasksDone }
        let tasksTotal = all.reduce(0) { $0 + $1.plan.tasks.count }
        let acMet = all.reduce(0) { $0 + $1.criteriaMet }
        let acTotal = all.reduce(0) { $0 + $1.plan.acceptanceCriteria.count }
        let finished = all.filter { !$0.plan.tasks.isEmpty && $0.tasksDone == $0.plan.tasks.count }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        breadcrumb
                        Label {
                            Text(folder.name).font(.largeTitle.weight(.semibold))
                        } icon: {
                            Image(systemName: "folder.fill").foregroundStyle(folder.color.color.gradient)
                        }
                        Text("\(all.count) plan\(all.count == 1 ? "" : "s") · \(finished) fully tested")
                            .foregroundStyle(.secondary)
                        Button("Build regression suite", systemImage: "square.stack.3d.up") {
                            showingSuite = true
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .disabled(all.isEmpty)
                        .help("Merge plans into one deduplicated run (IDEA-015)")
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 16) {
                        MetricRing(value: tasksTotal == 0 ? 0 : Double(tasksDone) / Double(tasksTotal),
                                   label: "tested", text: "\(tasksDone)/\(tasksTotal)")
                        MetricRing(value: acTotal == 0 ? 0 : Double(acMet) / Double(acTotal),
                                   label: "AC met", text: "\(acMet)/\(acTotal)", tint: .teal)
                    }
                }
                .padding(24)
                .glassEffect(.regular.tint(folder.color.color.opacity(0.08)), in: .rect(cornerRadius: 28))

                let subfolders = store.childFolders(of: folder.id)
                if !subfolders.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Folders", systemImage: "folder").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                            ForEach(subfolders) { sub in SubfolderCard(folder: sub) }
                        }
                    }
                }

                let direct = store.plans(in: folder.id)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Plans", systemImage: "checklist").font(.headline)
                    if direct.isEmpty {
                        Text(subfolders.isEmpty
                             ? "Empty — drag plans here, or analyze a ticket while this folder is selected."
                             : "No plans directly in this folder.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(direct) { saved in
                        Button { store.selection = saved.id } label: {
                            SidebarRow(saved: saved)
                                .padding(12)
                                .background(.background.opacity(0.55), in: .rect(cornerRadius: 14))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 92)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .glassScrollIndicator()
        .sheet(isPresented: $showingSuite) {
            SuiteBuilderSheet(folder: folder)
                .environment(store)
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Button("Test plans") { store.selection = nil }.buttonStyle(.plain)
            ForEach(store.path(to: folder.parentID)) { f in
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                Button(f.name) { store.selection = PlanStore.folderTag(f.id) }.buttonStyle(.plain)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct SubfolderCard: View {
    let folder: PlanFolder
    @Environment(PlanStore.self) private var store

    var body: some View {
        let all = store.allPlans(under: folder.id)
        let done = all.reduce(0) { $0 + $1.tasksDone }
        let total = all.reduce(0) { $0 + $1.plan.tasks.count }
        Button {
            store.expandedFolders.insert(folder.id)
            store.selection = PlanStore.folderTag(folder.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").font(.title2).foregroundStyle(folder.color.color.gradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name).font(.body.weight(.medium)).lineLimit(1)
                    Text("\(all.count) plan\(all.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                ProgressRing(value: total == 0 ? 0 : Double(done) / Double(total), lineWidth: 4)
                    .frame(width: 26, height: 26)
            }
            .padding(14)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

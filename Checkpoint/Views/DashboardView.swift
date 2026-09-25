import SwiftUI

/// Testing dashboard (IDEA-109): rolling-7-day activity, an 8-week trend,
/// and plans in progress. Computed from `updatedAt`, which bumps on every
/// tick, re-run and move — no new persistence needed.
struct DashboardView: View {
    @Environment(PlanStore.self) private var store

    private var weekAgo: Date { .now.addingTimeInterval(-7 * 24 * 3600) }

    private var touched: [SavedPlan] {
        store.plans.filter { $0.updatedAt >= weekAgo && !$0.archived }
    }

    private var inProgress: [SavedPlan] {
        store.sortPlans(store.plans.filter { !$0.archived && $0.progress > 0 && $0.progress < 1 })
    }

    /// Plans touched per week, oldest first (8 bars).
    private var trend: [Int] {
        (0..<8).map { w in
            let start = Date.now.addingTimeInterval(-Double(w + 1) * 7 * 24 * 3600)
            let end = Date.now.addingTimeInterval(-Double(w) * 7 * 24 * 3600)
            return store.plans.filter { $0.updatedAt >= start && $0.updatedAt < end }.count
        }.reversed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .font(.title)
                        .foregroundStyle(.indigo.gradient)
                    VStack(alignment: .leading) {
                        Text("Testing dashboard").font(.title2.weight(.semibold))
                        Text("Rolling 7 days · touch a plan to open it")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 16) {
                    StatCard(title: "Plans touched", value: "\(touched.count)", icon: "tray.full", tint: .indigo)
                    StatCard(title: "Tasks passed", value: "\(touched.reduce(0) { $0 + $1.tasksDone })", icon: "checkmark.circle", tint: .green)
                    StatCard(title: "AC met", value: "\(touched.reduce(0) { $0 + $1.criteriaMet })", icon: "seal", tint: .teal)
                    StatCard(title: "In progress", value: "\(inProgress.count)", icon: "hourglass", tint: .orange)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Touched per week").font(.headline)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(trend.enumerated()), id: \.offset) { _, n in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(n == trend.max() && n > 0 ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.accentColor.opacity(0.35)))
                                .frame(height: CGFloat(max(n, 0)) * 12 + (n > 0 ? 8 : 2))
                                .frame(maxWidth: .infinity)
                                .help("\(n) plans")
                        }
                    }
                    .frame(height: 90)
                }
                .padding(20)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                VStack(alignment: .leading, spacing: 8) {
                    Text("In progress").font(.headline)
                        .padding(.horizontal, 4)
                    if inProgress.isEmpty {
                        ContentUnavailableView("Nothing in progress", systemImage: "checkmark.seal",
                                               description: Text("Plans you start testing appear here."))
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(inProgress.prefix(20)) { saved in
                            SidebarRow(saved: saved)
                                .tag(saved.id)
                                .contentShape(.rect)
                                .onTapGesture { store.selection = saved.id }
                        }
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 140)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .glassScrollIndicator()
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint.gradient)
            Text(value)
                .font(.largeTitle.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

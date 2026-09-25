import SwiftUI
import Charts

/// Testing dashboard: the last 7 days of activity, an 8-week trend and the
/// plans still in progress. Built from `updatedAt`, which bumps on every tick,
/// re-run and move, so it needs no extra persistence.
struct DashboardView: View {
    @Environment(PlanStore.self) private var store

    private var weekAgo: Date { .now.addingTimeInterval(-7 * 24 * 3600) }

    private var touched: [SavedPlan] {
        store.plans.filter { $0.updatedAt >= weekAgo && !$0.archived }
    }

    private var inProgress: [SavedPlan] {
        store.sortPlans(store.plans.filter { !$0.archived && $0.progress > 0 && $0.progress < 1 })
    }

    private var overdue: [SavedPlan] {
        store.plans.filter { !$0.archived && $0.isOverdue }
    }

    private struct Week: Identifiable {
        let start: Date
        let count: Int
        var id: Date { start }
    }

    /// Plans touched per week, oldest first.
    private var trend: [Week] {
        let cal = Calendar.current
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return (0..<8).reversed().compactMap { w in
            guard let start = cal.date(byAdding: .weekOfYear, value: -w, to: thisWeek),
                  let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            return Week(start: start, count: store.plans.filter { $0.updatedAt >= start && $0.updatedAt < end }.count)
        }
    }

    var body: some View {
        let tasksPassed = touched.reduce(0) { $0 + $1.tasksDone }
        let tasksTotal = touched.reduce(0) { $0 + $1.plan.tasks.count }
        let acMet = touched.reduce(0) { $0 + $1.criteriaMet }
        let acTotal = touched.reduce(0) { $0 + $1.plan.acceptanceCriteria.count }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("Dashboard").font(.largeTitle.weight(.semibold))
                        } icon: {
                            Image(systemName: "chart.bar.fill").foregroundStyle(.indigo.gradient)
                        }
                        Text(touched.isEmpty
                             ? "No testing in the last 7 days."
                             : "\(touched.count) plan\(touched.count == 1 ? "" : "s") worked on in the last 7 days")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 16) {
                        MetricRing(value: tasksTotal == 0 ? 0 : Double(tasksPassed) / Double(tasksTotal),
                                   label: "tested", text: "\(tasksPassed)/\(tasksTotal)")
                        MetricRing(value: acTotal == 0 ? 0 : Double(acMet) / Double(acTotal),
                                   label: "AC met", text: "\(acMet)/\(acTotal)", tint: .teal)
                    }
                }
                .padding(24)
                .glassEffect(.regular.tint(.indigo.opacity(0.08)), in: .rect(cornerRadius: 28))

                HStack(spacing: 12) {
                    StatTile(value: touched.count, label: "plans touched", icon: "tray.full", tint: .indigo)
                    StatTile(value: inProgress.count, label: "in progress", icon: "hourglass", tint: .orange)
                    StatTile(value: touched.reduce(0) { $0 + $1.failedCount }, label: "failed tasks",
                             icon: "xmark.circle", tint: .red)
                    StatTile(value: overdue.count, label: "overdue", icon: "bell.badge", tint: .pink)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Plans worked on per week", systemImage: "chart.bar").font(.headline)
                    Chart(trend) { week in
                        BarMark(x: .value("Week", week.start, unit: .weekOfYear),
                                y: .value("Plans", week.count))
                            .foregroundStyle(week.start == trend.last?.start
                                             ? AnyShapeStyle(Color.accentColor.gradient)
                                             : AnyShapeStyle(Color.accentColor.opacity(0.4)))
                            .clipShape(.rect(cornerRadius: 5))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .weekOfYear)) {
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                            AxisGridLine()
                            AxisValueLabel()
                        }
                    }
                    .frame(height: 150)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.opacity(0.55), in: .rect(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.separator.opacity(0.5)))

                VStack(alignment: .leading, spacing: 10) {
                    Label("In progress", systemImage: "hourglass").font(.headline)
                    if inProgress.isEmpty {
                        Text("Plans you've started but not finished show up here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(inProgress.prefix(20)) { saved in
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
            .padding(.horizontal, PageLayout.side)
            .padding(.top, PageLayout.top)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .glassScrollIndicator()
    }
}

private struct StatTile: View {
    let value: Int
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint.gradient)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)").font(.title2.weight(.semibold).monospacedDigit())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

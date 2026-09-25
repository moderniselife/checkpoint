# IDEA-109 — Testing dashboard

**Status:** 🚧 Building'd · **Impact:** M · **Effort:** M · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: DashboardView (rolling-7-day cards, 8-week trend, in-progress list) on updatedAt history, sidebar entry + routing; compiled, needs real-world check.

## Problem
No answer to "how much did we test this week?"

## Proposal
Dashboard view: tested-this-week, AC-met trend, plans in progress, per-folder roll-ups.

## User flow
1. Sidebar → Dashboard (or folder overview upgrade).
2. See week stats + in-progress list.
3. Click through to plans.

## Scope
- **In:** week counts, trend sparkline, in-progress list.
- **Out (for now):** per-tester stats, exportable reports (see IDEA-043).

## Design notes
New top-level view with `MetricRing`s + bar/sparkline in Liquid Glass cards.

## Technical notes
Computed from `PlanStore.plans` (`createdAt`, `progress`, `criteriaProgress`); needs `updatedAt` for "tested this week" — add `SavedPlan.updatedAt` bumped on toggle. No new persistence file.

## Risks & open questions
- Week definition (rolling 7d vs calendar) — start rolling 7d.

## Done when
- [ ] Dashboard renders live stats
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

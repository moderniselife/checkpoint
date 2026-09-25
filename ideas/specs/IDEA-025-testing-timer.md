# IDEA-025 — Testing timer

**Status:** 🚧 Building'd · **Impact:** M · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: plan timer chip with live TimelineView time, persisted across launches, auto-pause on quit, totals in Markdown export; compiled, needs real-world check.

## Problem
No idea how long testing actually took — for estimates or worklogs.

## Proposal
Start/stop timer per plan (auto-pause on quit), manual adjust, total in header + export.

## User flow
1. Plan header → Start testing.
2. Pause/stop; adjust if forgotten.
3. Total shows + exports.

## Scope
- **In:** plan-level timer, persistence, export.
- **Out (for now):** per-task timing, Jira worklogs (see IDEA-026).

## Design notes
Timer chip in plan header with play/pause; feeds IDEA-109 dashboard later.

## Technical notes
`SavedPlan.testingSeconds: TimeInterval + timerRunningSince: Date?` in `plans.json`; tick via `TimelineView`. Pause on resign-active.

## Risks & open questions
- None major.

## Done when
- [ ] Timer tracks + exports correctly
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

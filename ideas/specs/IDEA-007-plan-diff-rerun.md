# IDEA-007 — Plan diff on re-run

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** M · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: transient PlanDiff computed in runSingle, banner + added/changed row highlights, Dismiss; compiled, needs real-world check.

## Problem
Re-runs silently change plans; testers can't see what moved.

## Proposal
After re-run, highlight added/removed/changed tasks and AC since the last run, with a diff summary bar.

## User flow
1. Re-run a plan.
2. Banner: "3 added · 1 removed · 2 changed" with toggles.
3. Ticks preserved on surviving tasks (already done); review highlights.

## Scope
- **In:** task/AC diff by stable identity, highlight UI, summary.
- **Out (for now):** word-level inline diffs.

## Design notes
Coloured left borders + pills in `PlanView`; diff computed pre/post `analyze`.

## Technical notes
`PlanStore.analyze` keeps prior `SavedPlan`; match tasks by `id` then fuzzy title; store `lastDiff` transiently (not persisted). AC matched by `id`.

## Risks & open questions
- LLM task IDs unstable — match by normalized title fallback.

## Done when
- [ ] Re-run shows added/removed/changed highlights
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

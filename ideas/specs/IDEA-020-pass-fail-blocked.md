# IDEA-020 — Pass / Fail / Blocked states

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: SavedPlan.failed/blocked dicts beside done (zero-migration), TaskRow verdict menu + actual/reason sheet, To do/Failed/Blocked filters, header counts, Markdown + HTML verdict export; compiled, needs real-world check.

## Problem
Done/not-done can't express "tried, it failed" or "can't test this yet".

## Proposal
Per-task state: Todo → Pass / Fail / Blocked (reason required for Blocked, expected+actual for Fail). Rings count Pass; Fail/Blocked surface in header.

## User flow
1. Task menu → Pass/Fail/Blocked (Fail prompts actual, Blocked prompts reason).
2. Header shows pass ring + fail/blocked counts.
3. Re-run preserves states on surviving tasks.

## Scope
- **In:** 4-state model, UI, export, preserved across re-runs.
- **Out (for now):** per-run history (see IDEA-023).

## Design notes
State dots in `TaskRow`; filter gains Failed/Blocked.

## Technical notes
Replace `SavedPlan.done: Set` usage with `taskState: [id: State]` (migrate `done` → pass). Persist in `plans.json`. `PlanExporter` prints verdicts.

## Risks & open questions
- Migration must not lose existing ticks.

## Done when
- [ ] Four states persist, filter, export
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

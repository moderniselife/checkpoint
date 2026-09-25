# IDEA-002 — Risk-based ordering

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** M · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: P0/P1/P2 badges derived from priority (Task.risk/RiskChip) + P0 lens filter; no model change; compiled, needs real-world check.

## Problem
Tasks read in research order, not blast-radius order; testers guess what matters.

## Proposal
P0/P1/P2 tags per task by blast radius + "Run P0 only" filter. Prompt asks the model to rank; UI filters/sorts.

## User flow
1. Plan arrives with P0–P2 badges.
2. Filter to P0 only for a tight pass.
3. Export respects the filter.

## Scope
- **In:** risk badge, sort/filter, prompt change.
- **Out (for now):** custom risk rubrics per team (see IDEA-009).

## Design notes
Badge next to `PriorityDot` in `TaskRow`; filter chip in `PlanView`.

## Technical notes
`TestPlan.Task` gains `risk: P0|P1|P2` (or reuse `priority` — currently high/medium/low; map or extend with back-compat default P1). Update `jsonSchema`, prompt, `PlanExporter`. Migration: missing → P1.

## Risks & open questions
- Model calibration — eval on sample epics (see IDEA-087).

## Done when
- [ ] Risk badges + P0 filter work on new plans
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

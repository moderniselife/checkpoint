# IDEA-084 — Regenerate one section

**Status:** 🚧 Building'd · **Impact:** M · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: per-section regen (tasks/AC/edge cases) with ID-preserving merge; compiled, needs real-world check.

## Problem
One weak section (tasks, AC, edge cases) forces a full re-run.

## Proposal
Per-section Regenerate: tasks / AC / edge cases / summary, reusing research context.

## User flow
1. Section header → Regenerate.
2. New section streams in; ticks on other sections untouched.

## Scope
- **In:** section-scoped regen with preserved ticks.
- **Out (for now):** free-form section prompts.

## Design notes
Regen icon per card header in `PlanView`.

## Technical notes
Small LLM call with plan + research context, section schema only; merge by section. Needs chat infra-lite (see IDEA-083) or a `PlanGenerator.regenerate(section:)` helper.

## Risks & open questions
- Cross-section consistency (covers-links) — revalidate AC coverage after merge.

## Done when
- [ ] Section regen works, ticks preserved
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

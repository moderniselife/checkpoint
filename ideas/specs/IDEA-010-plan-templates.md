# IDEA-010 — Plan templates

**Status:** 🚧 Building'd · **Impact:** M · **Effort:** M · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: bug/feature/epic template blocks + input-bar TemplateMenu override, per-plan chip; type-aware guide in shared prompt; compiled, needs real-world check.

## Problem
Bugs, features and epics need different plan shapes; one prompt fits none perfectly.

## Proposal
Per-type templates (bug / feature / epic): section emphasis + extra instructions, auto-picked from ticket type with manual override.

## User flow
1. Analyze → template auto-picked from issue type, shown as chip.
2. Override via menu; re-run uses the chosen template.

## Scope
- **In:** 3 built-in templates, auto-pick + override.
- **Out (for now):** user-authored templates.

## Design notes
Template chip in input bar + plan header.

## Technical notes
`PlanGenerator.systemPrompt` gains template branch; ticket `type` already in `TestPlan.Ticket`. Store chosen template on `SavedPlan`.

## Risks & open questions
- Type strings vary by tracker — normalise (bug, story/feature, epic).

## Done when
- [ ] Bug/feature/epic plans differ sensibly
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

# IDEA-016 — Coverage-gap suggestions

**Status:** 🚧 Building'd · **Impact:** M · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: one-click gap-fill (suggestTask) on uncovered criteria; template-drafted, deduped by id; compiled, needs real-world check.

## Problem
Orange "uncovered" AC just sits there; tester must invent the missing task.

## Proposal
One click on an uncovered criterion drafts the missing task (client template first, LLM refine later) and inserts it.

## User flow
1. See uncovered AC → Suggest task.
2. Preview → Insert (covers that AC).

## Scope
- **In:** template-drafted task, insert + cover link.
- **Out (for now):** model-generated tasks (needs IDEA-084 infra).

## Design notes
Button in `CriteriaLegend`/uncovered row.

## Technical notes
Client template using AC text + ticket key; `PlanStore` insert helper; marks `covers=[ac.id]`.

## Risks & open questions
- None — template is deliberately plain.

## Done when
- [ ] One-click gap fill works
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

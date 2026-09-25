# IDEA-008 — Ambiguity detector

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped V1: client vagueness heuristic on CriterionRow with amber flag, draft-questions popover + copy; advisory only; compiled, needs real-world check.

## Problem
Vague AC ("works correctly") sails through; testers discover gaps mid-run.

## Proposal
Flag vague AC with a ⚠ badge + one-click draft questions for PM/dev, appended to open questions.

## User flow
1. Plan shows amber flags on fuzzy criteria.
2. Click → suggested clarifying questions.
3. Copy into a ticket comment.

## Scope
- **In:** heuristic + prompt-based vagueness flags, question drafts.
- **Out (for now):** auto-commenting to Jira.

## Design notes
Badge in `CriterionRow`; popover with draft questions.

## Technical notes
Prompt addition (list ambiguous AC + why); client heuristic (short/hedged text) as fallback. No model change.

## Risks & open questions
- False positives — keep it advisory, never blocking.

## Done when
- [ ] Vague AC flagged with draft questions
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

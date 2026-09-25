# IDEA-086 — "Why this task?"

**Status:** 🚧 Building'd · **Impact:** M · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped V1: derived rationale popover (priority/coverage/sources), no LLM call; compiled, needs real-world check.

## Problem
Testers don't trust tasks they can't trace.

## Proposal
Per-task explainer: 1–2 sentences of reasoning + source links, on demand.

## User flow
1. Task → Why this task?
2. Popover explains + links sources.

## Scope
- **In:** on-demand explanation using stored research.
- **Out (for now):** persistent explanations on every task (see IDEA-011).

## Design notes
Info button in `TaskRow`; popover with reasoning + source chips.

## Technical notes
V1: derive from `covers` + sources + ticket title (no LLM). V2: small LLM call with task + cited sources (uses IDEA-083 infra).

## Risks & open questions
- None for V1.

## Done when
- [ ] Every task explains itself with sources
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

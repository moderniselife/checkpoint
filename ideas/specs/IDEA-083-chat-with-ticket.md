# IDEA-083 — Chat with the ticket

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** M · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped V1: per-plan chat thread (no live tools; answers from plan context), per-answer Update-plan via revision merge; compiled, needs real-world check.

## Problem
Plans are one-shot; "what about admins?" means a full re-run.

## Proposal
Follow-up chat per plan: ask questions, request changes ("add admin coverage"), model refines the plan with tools available.

## User flow
1. Plan → Ask a follow-up → type.
2. Answer streams; Apply patch updates tasks/AC.
3. History kept per plan.

## Scope
- **In:** chat thread, tool-aware answers, apply-patch to plan.
- **Out (for now):** cross-plan chat.

## Design notes
Chat drawer in `PlanView` (Plan | Research | Chat tabs).

## Technical notes
New `PlanChat` service reusing `ClaudeClient`/`OpenAIChatClient` + MCP tools + current plan JSON as context; patch via JSON merge, preserve `done/metCriteria` by ID. Persist thread in `SavedPlan`.

## Risks & open questions
- Patch conflicts with ticks — ID-stable merge required.

## Done when
- [ ] Follow-ups refine the plan without losing ticks
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

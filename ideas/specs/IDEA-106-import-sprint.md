# IDEA-106 — Import a sprint

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** M · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: BatchSheet (JQL search, epic fetch, paste list) + PlanStore.startBatch (sequential queue into a new folder, progress + cancel, error summary) in BatchSheet.swift; compiled, needs real-world check.

## Problem
Planning a whole sprint means pasting keys one by one.

## Proposal
Pick a sprint/board (Jira) or cycle (Linear) → every issue gets its own plan, filed in a new folder named for the sprint.

## User flow
1. Sidebar → Import sprint → pick board/sprint (or Linear team/cycle).
2. App creates folder + queues analyses with progress + cancel.
3. Failed keys report at the end; re-try individually.

## Scope
- **In:** sprint/cycle picker, batch queue into a folder, progress + cancel, error summary.
- **Out (for now):** incremental sync, auto-replan on sprint change.

## Design notes
Sheet with picker + destination folder name; `ProgressFeedView`-style batch bar.

## Technical notes
New MCP queries: Jira `search` JQL `sprint = X` / Linear `list_issues(cycleId)` — argument names read from tool schemas like `TicketInspector` does. Reuse `PlanStore.analyze` queue; cap concurrency (2–3), back-compat IDs.

## Risks & open questions
- Sprint custom-field IDs vary per Jira site — prefer `getAccessibleAtlassianResources`-style discovery, fall back to board APIs via MCP.

## Done when
- [ ] Sprint import creates one plan per issue in a folder
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

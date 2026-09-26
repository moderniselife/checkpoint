# IDEA-108 — Bulk-analyze epic children

**Status:** 🚧 Building'd · **Impact:** M · **Effort:** M · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: "Plan each child" button in ChildIssuesView reusing the batch queue with pre-resolved keys; compiled, needs real-world check.

## Problem
Epics produce one giant plan; teams want per-child plans filed together.

## Proposal
From an epic plan or ticket panel: "Plan each child" → one plan per child into a folder, with a parent index linking them.

## User flow
1. Open epic → Plan each child → confirm folder name.
2. Batch runs with progress + cancel.
3. Folder overview shows per-child rings.

## Scope
- **In:** child enumeration (JQL `parent = KEY` / Linear sub-issues), batch into folder.
- **Out (for now):** combined roll-up plan.

## Design notes
Button in epic plan header + `ChildIssuesView`; reuses batch UI from IDEA-106.

## Technical notes
Reuse `TicketInspector.jiraChildren` + Linear `list_issues(parentId)` fallback; same queue as IDEA-106. Folder per epic key.

## Risks & open questions
- Large epics (50+ children) — cap + confirm dialog.

## Done when
- [ ] Epic children each get a plan in one folder
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

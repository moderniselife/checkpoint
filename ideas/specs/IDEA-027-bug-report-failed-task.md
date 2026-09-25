# IDEA-027 — Bug report from failed task

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** M · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: pre-filled BugReportSheet from failed tasks (steps/expected/actual/evidence/note) with copy; one-click create still gated on write scope; compiled, needs real-world check.

## Problem
Failed tasks need retyping as bug reports elsewhere.

## Proposal
From a failed task: pre-filled report (steps, expected, actual from note, evidence list, plan/ticket links) — copy or create in tracker.

## User flow
1. Mark task Fail with actual.
2. Report bug → preview sheet.
3. Copy markdown or (later) create issue via write MCP.

## Scope
- **In:** pre-filled preview + copy; Jira-markup/Linear-markdown variants.
- **Out (for now):** one-click create (needs write scope; see IDEA-040).

## Design notes
Sheet in `PlanView` with editable fields + copy button.

## Technical notes
Pure render from task + notes + evidence + sources; reuse `PlanExporter` formatting. No new MCP calls.

## Risks & open questions
- Keep create-button hidden until write scope exists.

## Done when
- [ ] Failed task → copyable bug report
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

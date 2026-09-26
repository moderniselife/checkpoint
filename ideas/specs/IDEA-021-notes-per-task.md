# IDEA-021 — Notes per task

**Status:** 🚧 Building'd · **Impact:** M · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: SavedPlan.notes (preserved on re-run) + inline note editor in TaskRow + Markdown/HTML export; keyboard n opens it; compiled, needs real-world check.

## Problem
Observations live in scratch files; context lost by export time.

## Proposal
Freeform note per task (markdown-ish), shown inline, included in exports.

## User flow
1. Task → Add note → type.
2. Note shows under the task; edit/delete inline.
3. Exports include notes.

## Scope
- **In:** per-task notes, inline editor, export.
- **Out (for now):** rich text/images in notes (see IDEA-022).

## Design notes
Expandable note row in `TaskRow` with note icon when present.

## Technical notes
`SavedPlan.notes: [taskId: String]` in `plans.json`; included in `PlanExporter.markdown/html`.

## Risks & open questions
- None.

## Done when
- [ ] Notes persist + export
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

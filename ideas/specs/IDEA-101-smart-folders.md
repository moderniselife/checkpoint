# IDEA-101 — Smart folders

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** M · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: ticket metadata (labels/components/fixVersions/parentKey) in TestPlan.Ticket + prompt + schema, SmartFolder model with live matching, sidebar section + rule editor + overview + convert-to-static; compiled, needs real-world check.

## Problem
Manual folders rot: sprint/epic/label groupings must be rebuilt every run.

## Proposal
Rule-based virtual folders: group by sprint (fix version), epic/parent, label, or component. Live counts, read-only contents, convertible to a real folder.

## User flow
1. Sidebar → New smart folder → pick rule + value.
2. Plans matching the rule appear automatically.
3. Convert to static folder, or edit/delete the rule.

## Scope
- **In:** rule types (fixVersion, epic/parent, label, component), live membership, convert.
- **Out (for now):** JQL-backed rules, cross-tracker unions.

## Design notes
Distinct folder icon (gear badge) in `SidebarView`; rule editor popover like `FolderEditor`.

## Technical notes
New `SmartFolder: Codable {id, name, rule}` persisted in `folders.json` alongside `PlanFolder`; membership computed from `SavedPlan.plan` fields (needs fixVersion/labels surfaced — extend `TestPlan.Ticket` or derive from sources). `allPlans(under:)` gains a virtual branch.

## Risks & open questions
- Ticket metadata for sprint/labels isn't fully stored today — may need a `labels/fixVersions` field on `SavedPlan`.

## Done when
- [ ] Smart folder shows live matching plans
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

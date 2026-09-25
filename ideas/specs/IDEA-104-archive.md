# IDEA-104 — Archive

**Status:** 🚧 Building · **Impact:** M · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** SavedPlan.archived + show-archived toggle + restore live; compiled, unverified.

## Problem
Finished plans clutter the sidebar; deleting loses history.

## Proposal
Archive hides plans from the tree (toggleable Archive view), restorable or deletable later.

## User flow
1. Right-click → Archive (or header button).
2. Toggle Show archived to review; Restore or Delete permanently.

## Scope
- **In:** archived flag, hidden-by-default, restore/delete.
- **Out (for now):** auto-archive rules.

## Design notes
Sidebar footer toggle; archived rows dimmed with restore action.

## Technical notes
`SavedPlan.archived: Bool = false` in `plans.json`; `plans(in:)` filters archived unless showing. Keep `done/metCriteria`.

## Risks & open questions
- None.

## Done when
- [ ] Archive/restore works, hidden by default
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

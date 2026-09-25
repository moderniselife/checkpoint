# IDEA-103 — Pin / favourite

**Status:** 🚧 Building · **Impact:** S · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** SavedPlan.pinned + Pinned section + context actions live; compiled, unverified.

## Problem
Active plans sink under new runs; re-finding today's work costs clicks.

## Proposal
Pin plans to a Pinned section at the top of the sidebar; toggle via context menu, header button, or ⌘⇧P.

## User flow
1. Right-click plan → Pin (or header pin icon).
2. Pinned section lists them; unpin returns to folder order.

## Scope
- **In:** pinned flag, Pinned section, toggle UI + shortcut.
- **Out (for now):** pinning folders.

## Design notes
Pin icon in `SidebarRow` and plan toolbar; Pinned section above Test plans.

## Technical notes
`SavedPlan.pinned: Bool = false` in `plans.json`; sidebar renders `plans where pinned` first. No selection-ID change.

## Risks & open questions
- None.

## Done when
- [ ] Pin/unpin persists and section renders
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

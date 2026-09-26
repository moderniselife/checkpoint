# IDEA-100 — Search & filter plans

**Status:** 🚧 Building · **Impact:** L · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Sidebar search + mode/tracker/progress/tag filters live in SidebarView (PlanStore.matches); compiled, unverified.

## Problem
With dozens of plans, finding one by key/title/folder in the sidebar is slow, for devs and QA.

## Proposal
Sidebar search field + filter chips (mode, tracker, progress: all/in-progress/done). Filters folders too; empty state explains what didn't match.

## User flow
1. Type in sidebar search (⌘F focuses).
2. Toggle mode/tracker/progress chips.
3. Click a result; Clear restores the tree.

## Scope
- **In:** key/title/folder/mode/tracker/progress filtering, keyboard focus, empty state.
- **Out (for now):** full-text search inside tasks/AC, saved searches.

## Design notes
Search field atop `SidebarView` (sidebar style), chips below; matching rows highlight; folders auto-expand when they contain matches. Liquid Glass chips.

## Technical notes
`SidebarView.swift` + `PlanStore.swift`: computed `filteredPlans`/`filteredFolders` from `selection`-independent query; `plans(in:)`/`childFolders(of:)` stay canonical. No model change. Persist last query? No — session-only `@State`.

## Risks & open questions
- Fuzzy vs prefix matching? Start with case-insensitive contains on key/title/folder name.

## Done when
- [ ] Search + chips filter sidebar correctly
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

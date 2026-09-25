# IDEA-105 — Sort options

**Status:** 🚧 Building · **Impact:** S · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** PlanStore.sidebarSort (updated/progress/key/AC-met) + header menu live; compiled, unverified.

## Problem
Sidebar order is fixed; leads want recently-updated or least-tested first.

## Proposal
Sort menu: by updated, progress, key, AC-met. Applies within folders; persists.

## User flow
1. Sidebar header sort menu → pick key + direction.
2. Order updates; choice persists across launches.

## Scope
- **In:** 4 sort keys, asc/desc, persisted preference.
- **Out (for now):** custom manual ordering.

## Design notes
Sort icon in `SidebarView` header, next to new-folder button.

## Technical notes
`UserDefaults(sidebarSort, sidebarSortAsc)`; sort comparators over `SavedPlan(createdAt, progress, criteriaProgress, plan.ticket.key)`. Folders stay alpha-sorted.

## Risks & open questions
- `updatedAt` doesn't exist — use `createdAt` first, add `updatedAt` on toggle/re-run later.

## Done when
- [ ] Sort applies + persists
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

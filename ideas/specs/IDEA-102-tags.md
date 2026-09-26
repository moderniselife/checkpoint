# IDEA-102 — Tags

**Status:** 🚧 Building · **Impact:** S · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** SavedPlan.tags + OrganiseRow editor + sidebar filter live; compiled, unverified.

## Problem
Folders are one-dimensional; a plan can be both "sprint-12" and "needs-qa".

## Proposal
Freeform tags on plans: add/remove in plan header or sidebar context menu, filter by tag, shown as chips.

## User flow
1. Plan header → tag editor (comma entry, autocomplete).
2. Sidebar filter chip or search `tag:x` narrows to tagged plans.
3. Remove tag from header or context menu.

## Scope
- **In:** per-plan string set, editor UI, tag filter.
- **Out (for now):** tag colours, shared team tag taxonomy.

## Design notes
Chips in `PlanView` header and `SidebarRow`; autocomplete from existing tags.

## Technical notes
`SavedPlan.tags: Set<String> = []` in `PlanStore.swift`, persisted in `plans.json` (back-compat default). Normalise lowercase/trim. Combine with IDEA-100 filters.

## Risks & open questions
- None major; keep max tag length sane.

## Done when
- [ ] Tags persist, filter, export includes them
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

# IDEA-029 — Keyboard-first testing

**Status:** 🚧 Building'd · **Impact:** M · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: focusable task list, j/k move, space tick, f fail, b blocked, n note, selection highlight + hint bar; compiled, needs real-world check.

## Problem
Mouse-ticking dozens of tasks is slow.

## Proposal
j/k move, space toggles pass, f fail, b blocked, n note, / filter. Visible shortcut hints.

## User flow
1. Focus plan list; j/k navigates.
2. Space/f/b update state; n opens note.
3. Shortcuts listed in help menu.

## Scope
- **In:** navigation + state keys + hints.
- **Out (for now):** full remapping.

## Design notes
Focus ring in `PlanView`; footer hint bar.

## Technical notes
`focusedValue` + `.onKeyPress` in `PlanView`; reuse `toggle`/state setters. No model change.

## Risks & open questions
- Avoid clashing with text-field input — only when list focused.

## Done when
- [ ] All keys work without mouse
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

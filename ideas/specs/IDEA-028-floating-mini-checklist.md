# IDEA-028 — Floating mini checklist

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** M · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: non-activating floating NSPanel with plan switcher + live-ticking rows via shared PlanStore, toolbar button; compiled, needs real-world check.

## Problem
Testing happens in a browser; the full app window is in the way.

## Proposal
Always-on-top compact window with the current plan's tasks; tick syncs back live.

## User flow
1. Plan → Pop out checklist.
2. Mini window floats while testing; tick tasks.
3. Close returns; main plan updated.

## Scope
- **In:** floating window, ticking, plan switcher.
- **Out (for now):** editing tasks/notes in mini mode.

## Design notes
`NSPanel` floating, compact rows + progress ring; follows selected plan.

## Technical notes
Second window scene sharing `PlanStore` environment; same `toggle` API. macOS `NSPanel(.floating, .nonactivating)`.

## Risks & open questions
- Window management edge cases (Spaces, fullscreen).

## Done when
- [ ] Mini window ticks sync live
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

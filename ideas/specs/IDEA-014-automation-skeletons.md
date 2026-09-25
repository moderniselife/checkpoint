# IDEA-014 — Automation skeletons

**Status:** 🚧 Building'd · **Impact:** M · **Effort:** M · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: PlanExporter.automation for Playwright + XCTest, Copy menu items; pure render; compiled, needs real-world check.

## Problem
Manual plans die in automation backlogs; devs rewrite them as Playwright/XCTest by hand.

## Proposal
Dev-mode export: Playwright (TS) or XCTest stubs from tasks — test names, steps as comments/todos, AC links.

## User flow
1. Dev plan → Export → Copy Playwright skeleton.
2. Paste into repo; fill in selectors.

## Scope
- **In:** Playwright + XCTest templates, copy/save.
- **Out (for now):** runnable selectors, page-object generation.

## Design notes
Export menu additions in `PlanView` toolbar.

## Technical notes
New `PlanExporter.automation(ctx, framework)`; pure string render, no LLM. Titles sanitised to test names.

## Risks & open questions
- Keep stubs obviously incomplete (todo markers).

## Done when
- [ ] One-click skeletons for both frameworks
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

# IDEA-015 — Regression suite builder

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** L · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: SuiteBuilderSheet (plan picker, deduped merge, local ticks, Markdown copy) from FolderOverview; suites transient; compiled, needs real-world check.

## Problem
Release testing means re-opening N plans and deduping shared setup by hand.

## Proposal
Multi-select plans (or a folder) → one deduped regression run: merged setup, ordered tasks, per-source refs.

## User flow
1. Folder → Build regression suite → pick plans.
2. Preview merged run; export/print.
3. Ticks stored on the suite (not source plans).

## Scope
- **In:** merge + dedupe preview, suite ticking, export.
- **Out (for now):** auto-updating suites.

## Design notes
Sheet + virtual plan view reusing `PlanView` rows.

## Technical notes
New `RegressionSuite(ids, tasks)` derived (not persisted as `SavedPlan` initially); dedupe by normalized title; sources kept per task.

## Risks & open questions
- Dedup quality — exact+stem match first, LLM assist later.

## Done when
- [ ] Suite builds, ticks, exports
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

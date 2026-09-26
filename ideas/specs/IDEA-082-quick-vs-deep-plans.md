# IDEA-082 — Quick vs deep plans

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: input-bar Quick/Deep toggle, quickModel setting at low effort, per-plan chip, Upgrade-to-deep; re-runs preserve preset; compiled, needs real-world check.

## Problem
Every run uses the best (slow, pricey) setup, even for trivial tickets.

## Proposal
Quick (cheap model + low effort) vs Deep (best model + high effort) presets in the input bar; one-tap upgrade from quick to deep.

## User flow
1. Input bar → Quick/Deep toggle (default Deep).
2. Quick plan arrives fast; Upgrade to deep re-runs on best config.

## Scope
- **In:** preset toggle, per-preset provider/model/effort, upgrade action.
- **Out (for now):** auto-pick by ticket size.

## Design notes
Segmented control next to mode toggle; upgrade button in quick-plan header.

## Technical notes
`AppSettings.quickConfig: LLMConfig` (UserDefaults) vs current `llmConfig` as deep; `PlanStore.analyze` takes override config. No generator change.

## Risks & open questions
- Which cheap default? Provider-aware (e.g. Haiku / gpt-mini / local).

## Done when
- [ ] Quick/deep presets + upgrade work
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

# IDEA-001 — Smoke-test mode

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: derived smoke subset (TestPlan.smokeSubset, top-6 by risk), Smoke lens toggle, smoke-aware copy/save export; compiled, needs real-world check.

## Problem
Full plans are overkill for a quick "does it basically work" check after a deploy.

## Proposal
One-tap smoke subset: top ~5 tasks covering install/open/happy-path, generated cheaply or derived from the full plan.

## User flow
1. Plan header → Smoke subset toggle.
2. See 5-minute checklist; tick through it.
3. Export smoke-only if needed.

## Scope
- **In:** derived subset (no extra LLM call first version), toggle + export filter.
- **Out (for now):** separate smoke generation prompt.

## Design notes
Segmented control in `PlanView` (Full | Smoke); smoke = P0/high-priority tasks first, max 6.

## Technical notes
Pure client derivation: `plan.tasks filter priority==.high prefix 6` + deploy-confirm task; no model change. Later: `scenarioPrompt`-style smoke instruction.

## Risks & open questions
- Priority quality varies — fall back to first tasks per ticket.

## Done when
- [ ] Smoke toggle shows a sane 5-min subset
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

# IDEA-009 — Team house rules

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: AppSettings.houseRules (1000-char cap) appended to every prompt + Settings Testing editor; compiled, needs real-world check.

## Problem
Every team repeats itself: "always check Safari", "use tenant X".

## Proposal
Custom instructions text box in Settings → Testing; appended to every generation prompt.

## User flow
1. Settings → House rules → type rules.
2. All new plans follow them (e.g. browser, tenant, env).

## Scope
- **In:** free-text rules, prompt injection, per-plan indicator.
- **Out (for now):** per-folder/per-project rules.

## Design notes
Textarea in Settings; small "house rules applied" note in plan header.

## Technical notes
`AppSettings.houseRules: String` (UserDefaults); `PlanGenerator.prompt` appends block. No model change.

## Risks & open questions
- Long rules eat context — cap ~1000 chars with counter.

## Done when
- [ ] Rules affect generated plans
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

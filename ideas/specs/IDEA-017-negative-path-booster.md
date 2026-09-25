# IDEA-017 — Negative-path booster

**Status:** 🚧 Building'd · **Impact:** M · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: curated 5-item edge-case booster with title-stem dupe check; compiled, needs real-world check.

## Problem
Plans skew happy-path; edge cases thin out on small tickets.

## Proposal
"Add more edge cases" button appends 3–5 extra negative-path tasks (client checklist + prompt assist).

## User flow
1. Plan → Add edge cases.
2. New tasks appear under an Edge cases group, tickable + removable.

## Scope
- **In:** one-click extra edge tasks.
- **Out (for now):** full regenerate (see IDEA-084).

## Design notes
Button near edge-cases section in `PlanView`.

## Technical notes
V1: curated checklist filtered by ticket text (auth, input, empty, offline, permissions). V2: small LLM call with plan context (needs chat infra IDEA-083).

## Risks & open questions
- Avoid duplicates — title-stem check before insert.

## Done when
- [ ] Booster adds sane edge tasks without dupes
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

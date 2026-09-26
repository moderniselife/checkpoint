# IDEA-012 — Time estimates

**Status:** 🚧 Building'd · **Impact:** M · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: Task.estimateMin in schema + prompt, per-task and header totals; compiled, needs real-world check (needs a fresh run).

## Problem
No sense of plan size: is this 20 minutes or 3 hours?

## Proposal
Estimated minutes per task + total in the header; sums respect filters.

## User flow
1. Plan shows "≈45 min" total; each task shows its slice.
2. Filtered views re-sum.

## Scope
- **In:** per-task minutes, totals, prompt change.
- **Out (for now):** learning from actuals (needs IDEA-025).

## Design notes
Muted minutes next to priority in `TaskRow`; total in header rings row.

## Technical notes
`Task.estimateMin: Int?` + schema/prompt ("realistic manual minutes"); total = sum. Back-compat nil → hidden.

## Risks & open questions
- Estimates drift — label as rough.

## Done when
- [ ] Plans show per-task + total estimates
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

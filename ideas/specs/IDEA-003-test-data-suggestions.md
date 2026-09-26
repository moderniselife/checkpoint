# IDEA-003 — Test data suggestions

**Status:** 🚧 Building'd · **Impact:** M · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: Task.testData in schema + prompt, copyable data block in TaskRow, Markdown/HTML export; compiled, needs real-world check (needs a fresh run).

## Problem
"Use valid input" wastes time; testers invent data per task.

## Proposal
Concrete sample inputs per task (valid, invalid, boundary) in a copyable block.

## User flow
1. Expand a task → Data block with 3–5 values.
2. Click to copy.

## Scope
- **In:** `testData` per task, UI block, prompt change.
- **Out (for now):** tenant-specific data pools.

## Design notes
Monospace block under steps in `TaskRow`, copy button.

## Technical notes
`Task.testData: [String] = []` + schema + prompt line; exporter includes it. Back-compat default empty.

## Risks & open questions
- Avoid real PII — prompt says synthetic examples only.

## Done when
- [ ] Tasks show copyable sample data
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

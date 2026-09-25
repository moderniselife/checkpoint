# IDEA-011 — Source citations per task

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** M · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: Task.sources in schema + prompt, per-task source line with ticket links, Markdown/HTML export; compiled, needs real-world check (needs a fresh run).

## Problem
"Why am I testing this?" — tasks don't point back to the comment/AC/page that caused them.

## Proposal
Each task lists its sources (ticket key + comment/AC/page snippet); click jumps to the ticket tab or source list.

## User flow
1. Task shows "from PROJ-123 · AC2 · comment".
2. Click → opens source in panel or scrolls to AC.

## Scope
- **In:** per-task source refs, click-through.
- **Out (for now):** exact deep-links into Jira comments.

## Design notes
Small source line under `expected` in `TaskRow`, using existing `TicketKeyButton`.

## Technical notes
`Task.sources: [TaskSource{ticketKey, kind, ref}] = []` + schema/prompt; fallback derives from `covers` + ticketKey. Exporter prints them.

## Risks & open questions
- Model compliance — eval; fallback keeps it useful.

## Done when
- [ ] Tasks show clickable sources
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

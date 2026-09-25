# Plans: how they get written

**What:** a test plan is a researched brief — summary, setup, acceptance criteria, tickable tasks,
edge cases, open questions and sources — generated from a ticket and everything around it.
**Why this shape:** the reader should never need another tab open.

## What's inside

- **Summary** — two to four sentences on what changed, in the reader's language.
- **Before you start** — environment, tenancy, roles, flags, test data, build to verify.
- **Acceptance criteria** — quoted from the tickets (or marked *derived*), each tickable as met.
- **Test tasks** — numbered steps plus one observable expected result, grouped per ticket for epics,
  with priority, area, risk badge (P0–P2), time estimate, sample data and source links.
- **Edge cases, open questions, sources** — what to poke, what's unclear, and everything it read.

## Dev vs QA mode

Toggle in the input bar (**⌘⇧M**), default in Settings → Testing.

| | Dev | QA |
|---|---|---|
| Reader | the developer | a tester on the hosted app |
| Language | branches, APIs, logs welcome | UI names only |
| First task | setup | confirm the fix is deployed |
| Technical-only checks | tasks | open questions for the dev |

**When:** Dev for your own branches; QA for staging/prod sign-off. Both plans for one ticket live side by side.

## Effort, templates, presets

- **Effort** (Settings → AI provider: low/medium/high/xhigh) steers reasoning depth on providers
  that support it — and everywhere it caps how long a runaway thinker may run before Checkpoint
  cuts it off and moves on. Local models that think forever are bounded by this.
- **Templates** (the options menu at the end of the ticket field: Auto/Bug/Feature/Epic) reshape the plan — bugs lead with
  reproduction, features with happy path, epics stay grouped per child. Auto follows the ticket type.
- **Quick vs Deep** (same options menu): Quick uses a cheaper model at low effort for trivial tickets;
  Deep uses your best setup. Set the quick model in Settings → AI Provider. Quick plans carry a chip,
  and **Re-run** offers **Upgrade to Deep**. The menu lights up while anything differs from the defaults.
- **House rules** (Settings → Testing): standing instructions appended to every prompt,
  e.g. "always check Safari, use tenant X".

## Cost

Every run records tokens and an approximate $ figure, shown in the plan's **Research** tab.
Prices are a snapshot and unknown models show tokens only.

## Scenarios (optional)

The Scenarios menu adds 3–6 end-to-end journeys: **from related tickets** (tracker only) or
**tickets + codebase** (reads a repo folder you choose — sandboxed, read-only, confined to it).

## Re-running and diffs

**Re-run** regenerates the plan and keeps ticks, verdicts, notes and tags on surviving tasks.
If anything changed, a banner summarizes added/removed/changed items and the rows highlight —
dismiss it when you've reviewed.

**Why IDs matter:** survival is matched by stable task IDs, so edits to a task's wording can look
like remove+add. Ticks on reworded tasks may need re-ticking; that's the trade-off for honest diffs.

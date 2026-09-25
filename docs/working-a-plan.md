# Working a plan

**What:** everything you do after the plan arrives — proving it, recording it, refining it.
**Why:** a plan is a work surface, not a document. Ticks, verdicts, notes and evidence are the work.

## Verdicts, not just ticks

Each task has an outcome: **To do**, **Pass**, **Fail** (with what actually happened) or
**Blocked** (with why). Click the circle to pass; the ⋯ menu sets Fail/Blocked with detail.
The header counts passes on its rings and calls out failures and blocks.

**When:** fail the moment something misbehaves — the actual-result you type becomes the bug report later.

## Finding things in a big plan

- The glass pill on **Test tasks** switches **To do / All / Failed / Blocked** (with counts) and holds
  the **Smoke** (5-minute top-risk subset) and **P0** lenses. Active lenses show as removable pills above the list.
- **Estimates** under each task and in the header size the run; **sample data** blocks copy valid/invalid/boundary inputs.
- **Source links** under each task jump to the ticket, comment or page it came from; **Why this task?**
  in its ⋯ menu explains why it exists.
- Amber ⚠ flags mark **vague acceptance criteria** with draft questions for the PM/dev; the ⊕ on an
  uncovered criterion drafts the missing task in one click. **Add more edge cases** appends curated
  negative paths without duplicating.

## Notes, evidence, timer

- **Notes** (⋯ → Add Note, or `n`): freeform observations per task, included in exports.
- **Evidence** (⋯ → Attach Evidence, or drag screenshots or files onto a task). Thumbnails preview inline;
  Markdown lists them, HTML embeds small images.
- **Timer** (stopwatch under the plan summary): start/stop time-on-task. It persists across launches, auto-pauses on quit,
  and totals into exports.

## Asking for changes

- **Chat tab**: ask follow-ups ("what about admins?"). Answers stay in the thread; **Update plan
  from this** folds an answer back into the plan with ticks intact.
- **Regenerate** (the ⋯ on Acceptance criteria and Edge cases, the task pill on Test tasks) redoes
  just that section.
- Chat and regen use the same ID-preserving merge as re-runs.

## Keyboard and mini panel

Click the task list, then **j/k** move, **space** ticks, **f** fails, **b** blocks, **n** notes.
**More** (⋯) → **Mini Checklist** in the plan toolbar opens a floating always-on-top checklist that ticks live while you test
in a browser — same store, no sync step.

## Bug reports

**Report bug…** on a failed task opens a pre-filled report: steps, expected, your actual result,
evidence and notes. Copy it into Jira or Linear. One-click issue creation waits on a write
connection — until then, copy is the honest path.

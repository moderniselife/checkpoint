# Working a plan

**What:** everything you do after the plan arrives — proving it, recording it, refining it.
**Why:** a plan is a work surface, not a document. Ticks, verdicts, notes and evidence are the work.

## Verdicts, not just ticks

Each task has an outcome: **To do**, **Pass**, **Fail** (with what actually happened) or
**Blocked** (with why). Click the circle to pass; the ⋯ menu sets Fail/Blocked with detail.
The header counts passes on its rings and calls out failures and blocks.

**When:** fail the moment something misbehaves — the actual-result you type becomes the bug report later.

## Finding things in a big plan

- **To do / All / Failed / Blocked** filter plus **Smoke** (5-minute top-risk subset) and **P0** lenses.
- **Estimates** (⏱) and header totals size the run; **sample data** blocks copy valid/invalid/boundary inputs.
- **Source links** under each task jump to the ticket, comment or page it came from; the ⓘ button
  explains why the task exists.
- Amber ⚠ flags mark **vague acceptance criteria** with draft questions for the PM/dev; the ⊕ on an
  uncovered criterion drafts the missing task in one click. **Add more edge cases** appends curated
  negative paths without duplicating.

## Notes, evidence, timer

- **Notes** (pencil icon, or `n`): freeform observations per task, included in exports.
- **Evidence** (paperclip): drag screenshots or files onto a task. Thumbnails preview inline;
  Markdown lists them, HTML embeds small images.
- **Timer** (header chip): start/stop time-on-task. It persists across launches, auto-pauses on quit,
  and totals into exports.

## Asking for changes

- **Chat tab**: ask follow-ups ("what about admins?"). Answers stay in the thread; **Update plan
  from this** folds an answer back into the plan with ticks intact.
- **Regenerate** buttons redo just tasks, acceptance criteria or edge cases.
- Chat and regen use the same ID-preserving merge as re-runs.

## Keyboard and mini panel

Click the task list, then **j/k** move, **space** ticks, **f** fails, **b** blocks, **n** notes.
The toolbar **pop-out** opens a floating always-on-top checklist that ticks live while you test
in a browser — same store, no sync step.

## Bug reports

**Report bug…** on a failed task opens a pre-filled report: steps, expected, your actual result,
evidence and notes. Copy it into Jira or Linear. One-click issue creation waits on a write
connection — until then, copy is the honest path.

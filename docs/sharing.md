# Sharing

**What:** getting plans (and results) out of Checkpoint to people without it.
**Why:** testing is a team sport — Jira comments, PRs and sign-off docs are where plans earn trust.

## Markdown and HTML

The plan toolbar **Export** menu offers:

- **Copy as Markdown** — tasks and criteria as checkboxes, ready for a Jira comment or PR.
  Respects the Smoke lens: with Smoke on, you copy the subset.
- **Save as Markdown** — the full plan with status header, emoji sections and sources.
- **Save as HTML page** — a self-contained Liquid Glass page (light/dark, print-friendly) with
  browser-tickable checkboxes, live rings and embedded evidence images. Send it to anyone.

Exports include verdicts (fail/blocked callouts), notes, evidence lists, estimates, sample data
and testing time.

## Automation skeletons

Dev plans can **Copy Playwright or XCTest skeletons**: test names, steps as comments, AC links,
and explicit TODO markers. They are starting points, deliberately unrunnable — fill in selectors
and assertions in your repo.

**When:** the moment a manual plan proves valuable and deserves to live in CI.

## Bug reports

From any failed task, **Report bug…** produces a pre-filled report — steps, expected, actual,
evidence, notes — to copy into Jira or Linear. See [Working a plan](working-a-plan.md).

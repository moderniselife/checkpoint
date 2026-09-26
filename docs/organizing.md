# Organizing

**What:** keeping tens or hundreds of plans findable: folders, filters, and batch workflows.
**Why:** plans rot into a pile exactly when you need last sprint's evidence.

## Folders and smart folders

- **Folders** nest to any depth with colours. Drag plans onto them (or right-click → Move To);
  deleting a folder moves its contents up. New plans land in the folder you're viewing.
- **Smart folders** are live rules — label, component, fix version, or epic/parent — that fill
  themselves as matching plans arrive, with known-value suggestions while editing.
  **Convert to folder** freezes the current membership into a static folder.
- **Why metadata matters:** smart rules read ticket labels/components/fix versions recorded at
  generation time. Plans made before this feature (or by old runs) lack it — re-run to fill it in.

## Finding plans

- **Search** matches key, title, folder and tags. The filter menu in the *Test plans* header
  sorts (updated, progress, key or AC met) and narrows by mode, tracker, progress and tag.
- **Pin** active plans to the top section; **archive** finished ones out of sight (restorable).
- **Tags** are freeform (`sprint-12`, `needs-qa`), added from the tag line under the plan summary, **More → Tags…**, the sidebar right-click menu or **⌘T**.
- The **Dashboard** (top of the sidebar) shows rolling-7-day stats, an 8-week trend and everything
  in progress — computed from last-touched times, no setup.

## Reminders

Set **tomorrow / in a week** (or clear) from the plan toolbar's **More** (⋯) menu. You get a morning notification on
the due day plus an overdue badge in the sidebar. Permission is asked only the first time you set
one; saying no keeps dates and badges, just no banners. Finishing a plan retires its reminder.

## Batch work

- **Plan several tickets** (**+** in the *Test plans* header), from whichever trackers are connected:
  - **Jira**: any JQL, e.g. `sprint in openSprints()`.
  - **Linear**: team, current cycle, project, state, assigned to me, and search words.
  - **Custom tracker**: one of the server's own search or list tools, with your search text.
  - **Epic children** (Jira or Linear), or a **pasted list** with the tracker to look them up in.

  Each issue gets its own plan in a new folder, run sequentially with progress, cancel, and an
  error summary at the end.
- **Plan each child** (ticket panel): same engine, pre-filled from the epic's children.
- **Regression suites** (folder page → **Build regression suite**): merge a folder's plans into one deduplicated
  run with local ticks and Markdown export. Suites are transient by design — source plans stay canonical.

**When to use what:** import for sprint planning, epic-children for breakdowns, suites for release day.

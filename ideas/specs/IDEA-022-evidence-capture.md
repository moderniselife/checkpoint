# IDEA-022 — Evidence capture

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** M · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: per-task evidence folder under Application Support (10MB cap), thumbnails + attach/remove in TaskRow, Markdown list + HTML base64 embed (2MB cap), cleanup on delete; screen capture itself still via system shortcuts; compiled, needs real-world check.

## Problem
Screenshots/recordings prove a test but live outside the plan.

## Proposal
Attach images/files per task via drag-drop or picker; thumbnails inline, bundled into HTML export, listed in Markdown.

## User flow
1. Drag screenshot onto a task (or Attach button).
2. Thumbnail appears; click to preview, remove if needed.
3. HTML export embeds; Markdown lists filenames.

## Scope
- **In:** per-task attachments (images + files), preview, HTML embed, Markdown list.
- **Out (for now):** screen recording capture inside the app (use ⌘⇧5, then attach).

## Design notes
Attachment strip in expanded `TaskRow`; QuickLook preview.

## Technical notes
Store under App Support `evidence/<planID>/<taskID>/` with refs in `plans.json` (paths, not blobs). Cap size (~10MB/task). Sandbox-safe (user-picked files).

## Risks & open questions
- Storage growth — per-plan folder makes cleanup on delete easy.

## Done when
- [ ] Attach/view/export evidence per task
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

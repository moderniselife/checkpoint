# Ideas

The place to dump every feature idea — big, small, wild — and decide later which ones are worth building.
Nothing here is a commitment. Shipped work lives in [`FEATURES.md`](../FEATURES.md).

## How it works

```
 capture  ──▶  triage  ──▶  spec  ──▶  build  ──▶  ship
 (Inbox)      (Shortlist)  (specs/)   (Building)  (→ FEATURES.md)
```

1. **Capture** — add a row to the **Inbox** at the top of [`IDEAS.md`](IDEAS.md), or run
   `./ideas/idea "One-line idea"` from the repo root. Don't polish; one line is plenty.
2. **Triage** — when you have a moment, move Inbox rows into the right theme and fill in
   **Impact** and **Effort**. Mark the ones you like 👍.
3. **Spec** — for a 👍 idea you actually want to build, copy [`specs/_TEMPLATE.md`](specs/_TEMPLATE.md) to
   `specs/IDEA-###-short-name.md`, fill it in, and set the status to 📐 with a link to the spec.
4. **Build** — set 🚧 while it's in progress.
5. **Ship** — set ✅, add it to `FEATURES.md`, and leave the row here for history.

## Statuses

| | Status | Meaning |
|---|---|---|
| 💭 | Inbox | Just captured, not triaged |
| 👍 | Shortlist | We like it — candidate to build |
| 📐 | Spec'd | Has a spec in `specs/` |
| 🚧 | Building | In progress |
| ✅ | Shipped | Done — see `FEATURES.md` |
| 🧊 | Parked | Good idea, not now |
| ❌ | Rejected | Decided against (keep the row + reason so it isn't re-proposed) |

## Impact / Effort

Rough gut feel, not estimates: **S** / **M** / **L**.
Sweet spot to pick from: **Impact L + Effort S/M**.

## Handy commands

```bash
./ideas/idea "Add a dark-mode toggle to the plan export"   # append to Inbox with the next ID
./ideas/idea --stats                                          # count ideas by status
./ideas/idea --list 👍                                        # list ideas with a status
```

# IDEA-110 — Reminders

**Status:** 🚧 Building · **Impact:** S · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: SavedPlan.dueDate + overdue badges + UNUserNotificationCenter scheduling (9am due-day nudge, permission on first use, cancel on clear/delete/finish, re-arm on launch) in Reminders.swift; compiled, needs real-world check.

## Problem
Plans slip: "test this before Friday" lives in someone's head.

## Proposal
Due dates on plans with a macOS notification; overdue badges in the sidebar.

## User flow
1. Plan header → Set due date.
2. Notification fires; sidebar shows overdue dot.
3. Clear or mark done to dismiss.

## Scope
- **In:** per-plan due date, local notification, overdue UI.
- **Out (for now):** repeating reminders, calendar sync.

## Design notes
Date picker in plan header menu; bell badge on `SidebarRow`.

## Technical notes
`SavedPlan.dueDate: Date?` in `plans.json`; `UNUserNotificationCenter` scheduling (entitlement-free local notifications); overdue = `dueDate < now && progress < 1`.

## Risks & open questions
- Notification permission prompt copy.

## Done when
- [ ] Due dates notify + badge correctly
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

# Idea board

Every idea for Checkpoint, big or small. See [`README.md`](README.md) for how to capture, triage and promote ideas.

**Statuses:** 💭 Inbox · 👍 Shortlist · 📐 Spec'd · 🚧 Building · ✅ Shipped · 🧊 Parked · ❌ Rejected
**Impact / Effort:** S · M · L (gut feel)

---

## 📥 Inbox

New, untriaged ideas land here (`./ideas/idea "…"` appends to this table). Move them into a theme below when triaging.

| ID | Idea | Notes | Impact | Effort | Status |
|---|---|---|---|---|---|

---

## 🧠 Plan quality

| ID | Idea | Notes | Impact | Effort | Status |
|---|---|---|---|---|---|
| IDEA-001 | Smoke-test mode | A 5-minute "does it basically work" subset of the plan | L | S | 💭 |
| IDEA-002 | Risk-based ordering | Tag tasks P0/P1/P2 by blast radius; "run P0 only" filter | L | M | 💭 |
| IDEA-003 | Test data suggestions | Concrete sample inputs per task (valid, invalid, boundary) | M | S | 💭 |
| IDEA-004 | Roles × actions matrix | Auto permission grid for tickets touching access control | M | M | 💭 |
| IDEA-005 | Accessibility pass | Optional VoiceOver/keyboard/contrast checks appended to plans | M | S | 💭 |
| IDEA-006 | Browser / device matrix | Which browsers/devices to cover, based on the ticket and team defaults | M | S | 💭 |
| IDEA-007 | Plan diff on re-run | Highlight tasks/AC added, removed or changed since the last run | L | M | 💭 |
| IDEA-008 | Ambiguity detector | Flag vague AC and draft questions for the PM/dev | L | S | 💭 |
| IDEA-009 | Team house rules | Custom instructions every plan follows ("always check Safari", "use tenant X") | L | S | 💭 |
| IDEA-010 | Plan templates | Per-team or per-ticket-type templates (bug vs feature vs epic) | M | M | 💭 |
| IDEA-011 | Source citations per task | Each task links to the comment / AC / page it came from | L | M | 💭 |
| IDEA-012 | Time estimates | Estimated minutes per task and total for the plan | M | S | 💭 |
| IDEA-013 | Gherkin export | Export tasks as Given/When/Then scenarios | M | S | 💭 |
| IDEA-014 | Automation skeletons | Dev mode: generate Playwright/XCTest stubs from tasks | M | M | 💭 |
| IDEA-015 | Regression suite builder | Combine several plans into one deduplicated regression run | L | L | 💭 |
| IDEA-016 | Coverage-gap suggestions | For uncovered AC, propose the missing task in one click | M | S | 💭 |
| IDEA-017 | Negative-path booster | Button to "add more edge cases" to an existing plan | M | S | 💭 |

## ✅ Test execution

| ID | Idea | Notes | Impact | Effort | Status |
|---|---|---|---|---|---|
| IDEA-020 | Pass / Fail / Blocked states | Beyond done/not-done; blocked needs a reason | L | S | 💭 |
| IDEA-021 | Notes per task | Freeform notes while testing, included in exports | M | S | 💭 |
| IDEA-022 | Evidence capture | Attach screenshots/recordings to tasks (drag-drop, ⌘⇧5) | L | M | 💭 |
| IDEA-023 | Test runs | Multiple runs per plan (per environment / per build) with history | L | M | 💭 |
| IDEA-024 | Retest after fix | Re-open only failed tasks as a new run | M | S | 💭 |
| IDEA-025 | Testing timer | Track time spent per plan/run | M | S | 💭 |
| IDEA-026 | Log time to Jira | Opt-in worklog write from the timer (needs a write connection) | M | M | 💭 |
| IDEA-027 | Bug report from failed task | Pre-filled steps/expected/actual + evidence, copy or create | L | M | 💭 |
| IDEA-028 | Floating mini checklist | Always-on-top compact window to tick tasks while testing in a browser | L | M | 💭 |
| IDEA-029 | Keyboard-first testing | j/k to move, space to tick, f to fail, n for note | M | S | 💭 |
| IDEA-030 | Environment picker per run | DEV / STAGING / PROD with URLs from settings | M | S | 💭 |

## 🤝 Sharing & collaboration

| ID | Idea | Notes | Impact | Effort | Status |
|---|---|---|---|---|---|
| IDEA-040 | Post plan as a comment | Jira/Linear comment with the plan (explicit confirm; needs write scope) | L | M | 💭 |
| IDEA-041 | Post results summary | Pass/fail counts + evidence links back to the ticket | L | M | 💭 |
| IDEA-042 | Export PDF / HTML report | Per plan or per folder, for release sign-off | L | M | 💭 |
| IDEA-043 | Folder test report | Rolled-up metrics + per-plan status for a sprint/release | L | M | 💭 |
| IDEA-044 | Share to Slack | Send plan or results to a channel | M | M | 💭 |
| IDEA-045 | Team sync | Share plans/folders via iCloud Drive or a shared folder | M | L | 💭 |
| IDEA-046 | Assign tasks | Split one plan across testers | M | L | 💭 |
| IDEA-047 | Copy as Jira markup / Linear markdown | Tracker-native formatting for pasting | S | S | 💭 |

## 🔌 Integrations

| ID | Idea | Notes | Impact | Effort | Status |
|---|---|---|---|---|---|
| IDEA-060 | PR-aware Dev plans | Read linked GitHub/Bitbucket PRs to see changed files and focus tests | L | M | 💭 |
| IDEA-061 | Figma frames in panel | Show linked Figma designs next to the ticket | M | M | 💭 |
| IDEA-062 | Confluence viewer | Read linked Confluence pages inside the panel | M | M | 💭 |
| IDEA-063 | Jira remote links | Show remote links (PRs, docs) in the panel's Links card | S | S | 💭 |
| IDEA-064 | More trackers | GitHub Issues, Azure DevOps, Shortcut, ClickUp, Asana via MCP | L | L | 💭 |
| IDEA-065 | Bring your own MCP | Add any MCP server (e.g. internal docs) for research | L | M | 💭 |
| IDEA-066 | Test-management export | TestRail / Xray / Zephyr export | M | M | 💭 |
| IDEA-067 | Sentry context | Pull linked Sentry issues into research | S | M | 💭 |
| IDEA-068 | Notion specs | Read linked Notion pages | S | M | 💭 |
| IDEA-069 | Slack thread context | Read Slack threads linked from the ticket | M | M | 💭 |

## 🤖 AI & models

| ID | Idea | Notes | Impact | Effort | Status |
|---|---|---|---|---|---|
| IDEA-080 | Cost readout per plan | Tokens + $ from streamed usage; show in research log | M | S | 💭 |
| IDEA-081 | Cost estimate before run | Rough estimate based on ticket size / epic children | S | M | 💭 |
| IDEA-082 | Quick vs deep plans | Fast plan on a cheaper model/effort; deep plan on the best model | L | S | 💭 |
| IDEA-083 | Chat with the ticket | Ask follow-ups ("what about admins?") and refine the plan | L | M | 💭 |
| IDEA-084 | Regenerate one section | Redo just tasks / AC / edge cases | M | S | 💭 |
| IDEA-085 | Research cache | Reuse fetched tickets across plans (epics share children) | M | M | 💭 |
| IDEA-086 | "Why this task?" | Explain a task's reasoning and source on demand | M | S | 💭 |
| IDEA-087 | Plan-quality evals | Rubric + sample tickets to measure prompt changes | L | M | 💭 |
| IDEA-088 | Local model option | Offline planning with a local model for sensitive projects | M | L | 💭 |

## 🗂 Organisation

| ID | Idea | Notes | Impact | Effort | Status |
|---|---|---|---|---|---|
| IDEA-100 | Search & filter plans | By key, title, folder, mode, tracker, progress | L | S | 👍 |
| IDEA-101 | Smart folders | Auto-group by sprint, epic, label or fix version | L | M | 💭 |
| IDEA-102 | Tags | Freeform tags on plans | S | S | 💭 |
| IDEA-103 | Pin / favourite | Keep active plans at the top | S | S | 💭 |
| IDEA-104 | Archive | Hide finished plans without deleting | M | S | 💭 |
| IDEA-105 | Sort options | By updated, progress, key, AC met | S | S | 💭 |
| IDEA-106 | Import a sprint | Pull every ticket in the current sprint → one plan each, into a folder | L | M | 💭 |
| IDEA-107 | Batch from JQL / Linear view | Plan everything matching a query | L | M | 💭 |
| IDEA-108 | Bulk-analyze epic children | Separate plans for each child, auto-filed in a folder | M | M | 👍 |
| IDEA-109 | Testing dashboard | Tested this week, AC-met trend, plans in progress | M | M | 💭 |
| IDEA-110 | Reminders | "Test this before Friday" due dates with notifications | S | S | 💭 |

## ✨ Mac experience

| ID | Idea | Notes | Impact | Effort | Status |
|---|---|---|---|---|---|
| IDEA-120 | Command palette (⌘K) | Jump to plans, run actions, analyze a key | L | M | 💭 |
| IDEA-121 | Notify when a plan is ready | Big epics take minutes — ping when done | M | S | 💭 |
| IDEA-122 | Menu-bar quick analyze | Global shortcut → paste key → plan | M | M | 👍 |
| IDEA-123 | Shortcuts / App Intents | "Analyze PROJ-123 in QA mode" from Shortcuts and Spotlight | M | M | 💭 |
| IDEA-124 | Safari share extension | Analyze the Jira/Linear page you're looking at | L | M | 💭 |
| IDEA-125 | Desktop widget | Testing progress for the current folder | S | M | 💭 |
| IDEA-126 | Icon Composer glass icon | Layered `.icon` with live light/dark/tinted modes | S | S | 👍 |
| IDEA-127 | Onboarding flow | First-run walkthrough: key → connect → sample ticket | L | M | 💭 |
| IDEA-128 | Accessibility labels | Full VoiceOver pass on custom controls | M | S | 💭 |
| IDEA-129 | Localisation | Translate UI (plans can already follow the ticket language) | S | M | 💭 |
| IDEA-130 | Custom accent / tint | Pick the glass tint and accent colour | S | S | 💭 |

## 📦 Platform & distribution

| ID | Idea | Notes | Impact | Effort | Status |
|---|---|---|---|---|---|
| IDEA-140 | Sparkle auto-update | Appcast generated from GitHub Releases (needs Developer ID) | L | M | 👍 |
| IDEA-141 | Homebrew cask | `brew install --cask checkpoint` | M | S | 💭 |
| IDEA-142 | CLI | `checkpoint plan PROJ-123 --qa > plan.md` for scripts/CI | M | M | 💭 |
| IDEA-143 | MCP server mode | Expose plans to Claude Code / Cursor / other agents | M | M | 💭 |
| IDEA-144 | iPhone / iPad companion | Tick tasks while testing on a device | M | L | 💭 |
| IDEA-145 | Mac App Store build | Wider reach; needs App Store review | S | L | 🧊 |
| IDEA-146 | Opt-in crash reporting | Privacy-preserving, off by default | S | M | 💭 |
| IDEA-147 | Settings sync | Sync non-secret settings via iCloud | S | M | 💭 |

## 🛠 Engineering

| ID | Idea | Notes | Impact | Effort | Status |
|---|---|---|---|---|---|
| IDEA-160 | Unit test target | ADF converter, Linear parser, SSE assembly, folder logic | L | M | 👍 |
| IDEA-161 | UI tests | Smoke tests for analyze → plan → tick | M | M | 💭 |
| IDEA-162 | Fixture-based MCP mocks | Record real MCP responses for offline tests | M | M | 💭 |
| IDEA-163 | Encrypted plan storage | Encrypt plans.json at rest | S | S | 💭 |
| IDEA-164 | Fetch full comment threads | Paginate comments when Jira truncates | S | S | 💭 |
| IDEA-165 | Structured logging / debug panel | Inspect MCP calls and API errors in-app | M | S | 💭 |

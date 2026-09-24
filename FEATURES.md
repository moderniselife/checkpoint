# Checkpoint — Feature Tracker & Support Guide

The single place for what Checkpoint does, where each feature lives in the code, how well it's been
verified, what's known to be rough, and how to fix things when they break.

**Last updated:** 2026-09-25 · **Latest release:** 0.3.0 — plan export (Markdown / HTML), epic child issues, MIT license

---

## Status legend

| Status | Meaning |
|---|---|
| ✅ **Verified** | Exercised end-to-end in the running app, or against the real service/data |
| 🧪 **Partly verified** | Core logic tested (harness, real API data, or fixtures), but not clicked through in the app |
| 🔍 **Needs real-world check** | Built and compiles, but depends on something we haven't been able to observe yet |
| 🐞 **Known issue** | Works with a caveat — see *Known limitations* |
| 💡 **Backlog** | Idea / not built |

> Everything that shipped in **0.1.0** has been tested by the maintainer (✅). Work added in **0.2.0–0.3.0** is 🧪 — logic
> tested with harnesses and fixture servers — until someone runs it for real. Promote a row to ✅ once seen working.

---

## 1. Feature tracker

### 1.1 Test plan generation

| Feature | Status | Where | How to verify |
|---|---|---|---|
| Analyze a ticket key or pasted Jira/Linear link | ✅ | `TicketInputBar.swift`, `PlanStore.analyze` | Enter `PROJ-123`, ⌘↩ |
| Agent loop: Claude researches via MCP tools, parallel tool calls | ✅ | `PlanGenerator.swift` | Watch research feed open multiple tickets at once |
| Follows comments, epic children, parent, links, Confluence/Linear docs | ✅ | `PlanGenerator.systemPrompt` | Analyze an epic (e.g. `PROJ-100`) → children appear in feed |
| Schema-constrained plan output (`output_config.format`) | ✅ | `TestPlan.jsonSchema` | Plans always decode; no "couldn't read plan" errors |
| Read-only tool allowlist (Jira) | ✅ | `PlanGenerator.isReadOnly` | Only `get*`/`search*`/`fetch`/`lookup*`/`list*` exposed |
| Streaming responses (SSE) with message reassembly | ✅ | `ClaudeClient.streamMessage` | Fixture-tested (thinking + signature, split tool JSON, text); watch a live run |
| Prompt caching, server-side refusal fallbacks (`fallbacks: "default"`) | ✅ | `PlanGenerator.run` | Cache hits visible in API usage; fallback only on refusals |
| Model + effort picker | ✅ | Settings → Anthropic | Change model, re-run |
| Re-run keeps ticked tasks / met criteria that still exist | ✅ | `PlanStore.analyze` | Tick, re-run, ticks remain |
| Copy as Markdown (tasks + AC checkboxes) | ✅ | `PlanExporter.markdown` | Toolbar → Export → Copy as Markdown |
| Save as Markdown (`.md`) with status header, emoji sections, scenarios, sources | 🧪 | `PlanExporter.markdown` | Export → Save as Markdown… |
| Save as HTML page — Liquid Glass, light/dark, print, browser-tickable with live rings | 🧪 | `PlanExporter.html` | Export → Save as HTML Page… (rendered in Chrome light + dark) |

### 1.2 Research visibility

| Feature | Status | Where | How to verify |
|---|---|---|---|
| Live research feed (status, thoughts, tool calls) | ✅ | `ProgressFeedView.swift` | Any analysis |
| Live status card: phase, elapsed timer, progress bar, counts | ✅ | `LiveStatusCard`, `PlanStore.phase` | Analyze an epic; bar fills while reading/writing |
| Tool chips: pending spinner → ✓ / ⚠︎, grouped per batch | ✅ | `FeedRow`, `PlanStore.record` | Chips flip to ticks as tickets return |
| Streaming thinking (updates in place, pulsing icon) | ✅ | `PlanStore.record(.thinking)` | Thought text grows while Claude thinks |
| Expand / collapse thoughts | ✅ | `FeedRow` | Click the chevron |
| Research log saved with each plan + duration | ✅ | `SavedPlan.research` | Toolbar **Plan \| Research** → Research |
| Click a ticket chip to open it in the panel | ✅ | `FeedRow` | Click "Opened ticket DED-…" |

### 1.3 Working the plan

| Feature | Status | Where | How to verify |
|---|---|---|---|
| Tickable test tasks, grouped per ticket for epics | ✅ | `PlanView.TaskRow` | Tick tasks; ring updates |
| To do / All filter | ✅ | `PlanView` | Segmented control |
| Acceptance criteria as checkboxes (met state) | ✅ | `CriterionRow`, `PlanStore.toggleCriterion` | Click a seal → green + strikethrough |
| AC coverage hints + legend | ✅ | `CriteriaLegend` | Orange ⚠︎ = no task covers it |
| Two metrics: tested ring + AC-met ring | ✅ | `MetricRing` | Plan header |
| Priority dots, area chips, "covers AC…" | ✅ | `TaskRow` | — |
| Before you start / edge cases / open questions / sources | ✅ | `PlanView` | — |

### 1.4 Dev vs QA mode

| Feature | Status | Where | How to verify |
|---|---|---|---|
| Dev / QA toggle in input bar (⌘⇧M), default in Settings | ✅ | `TicketInputBar.ModeToggle`, `TestMode.swift` | Toggle; badge shows on plan |
| QA prompt: black-box, UI-only, deploy check first, tech-only → open questions | ✅ | `PlanGenerator.qaPlan` | Compare Dev vs QA plan for same ticket |
| Hosted environment setting used by QA plans | ✅ | Settings → Testing | Set URL; QA plan preconditions mention it |
| Dev and QA plans stored side by side; "Run in QA/Dev mode" | ✅ | `SavedPlan.id` | Right-click plan |

### 1.5 Ticket panel (right side)

| Feature | Status | Where | How to verify |
|---|---|---|---|
| Floating Liquid Glass panel, resizable, remembers width | ✅ | `TicketPanel.swift`, `ContentView` | Drag left edge |
| Open from any ticket key, header button, toolbar, ⌘I | ✅ | `TicketKeyButton`, `PlanView` | — |
| **Ticket tabs**: multiple open tickets, switch/close/close others | ✅ | `TicketTabStrip`, `TicketInspector` | Open 3 tickets; tabs above panel |
| ⌃Tab / ⌃⇧Tab cycle tabs; Back = previous tab | ✅ | `TicketInspector.cycle/back` | — |
| Tabs persist across launches; "Open tickets (N)" when hidden | ✅ | `TicketInspector.restoreTabs` | Relaunch |
| Fields grid, time tracking bar, labels, dates | ✅ | `TicketDetailView` | — |
| Description with task lists, tables, code, panels, mentions | ✅ | `MarkdownView`, ADF converter | Open `PROJ-123` |
| **Inline images** in description/comments (ADF → attachment ID) | ✅ | `TicketDetail.MediaResolver`, `InlineImage` | Open a ticket with a screenshot pasted into a comment |
| Attachments grid with previews, full-size viewer | ✅ | `AttachmentsGrid`, `AttachmentLoader` | Needs an API token saved (see limitations) |
| Related: parent / sub-tasks / links (opens as tab) | ✅ | `LinkedRow` | — |
| Epic child issues (JQL `parent = KEY`, paginated) with done / in-progress / to-do filter | 🧪 | `TicketInspector.jiraChildren`, `ChildIssuesView` | Open an epic |
| Comments (newest-first toggle), work log, change history | ✅ | `CommentsList`, `WorklogList`, `HistoryList` | — |
| Comment/worklog avatars (filled by accountId) + initials fallback | ✅ | `TicketDetail.fillAvatars`, `AvatarView` | Comment authors show avatars |
| All other custom fields | ✅ | "All other fields" disclosure | — |
| Clickable external links (PRs, Figma…) | ✅ | `ExternalLinkRow` | Linear issues with link attachments |

### 1.6 Organisation

| Feature | Status | Where | How to verify |
|---|---|---|---|
| Folders nested to any depth, with colours | ✅ | `PlanFolder.swift`, `PlanStore` folders API | Sidebar folder+ button |
| Edit popover (name + colour), new subfolder, delete (contents move up) | ✅ | `FolderEditor` | Right-click folder |
| Cycle-safe folder moves | ✅ | `PlanStore.moveFolder` | Harness-tested |
| Drag & drop plans/folders onto folders or header | ✅ | `itemProvider` + `onDrop` in `SidebarView` | Drag an already-selected plan |
| Nested "Move To" menus | ✅ | `MoveMenu` | Right-click plan |
| Folder overview (breadcrumb, rolled-up rings, subfolder cards) | ✅ | `FolderOverview.swift` | Select a folder |
| New plans land in the selected folder | ✅ | `PlanStore.analyze` | — |

### 1.7 Connections & auth

| Feature | Status | Where | How to verify |
|---|---|---|---|
| Atlassian OAuth 2.1 (DCR + PKCE + loopback `127.0.0.1:33418`) | ✅ | `MCPOAuth.swift`, `LoopbackServer.swift` | Settings → Sign in with Atlassian |
| Atlassian API token (Basic) → `/v2/mcp` | ✅ | `AppSettings.makeMCPClient` | Requires org admin to enable API-token auth |
| Detect bad Atlassian creds (v1 silently hides Jira tools) | ✅ | `MCPClient.authenticatedTools` | — |
| Token refresh + one retry on 401 | ✅ | `MCPOAuth.refresh`, `MCPClient.send` | — |
| Linear OAuth (`read` scope) / API key → `/mcp/readonly` | ✅ | `MCPOAuth.linear`, `AppSettings.makeLinearClient` | Settings → Sign in with Linear |
| Tracker auto-detect from links; default tracker menu for bare keys | ✅ | `Tracker.detect`, `TrackerMenu` | Paste a linear.app link |
| Keys/tokens in Keychain | ✅ | `Keychain.swift` | — |

### 1.8 Look & feel

| Feature | Status | Where | How to verify |
|---|---|---|---|
| Liquid Glass UI (input bar, cards, chips, panel, tabs) | ✅ | throughout | — |
| Thin glass scroll indicators (system scrollers forced off) | ✅ | `GlassScrollIndicator.swift` | "Show scroll bars: Always" → no grey bar |
| App icon (full-bleed, no macOS 26 icon-jail) + in-app logo | ✅ | `Assets.xcassets` | Dock |
| Custom placeholder in ticket field | ✅ | `TicketInputBar` | — |

### 1.8b AI providers

| Feature | Status | Where | How to verify |
|---|---|---|---|
| Anthropic Claude (thinking, schema-enforced plan, fallbacks) | ✅ | `PlanGenerator.runAnthropic` | Default provider |
| OpenAI, Google Gemini, xAI Grok, OpenRouter | 🧪 | `OpenAIChatClient`, `PlanGenerator.runOpenAI` | Fixture-tested end to end (tool call, round-trip, JSON plan); needs a real key per provider |
| Local OpenAI-compatible (Ollama, LM Studio, vLLM, llama.cpp) | 🧪 | same | Fixture-tested; try `http://localhost:11434/v1` |
| Local Anthropic-compatible (LiteLLM, gateways) | 🧪 | `runAnthropic` compatible branch | Fixture-tested end to end |
| Per-provider key/model/base URL, Fetch models, Test | 🧪 | Settings → AI provider | Switch providers; each keeps its setup |
| Strip-and-retry unsupported params (reasoning effort, JSON schema…) | 🧪 | `OpenAIChatClient.stream` | Fixture 400 on `reasoning_effort` recovered |
| Gemini-safe tool schemas | 🧪 | `PlanGenerator.cleanSchema` | Unit-checked |

### 1.8c Scenarios (optional)

| Feature | Status | Where | How to verify |
|---|---|---|---|
| End-to-end scenarios from related tickets | 🧪 | `PlanGenerator.scenarioPrompt`, `ScenarioCard` | Input bar → Scenarios → From related tickets; analyze an epic |
| Scenarios from tickets + codebase (read-only `code_list` / `code_search` / `code_read`) | 🧪 | `CodebaseTools.swift` | Choose a repo folder; fixture-tested end to end |
| Codebase confined to the chosen folder (`..`, absolute paths, symlink escapes refused) | 🧪 | `CodebaseTools.resolve` | Harness-tested |
| Security-scoped, read-only folder bookmark | 🧪 | `AppSettings.chooseCodebase/openCodebase` | Relaunch keeps access |
| Tickable scenario cards, Markdown export, re-run keeps ticks | 🧪 | `PlanView`, `TestPlan.markdown` | — |

### 1.9 Distribution

| Feature | Status | Where | How to verify |
|---|---|---|---|
| Landing page (Liquid Glass, light/dark, responsive, live download link) | 🧪 | `site/index.html` | Previewed locally at desktop + 375px; deploys to https://checkpoint.guide via `.github/workflows/pages.yml` |
| SEO: JSON-LD (SoftwareApplication, WebSite, WebPage, FAQPage), OG/Twitter cards, canonical, sitemap, robots, manifest, 404 | 🧪 | `site/` | Validate with Google Rich Results Test once deployed |
| GitHub Action: tag → universal Release build → DMG + zip + SHA256 → GitHub Release | ✅ | `.github/workflows/release.yml` | v0.1.0 released by CI |
| Developer ID signing + notarization + stapling when secrets are set | 🔍 | same | Add the five secrets, push a tag |
| `./build.sh` — build from source (universal, ad-hoc or `--sign`, `--dmg`/`--zip`, `--install`, `--open`) | ✅ | `build.sh` | Run locally: universal app + zip produced |
| Issue forms (bug, feature, AI provider, tracker, integration), PR template | 🧪 | `.github/` | Open *New issue* on GitHub |
| SECURITY, CONTRIBUTING, CONTRIBUTORS, CODE_OF_CONDUCT, SUPPORT | ✅ | repo root | — |
| Ad-hoc signed fallback when no secrets | ✅ | same | v0.1.0 is ad-hoc signed |

---

## 2. Jira ↔ Linear parity

| Capability | Jira | Linear | Notes |
|---|---|---|---|
| Test plans (Dev + QA) | ✅ | ✅ | Same generator; Linear prompt adds Linear-specific research hints |
| Research feed + log + streaming progress | ✅ | ✅ | Tracker-agnostic |
| Ticket panel | ✅ | ✅ | Linear parser is tolerant because its MCP output shape isn't documented |
| Comments | ✅ | ✅ | `list_comments`, or embedded in the issue |
| Sub-issues / parent / relations | ✅ | ✅ | Falls back to `list_issues(parentId)` |
| Inline images | ✅ | ✅ | Linear: authenticated `uploads.linear.app` |
| Attachments | ✅ | ✅ | Linear: uploads found in markdown |
| External links (PRs, Figma…) | — | ✅ | Linear attachment links |
| Work log / time tracking | ✅ | n/a | Linear has estimates instead (shown in fields) |
| Change history | ✅ | n/a | Not exposed by Linear MCP |
| Read-only guarantee | client allowlist | server-enforced | Linear `/mcp/readonly` + `read` scope |
| Tabs, folders, AC tracking | ✅ | ✅ | Tracker-agnostic |


---

## 3. Known limitations

| # | Area | Limitation | Workaround |
|---|---|---|---|
| L1 | Jira attachments | Image previews use an **Atlassian email + API token** if saved; the OAuth token may not be accepted for attachment downloads | Save an API token in Settings (even if you use OAuth), or click to open in browser |
| L2 | Jira API token | Rejected unless the org admin enables API-token auth for Rovo MCP | Use Sign in with Atlassian |
| L3 | Linear | Output shape undocumented; panel parser is best-effort | Report fields that look wrong |
| L4 | Linear images | OAuth token may not be accepted by `uploads.linear.app` | Use a Linear API key |
| L5 | Research log | Plans created before `091f61b` have no saved log | Re-run the plan |
| L6 | Big epics | Research + writing can take a few minutes at high effort | Lower effort in Settings; progress card shows it's alive |
| L7 | Comments | Panel shows what Jira returns in one call (usually all); very long threads may be truncated | "Open in Jira" |
| L8 | Pasted images in Jira markdown | The markdown format drops/blob-ifies images, so the panel uses ADF instead (the plan generator still reads markdown) | — |
| L10 | Non-Claude providers | Plans are written in two phases (research, then JSON); models without tool calling can't research | Pick a tool-calling model |
| L11 | Local models | Big epics can exceed a small local model's context window | Use a larger-context model, or analyze children individually |
| L12 | Scenarios | Tickets-only scenarios depend on how well related tickets describe the flows; codebase mode gives more grounded journeys | Point it at the product repo |
| L9 | App icon | Legacy asset-catalog icon (full-bleed) rather than an Icon Composer `.icon` with live glass layers | Split the logo into layers in Xcode's Icon Composer |

---

## 4. Support & troubleshooting

### Connections
| Symptom | Likely cause | Fix |
|---|---|---|
| "Atlassian rejected your credentials (…)" with API token | Admin hasn't enabled API-token auth, email ≠ token owner, or scoped token | Switch to **Sign in with Atlassian** |
| Sign-in tab shows an error after approving | Org removed `127.0.0.1` from Rovo MCP domain allowlist | Admin adds `http://127.0.0.1:*/**` |
| "Not signed in to Atlassian/Linear" mid-run | Refresh token expired/revoked | Settings → sign out → sign in |
| Test connection OK but analysis says "Connect Jira/Linear" | Bare key routed to the other tracker | Paste the full link, or change the tracker menu in the input bar |

### Plans
| Symptom | Likely cause | Fix |
|---|---|---|
| Looks frozen on an epic | Long research/writing | Watch the status card timer; it's alive if the timer ticks |
| "Claude declined this request" | Safety classifier refusal (fallback also refused) | Try another model in Settings |
| "The plan was cut off (max tokens)" | Very large epic | Lower effort or analyze children individually |
| Plan too technical | Dev mode | Switch to QA (⌘⇧M) |
| Orange ⚠︎ on a criterion | No task covers it (often sign-offs / "verified on DEV") | Verify manually, or ask |

### App
| Symptom | Fix |
|---|---|
| Dock shows blank/old icon | Quit & reopen; `killall Dock` |
| Grey system scrollbar visible | Should be gone since `8912008`; report if seen |
| Drag into a folder does nothing | Use right-click → **Move To**; report it (drag was reworked in `091f61b`) |
| Images show ⚠︎ placeholder | See L1 / L4 |

### Where data lives
- Plans: `~/Library/Containers/com.josephshenton.checkpoint/Data/Library/Application Support/Checkpoint/plans.json`
- Folders: same directory, `folders.json`
- Keys/tokens: macOS Keychain, service `com.josephshenton.checkpoint`
- Preferences (mode, model, open tabs, panel width…): the app's `UserDefaults`

To reset: quit, delete the `Checkpoint` folder above, remove the Keychain items.

---

## 5. Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘L | Focus ticket field |
| ⌘↩ | Analyze |
| ⌘⇧M | Toggle Dev / QA |
| ⌘I | Show / hide ticket details |
| ⌃Tab / ⌃⇧Tab | Next / previous ticket tab |
| Esc | Hide ticket panel (tabs stay open) |
| ⌘, | Settings |

---

## 6. Backlog / ideas

Ideas now live in [`ideas/IDEAS.md`](ideas/IDEAS.md) — a triage board for capturing lots of ideas and
picking the good ones later (`./ideas/idea "…"` to add one). Picked ideas get a spec in `ideas/specs/`.

---

## 7. Changelog

| Date | Commit | Change |
|---|---|---|
| 2026-09-24 | `055658a` | Initial app: Jira key → test plan, Liquid Glass UI, Atlassian MCP (API token) |
| 2026-09-24 | `6fb9c0c` | Atlassian OAuth 2.1 sign-in |
| 2026-09-24 | `3a29b87` | OAuth via loopback redirect (no admin allowlisting needed) |
| 2026-09-24 | `591b6d6` | API tokens use `/v2/mcp` (v1 ignores them) |
| 2026-09-24 | `e856c87` | Ticket side panel with full issue details |
| 2026-09-24 | `a882833` | Inline Jira images, input placeholder, expandable thoughts |
| 2026-09-24 | `959b4a3` | Dev / QA mode |
| 2026-09-24 | `622b320` | Linear support, glass scroll indicators, details button, README |
| 2026-09-24 | `55f31af` | Folders, acceptance-criteria checkboxes, Linear parity pass |
| 2026-09-24 | `8912008` | App icon + logo; system scrollers fully hidden |
| 2026-09-24 | `3a61339` | Full-bleed icon (fixes macOS 26 icon-jail) |
| 2026-09-24 | `091f61b` | Ticket tabs, research log, streaming progress, avatar + drag fixes, AC legend |
| 2026-09-24 | `0de3ca2` | FEATURES.md: tracker, parity, limitations, support, changelog |
| 2026-09-24 | `06fc9ce` | GitHub Actions release workflow (DMG + zip + checksums, optional notarization) |
| 2026-09-24 | `8fd0695` | Landing page, GitHub Pages deploy, ideas board |
| 2026-09-24 | `001811c` | Landing page SEO: structured data, social cards, sitemap, use cases, FAQ |
| 2026-09-25 | `e0c2179` | Landing page moves to the checkpoint.guide custom domain |
| 2026-09-25 | `9fda0f6` | OpenAI, Gemini, Grok, OpenRouter and local model support |
| 2026-09-25 | `039ea02` | Docs + website for multi-provider support |
| 2026-09-25 | `8f1c78a` | Optional end-to-end scenarios (related tickets or tickets + codebase) |
| 2026-09-25 | `8311efd` | `build.sh` one-command build from source |
| 2026-09-25 | `34d929b` | Issue forms and community health files |
| 2026-09-25 | `6e94039` | Docs: verified 0.1.0 features, scenarios, build script, community |
| 2026-09-25 | `51ecb65` | **Release 0.2.0** — multi-provider AI, scenarios, build script, landing page, community files, new link-preview banner |
| 2026-09-25 | `ad27288` | Epic child issues in the ticket panel |
| 2026-09-25 | `297c31d` | Export plans as Markdown or a styled HTML page |
| 2026-09-25 | `7c2f5cd` | MIT license |
| 2026-09-25 | — | **Release 0.3.0** — export, epic children, MIT license |

---

## 8. Keeping this file current

- Add a row when a feature ships; move 🧪/🔍 → ✅ once seen working in the app.
- Log new problems under **Known limitations** with a workaround.
- Append each commit to the **Changelog**.
- Related docs: [`README.md`](README.md) (overview & setup), [`ideas/`](ideas/README.md) (idea board).

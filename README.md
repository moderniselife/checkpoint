<p align="center">
  <img src="assets/logo-512.png" alt="Checkpoint" width="160">
</p>

<h1 align="center">Checkpoint</h1>

<p align="center"><strong>Paste a ticket. Get a test plan.</strong></p>

Checkpoint is a native app for macOS 26, iPhone and iPad (SwiftUI + Liquid Glass) that reads a Jira or Linear issue —
plus its comments, children, parent, linked issues and specs — and turns it into a focused,
tickable test plan: what changed, what "done" means, and exactly what to click to prove it.
No more opening ten tabs and flipping back and forth.

---

## Features

### Test plans
- **One input** — a key (`PROJ-123`, `ENG-123`) or a pasted Jira/Linear link.
- **Deep research** — Claude follows comments (later ones win), epic children / sub-issues, parent,
  related issues and linked Confluence pages / Linear docs, only as far as they change what to test.
- **The plan**
  - plain-English summary of what changed
  - **Before you start** — environment, tenancy, roles, flags, test data, build/deploy
  - **Acceptance criteria** — quoted from the tickets (or marked *derived*), each showing
    uncovered / pending / verified as you tick tasks
  - **Test tasks** — numbered steps + one observable expected result, grouped per ticket for
    epics, priority and area, tickable and saved
  - edge cases, open questions, and every source it read
- **Acceptance criteria are checkboxes** — click the seal to mark a criterion met. Plans track two
  metrics: tasks tested and AC met (header rings, sidebar, folder roll-ups, Markdown export).
- **Copy as Markdown** for Jira comments / PRs. **Re-run** keeps ticks and met criteria that survive.
- **Live research feed** — see each ticket it opens and expand its reasoning as it works.
- **Quick or Deep**, and a **template** (Bug / Feature / Epic) when the ticket type isn't enough —
  both in the small options menu at the end of the ticket field. **House rules** in Settings ride along
  with every plan.

### Working a plan
- **Verdicts** — pass, fail (with what actually happened) or blocked (with why), from each task's ⋯ menu.
  A failed task turns into a pre-filled **bug report** you can copy.
- **Notes and evidence** — add a note, or drop screenshots and files straight onto a task.
- **Smoke and P0 lenses** — cut a big plan down to the 5-minute top-risk subset, or just the P0s.
  Tasks carry risk badges, time estimates, sample test data and links to the comment or page they came from.
- **Timer** — track time spent testing; it totals into exports.
- **Chat** — ask follow-ups about the plan and fold good answers back in. Regenerate just the tasks,
  acceptance criteria or edge cases; ticks survive.
- **Keyboard** — j/k to move, space to pass, f/b/n for fail, blocked and note.
- **Mini checklist** — a small always-on-top panel to tick through while you test in a browser.
- **Automation skeletons** — copy a Playwright or XCTest starting point from the Export menu.

See [docs/working-a-plan.md](docs/working-a-plan.md) for the details.

### iPhone, iPad and sync
Checkpoint runs on iPhone and iPad with the same plans and features: analyze a ticket on your phone,
tick through it on a test device, attach photos straight from the camera, share plans from the share sheet.
- **Sync folder**: keep your plans in a folder in iCloud Drive (or Dropbox, or a network share), and every
  device that opens it stays in step. It's free and works in any build.
- **iCloud**: automatic sync through your iCloud account, coming with the App Store version.
- API keys and sign-ins never sync; they stay in each device's Keychain.

See [docs/sync.md](docs/sync.md).

### A proper welcome
First launch walks you through how you test, your AI provider (with a live key test), Jira and Linear
sign-in, and sync, all skippable, then offers a **guided tour**: a spotlight over the real UI explaining
each part, using a sample plan if you don't have one yet. The **Help** menu has the tour, guides, a
keyboard-shortcuts window and a link to report issues.

### Folders and finding things
Organise plans into folders nested to any depth, each with a colour.
- **＋** in the sidebar header makes a folder, a **smart folder** (live rule: label, component,
  fix version or epic) or plans a whole sprint, epic or pasted list in one go. Right-click a folder for *New Subfolder*, *Edit*, *Move*, *Delete*
  (deleting moves its contents up a level).
- **Drag** plans and folders onto folders, or onto the *Test plans* header to move them to the top level.
  Right-click → **Move To** gives a nested menu too.
- Folders show rolled-up tested counts; selecting one opens an overview with breadcrumb, tested / AC-met
  rings, subfolders and plans.
- New plans land in the folder you're looking at.
- **Search, sort and filter** the sidebar; **pin**, **tag**, **archive** and set **reminders** on plans.
- The **Dashboard** shows the last week of testing, an 8-week trend and everything in progress.
- Build a deduplicated **regression suite** from a folder's plans for release day.

See [docs/organizing.md](docs/organizing.md).

### Dev vs QA mode
Toggle in the input bar (**⌘⇧M**); default in Settings.

| | Dev | QA |
|---|---|---|
| Audience | the developer verifying their own change | a tester on the **hosted** app |
| Language | may reference branches, commits, APIs, logs, tests | UI names only — no code, repos or local setup |
| First task | setup | confirm the fix is actually deployed |
| Technical-only checks | tasks | open questions ("confirm with the dev") |

Set **Hosted environment** (e.g. `https://app.dev.example.com (DEV)`) and QA plans aim at it.
Dev and QA plans for the same ticket live side by side — right-click → **Run in QA/Dev mode**.

### Export & share
**Export** in the plan toolbar: copy Markdown, save a `.md`, or save a self-contained **HTML page** in the
Checkpoint Liquid Glass style — light/dark, print-friendly, with checkboxes you can tick in the browser and live
progress rings. Great for Jira comments, PRs, sign-off docs or sending to someone without the app.

### Scenarios (optional)
Turn on **Scenarios** in the input bar to add 3–6 end-to-end user journeys to each plan — realistic flows that start
before the changed screen and carry on through neighbouring features, with a role, goal, steps and end result.
- **From related tickets** — uses your tracker only: same epic/parent, components, labels and nearby tickets.
- **Tickets + codebase** — also reads a local repo you choose (read-only, confined to that folder) to trace real
  screens, routes and permission checks. QA plans still describe everything in UI terms.

### Ticket panel
Click any ticket key (feed, plan header, task groups, AC sources, source chips) or hit
**Ticket details / ⌘I** to slide in a resizable Liquid Glass panel with *everything*:
fields, time tracking, description (task lists, tables, code, panels), **inline images**, **epic child issues**,
attachments with previews, parent / sub-issues / links (navigable, with Back),
comments, work log, change history and every other custom field.

### Jira and Linear, same features
Plans, Dev/QA mode, the research feed, the ticket panel, folders and AC tracking work identically for both.
The panel adapts to each tracker: Jira adds work log, history and time tracking; Linear shows its
project, cycle, estimate, sub-issues, relations, link attachments (PRs, Figma…) and uploaded files.

**Custom MCP servers** (Settings → Custom Servers) add anything else that speaks MCP over HTTP —
as a tracker of its own, or as an extra read-only research source whose findings get cited in tasks.

### Read-only by design
Checkpoint can never change your tickets:
- **Jira** — only `get*` / `search*` / `fetch` / `lookup*` / `list*` MCP tools are exposed to Claude.
- **Linear** — uses Linear's `/mcp/readonly` endpoint with a `read` OAuth scope, enforced by Linear.
- **Custom servers** — only read-only tools, by the same name rules as Jira.

---

## Install

**Download** the latest DMG from [Releases](https://github.com/moderniselife/checkpoint/releases/latest) (or
[checkpoint.guide](https://checkpoint.guide)) and drag Checkpoint to Applications. Requires macOS 26+.

### Build from source

Requirements: macOS 26+, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (the script offers to install it).

```bash
./build.sh
```

For iPhone and iPad, `./build.sh --platform ios` makes an unsigned `dist/Checkpoint-<version>-iOS.ipa`
(install it with AltStore or Sideloadly), and `--platform all` builds both. To run it straight on your
device instead: `xcodegen generate`, open `Checkpoint.xcodeproj`, choose the **CheckpointMobile** scheme and
your signing team (iOS 26+). Releases include the `.ipa` next to the Mac DMG.

The Mac script builds a universal Release app to **`dist/Checkpoint.app`** (ad-hoc signed). Options:

| Flag | Does |
|---|---|
| `--install` | Copy to `/Applications` |
| `--open` | Launch when done |
| `--dmg` / `--zip` | Also package `dist/Checkpoint-<version>.dmg` / `.zip` |
| `--sign "Developer ID Application: …"` | Sign with your own identity |
| `--version 0.2.0` | Set the marketing version |
| `--debug` | Faster Debug build (native arch only) |
| `--platform macos\|ios\|all` | Which app to build (default `macos`) |

```bash
./build.sh --install --open
```

Working on the code? `xcodegen generate && open Checkpoint.xcodeproj`, then ⌘R. The `.xcodeproj` is generated from
`project.yml` — change `DEVELOPMENT_TEAM` there to your own team for signed Debug builds.

## Setup

Open **Settings (⌘,)**:

1. **AI provider** — pick one, add its key, then **Fetch models** and **Test**:

   | Provider | Key | Notes |
   |---|---|---|
   | Anthropic Claude | <https://platform.claude.com/settings/keys> | Adaptive thinking, schema-enforced plans, refusal fallbacks |
   | OpenAI | <https://platform.openai.com/api-keys> | Any model with tool calling |
   | Google Gemini | <https://aistudio.google.com/apikey> | Via Gemini's OpenAI-compatible endpoint |
   | xAI Grok | <https://console.x.ai> | |
   | OpenRouter | <https://openrouter.ai/keys> | Hundreds of models, one key |
   | Local — OpenAI-compatible | optional | Ollama (`http://localhost:11434/v1`), LM Studio, vLLM, llama.cpp |
   | Local — Anthropic-compatible | optional | LiteLLM or any Messages-API gateway |

   Local models need tool calling and a big context window — large epics can overflow small models.
2. **Testing** — default mode and your hosted environment.
3. **Atlassian (Rovo MCP)** — Jira site (e.g. `yourco.atlassian.net`), then either
   - **Sign in with Atlassian** (OAuth, recommended), or
   - **API token** — email + token from <https://id.atlassian.com/manage-profile/security/api-tokens>
     (your org admin must allow API-token auth for the Rovo MCP server).
4. **Linear (official MCP)** — **Sign in with Linear** (OAuth) or a Linear API key.
5. **Test connection** on each.

Connect one or both trackers. Pasted links pick the tracker automatically; with both connected,
bare keys go to the tracker chosen in the input bar menu.

> **Attachment previews in Jira** load with your Atlassian email + API token if saved (even when
> you sign in with OAuth), otherwise with the OAuth token.

---

## How it works

```
Ticket key ─▶ PlanGenerator ──(Claude · OpenAI · Gemini · Grok · OpenRouter · local)──▶ TestPlan
                  │   ▲
      tool calls  ▼   │ results
                MCPClient ──(Streamable HTTP)──▶ Atlassian Rovo MCP  /  Linear MCP (read-only)
```

| Piece | What it does |
|---|---|
| `MCPClient` | Minimal MCP Streamable-HTTP client: JSON-RPC over POST, SSE responses, `Mcp-Session-Id`, per-request auth with one refresh-and-retry on 401. |
| `MCPOAuth` | OAuth 2.1 for Atlassian and Linear: dynamic client registration, PKCE, loopback redirect on `127.0.0.1:33418` (pre-approved by Atlassian's domain allowlist), Keychain tokens with coalesced auto-refresh. |
| `PlanGenerator` | Agent loop with two engines. **Anthropic Messages** (Claude + compatible servers): streaming, adaptive thinking, prompt caching, refusal fallbacks and a schema-constrained final turn on native Claude. **OpenAI Chat Completions** (OpenAI, Gemini, Grok, OpenRouter, local): research with tools, then a final JSON-schema call. Prompts vary by tracker and Dev/QA mode. |
| `OpenAIChatClient` | Streaming Chat Completions with tool-call/reasoning reassembly, `/models` listing, strip-and-retry for unsupported parameters. |
| `TicketInspector` | Loads full issues for the panel — Jira as ADF + `renderedFields` (so inline images map to attachment IDs), Linear via `get_issue` + `list_comments` with argument names read from the tool schemas. |
| `CodebaseTools` | Read-only `code_list` / `code_search` / `code_read` for scenario research, confined to the chosen folder. |
| `PlanStore` | Plan history + tick state in the app's Application Support container. |

**Endpoints**
- Jira OAuth → `https://mcp.atlassian.com/v1/mcp`
- Jira API token → `https://mcp.atlassian.com/v2/mcp` (v1 silently ignores API tokens)
- Linear → `https://mcp.linear.app/mcp/readonly`

Keys and tokens live in the macOS Keychain. The app is sandboxed (network client, a loopback
listener for sign-in only, and read-only access to a codebase folder you choose for scenarios); App Transport Security allows plain HTTP only for local networking (local model servers).

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘L | Focus the ticket field |
| ⌘↩ | Analyze |
| ⌘⇧M | Toggle Dev / QA |
| ⌘I | Show / hide ticket details |
| Esc | Close the ticket panel |
| ⌘, | Settings |

---

## Project layout

```
Checkpoint/
  App/        CheckpointApp — scenes and environment
  Models/     TestPlan, TicketDetail (+ ADF→markdown), LinearParsing, PlanFolder, LLMProvider, ScenarioMode, TestMode, Tracker, JSONValue
  Services/   MCPClient, MCPOAuth, LoopbackServer, ClaudeClient, OpenAIChatClient, PlanGenerator, CodebaseTools,
              PlanStore, TicketInspector (+ AttachmentLoader), AppSettings, Keychain
  Views/      ContentView, TicketInputBar, SidebarView, FolderOverview, ProgressFeedView, PlanView,
              TicketPanel, MarkdownView, GlassScrollIndicator, SettingsView
  Assets.xcassets  AppIcon (generated from assets/logo.png on Apple's icon grid) + Logo
assets/       logo.png (master), logo-512.png (README)
ideas/        Idea board (IDEAS.md), specs/, and the `idea` capture script
site/         Landing page (GitHub Pages)
build.sh      One-command build from source → dist/Checkpoint.app
project.yml   XcodeGen spec (the .xcodeproj is generated, not committed)
```

## Releases

Pushing a tag builds and publishes a GitHub Release (`.github/workflows/release.yml`):

```bash
git tag v0.2.0 && git push origin v0.2.0
```

Or run **Actions → Release → Run workflow** and enter a version.

Each release has a universal (Apple Silicon + Intel) `Checkpoint-<version>.dmg`, a `.zip`, and
`SHA256SUMS.txt`. Builds are **ad-hoc signed** unless these repository secrets are set, in which case
they're Developer ID signed, notarized and stapled:

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE_P12` | `base64 -i DeveloperID.p12 \| pbcopy` of your *Developer ID Application* certificate |
| `MACOS_CERTIFICATE_PASSWORD` | the .p12 password |
| `APPLE_TEAM_ID` | your 10-character team ID |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_APP_PASSWORD` | an app-specific password from appleid.apple.com |

Ad-hoc builds: right-click → **Open** the first time, or `xattr -dr com.apple.quarantine /Applications/Checkpoint.app`.

## Landing page

`site/` is a self-contained landing page (no build step), live at **https://checkpoint.guide**.
It deploys to GitHub Pages on every push that touches `site/` (Settings → Pages → Source: GitHub Actions,
custom domain `checkpoint.guide`, DNS on Cloudflare). Preview locally:

```bash
cd site && python3 -m http.server 8000
```

## Ideas

Feature ideas are captured and triaged on the board in [`ideas/IDEAS.md`](ideas/IDEAS.md):

```bash
./ideas/idea "Your idea"      # add to the Inbox
./ideas/idea --stats          # counts by status
```

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Use the
[issue forms](https://github.com/moderniselife/checkpoint/issues/new/choose) for bugs, features, AI provider and tracker
requests; report security issues privately per [SECURITY.md](SECURITY.md). Everyone who helps is listed in
[CONTRIBUTORS.md](CONTRIBUTORS.md), and we follow a [Code of Conduct](CODE_OF_CONDUCT.md).

## Feature tracker

See [`FEATURES.md`](FEATURES.md) for every feature, its verification status, Jira↔Linear parity,
known limitations, support guide, backlog and changelog.

## License

[MIT](LICENSE) © 2026 Joseph Shenton

## Troubleshooting

- **"Atlassian rejected your credentials"** with an API token → your admin hasn't enabled API-token
  auth for Rovo MCP, the email doesn't match the token's account, or the token is scoped. Try OAuth.
- **Sign-in browser tab errors** → your admin may have removed the default `127.0.0.1` domain from
  the Rovo MCP allowlist; ask them to add `http://127.0.0.1:*/**`.
- **Images show a ⚠️ placeholder** → save an Atlassian API token (Jira) or use a Linear API key.
- **Plan feels too technical** → switch to QA mode.

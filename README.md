<p align="center">
  <img src="assets/logo-512.png" alt="Checkpoint" width="160">
</p>

<h1 align="center">Checkpoint</h1>

<p align="center"><strong>Paste a ticket. Get a test plan.</strong></p>

Checkpoint is a native macOS 26 app (SwiftUI + Liquid Glass) that reads a Jira or Linear issue —
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

### Folders
Organise plans into folders nested to any depth, each with a colour.
- **＋ folder** button in the sidebar header; right-click a folder for *New Subfolder*, *Edit*, *Move*, *Delete*
  (deleting moves its contents up a level).
- **Drag** plans and folders onto folders, or onto the *Test plans* header to move them to the top level.
  Right-click → **Move To** gives a nested menu too.
- Folders show rolled-up tested counts; selecting one opens an overview with breadcrumb, tested / AC-met
  rings, subfolders and plans.
- New plans land in the folder you're looking at.

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

### Ticket panel
Click any ticket key (feed, plan header, task groups, AC sources, source chips) or hit
**Ticket details / ⌘I** to slide in a resizable Liquid Glass panel with *everything*:
fields, time tracking, description (task lists, tables, code, panels), **inline images**,
attachments with previews, parent / sub-issues / links (navigable, with Back),
comments, work log, change history and every other custom field.

### Jira and Linear, same features
Plans, Dev/QA mode, the research feed, the ticket panel, folders and AC tracking work identically for both.
The panel adapts to each tracker: Jira adds work log, history and time tracking; Linear shows its
project, cycle, estimate, sub-issues, relations, link attachments (PRs, Figma…) and uploaded files.

### Read-only by design
Checkpoint can never change your tickets:
- **Jira** — only `get*` / `search*` / `fetch` / `lookup*` / `list*` MCP tools are exposed to Claude.
- **Linear** — uses Linear's `/mcp/readonly` endpoint with a `read` OAuth scope, enforced by Linear.

---

## Setup

Requirements: macOS 26+, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
```

```bash
xcodegen generate && open Checkpoint.xcodeproj
```

Build & run (⌘R). Signing uses the team in `project.yml` (`DEVELOPMENT_TEAM`) — change it to yours.

Then open **Settings (⌘,)**:

1. **Anthropic** — API key from <https://platform.claude.com/settings/keys>; pick model and effort.
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
Ticket key ─▶ PlanGenerator ──(Messages API, adaptive thinking, structured output)──▶ TestPlan
                  │   ▲
      tool calls  ▼   │ results
                MCPClient ──(Streamable HTTP)──▶ Atlassian Rovo MCP  /  Linear MCP (read-only)
```

| Piece | What it does |
|---|---|
| `MCPClient` | Minimal MCP Streamable-HTTP client: JSON-RPC over POST, SSE responses, `Mcp-Session-Id`, per-request auth with one refresh-and-retry on 401. |
| `MCPOAuth` | OAuth 2.1 for Atlassian and Linear: dynamic client registration, PKCE, loopback redirect on `127.0.0.1:33418` (pre-approved by Atlassian's domain allowlist), Keychain tokens with coalesced auto-refresh. |
| `PlanGenerator` | Agent loop on the Claude Messages API (raw HTTP — no Swift SDK). Parallel tool calls, prompt caching, server-side refusal fallbacks, final turn constrained to the `TestPlan` JSON schema. Prompts vary by tracker and Dev/QA mode. |
| `TicketInspector` | Loads full issues for the panel — Jira as ADF + `renderedFields` (so inline images map to attachment IDs), Linear via `get_issue` + `list_comments` with argument names read from the tool schemas. |
| `PlanStore` | Plan history + tick state in the app's Application Support container. |

**Endpoints**
- Jira OAuth → `https://mcp.atlassian.com/v1/mcp`
- Jira API token → `https://mcp.atlassian.com/v2/mcp` (v1 silently ignores API tokens)
- Linear → `https://mcp.linear.app/mcp/readonly`

Keys and tokens live in the macOS Keychain. The app is sandboxed (network client + a loopback
listener for sign-in only).

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
  Models/     TestPlan, TicketDetail (+ ADF→markdown), LinearParsing, PlanFolder, TestMode, Tracker, JSONValue
  Services/   MCPClient, MCPOAuth, LoopbackServer, ClaudeClient, PlanGenerator,
              PlanStore, TicketInspector (+ AttachmentLoader), AppSettings, Keychain
  Views/      ContentView, TicketInputBar, SidebarView, FolderOverview, ProgressFeedView, PlanView,
              TicketPanel, MarkdownView, GlassScrollIndicator, SettingsView
  Assets.xcassets  AppIcon (generated from assets/logo.png on Apple's icon grid) + Logo
assets/       logo.png (master), logo-512.png (README)
project.yml   XcodeGen spec (the .xcodeproj is generated, not committed)
```

## Troubleshooting

- **"Atlassian rejected your credentials"** with an API token → your admin hasn't enabled API-token
  auth for Rovo MCP, the email doesn't match the token's account, or the token is scoped. Try OAuth.
- **Sign-in browser tab errors** → your admin may have removed the default `127.0.0.1` domain from
  the Rovo MCP allowlist; ask them to add `http://127.0.0.1:*/**`.
- **Images show a ⚠️ placeholder** → save an Atlassian API token (Jira) or use a Linear API key.
- **Plan feels too technical** → switch to QA mode.

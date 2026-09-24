# Checkpoint

A macOS 26 (Liquid Glass) app: paste a Jira key, get a test plan.

Checkpoint connects to the **Atlassian Rovo MCP server**, lets Claude read the ticket plus
its comments, children, parent epic, linked issues and Confluence specs, then produces:

- a plain-English summary of what changed
- **Before you start** — env, tenancy, roles, flags, build to verify on
- **Acceptance criteria** — quoted from tickets (or marked *derived*), each showing whether it's covered/verified
- **Test tasks** — numbered steps + expected result, grouped per ticket, tickable (saved locally)
- edge cases, open questions, and the list of sources it read for you
- Copy as Markdown (paste into a Jira comment / PR)

## Setup

1. `brew install xcodegen` (once)
2. `xcodegen generate && open Checkpoint.xcodeproj` — build & run (⌘R)
3. Settings (⌘,):
   - **Anthropic API key** — https://platform.claude.com/settings/keys
   - **Jira site** (e.g. `yourcompany.atlassian.net`)
   - **Connect with**: *Sign in with Atlassian* (OAuth, default) or *API token* (email + token from https://id.atlassian.com/manage-profile/security/api-tokens)
   - Hit **Test connection** — it should show your name.

OAuth uses dynamic client registration + PKCE against `mcp.atlassian.com`, opens your default
browser, and catches the redirect on `http://127.0.0.1:33418/callback` (falls back to a free port).
Loopback redirects are pre-approved in Atlassian's MCP domain allowlist, so no admin change is
needed — custom schemes like `checkpoint://` would need allowlisting. Tokens refresh automatically
(including once on a mid-run 401).

> API-token auth for the Rovo MCP server must be enabled by your Atlassian org admin.
> With bad credentials Atlassian still answers, but hides the Jira tools — Checkpoint detects this.

## How it works

- `MCPClient` — minimal MCP Streamable-HTTP client (JSON-RPC over POST, SSE responses, `Mcp-Session-Id`), Basic auth.
- `PlanGenerator` — agent loop on the Claude Messages API (raw HTTP). Only **read-only** MCP tools
  (`get*`, `search*`, `fetch`, `lookup*`) are exposed, so it can never edit tickets. Tool calls in a turn
  run in parallel; the final turn is constrained to the `TestPlan` JSON schema via `output_config.format`.
  Adaptive thinking (summaries stream into the progress feed), prompt caching, and server-side refusal fallbacks are on.
- `PlanStore` — history + tick state in `~/Library/Containers/com.josephshenton.checkpoint/.../Application Support/Checkpoint/plans.json`.
- Keys live in the Keychain.

## Dev vs QA mode

Toggle in the input bar (⌘⇧M), default in Settings.

- **Dev** — for the developer verifying their own change: may reference branches, commits, APIs, logs, tests.
- **QA** — black-box plans for testing the *hosted* app: UI names only, no code/branches/local setup,
  starts by confirming the fix is deployed, covers roles/negative/edge/regression, and pushes anything
  only verifiable technically into open questions. Set **Hosted environment** in Settings to aim plans at it.

Dev and QA plans for the same ticket are saved side by side; right-click a plan → "Run in QA/Dev mode".

Shortcuts: ⌘L focus ticket field · ⌘↩ analyze · ⌘⇧M toggle Dev/QA.

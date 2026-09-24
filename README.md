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
   - **Jira site** (e.g. `yourcompany.atlassian.net`), **email**, **Atlassian API token** — https://id.atlassian.com/manage-profile/security/api-tokens
   - Hit **Test connection** — it should show your name.

> API-token auth for the Rovo MCP server must be enabled by your Atlassian org admin.
> With an unauthorised token Atlassian still answers, but hides the Jira tools — Checkpoint detects this.

## How it works

- `MCPClient` — minimal MCP Streamable-HTTP client (JSON-RPC over POST, SSE responses, `Mcp-Session-Id`), Basic auth.
- `PlanGenerator` — agent loop on the Claude Messages API (raw HTTP). Only **read-only** MCP tools
  (`get*`, `search*`, `fetch`, `lookup*`) are exposed, so it can never edit tickets. Tool calls in a turn
  run in parallel; the final turn is constrained to the `TestPlan` JSON schema via `output_config.format`.
  Adaptive thinking (summaries stream into the progress feed), prompt caching, and server-side refusal fallbacks are on.
- `PlanStore` — history + tick state in `~/Library/Containers/com.josephshenton.checkpoint/.../Application Support/Checkpoint/plans.json`.
- Keys live in the Keychain.

Shortcuts: ⌘L focus ticket field · ⌘↩ analyze.

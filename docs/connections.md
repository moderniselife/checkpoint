# Connections

**What:** the two things Checkpoint talks to — models and trackers — and where your secrets live.
**Why:** explicit connections mean no surprises about what can read (or never write) your data.

## AI providers

Settings → AI Provider. Claude, OpenAI, Gemini, Grok, OpenRouter, local OpenAI-compatible servers
(Ollama, LM Studio, vLLM) and Anthropic-compatible gateways (LiteLLM). Each keeps its own key,
model and URL; **Fetch models** lists what's actually available; **Test** proves key + model.

- **Effort** steers reasoning depth where supported — and everywhere caps runaway thinking:
  if a local model yaps instead of acting, Checkpoint cuts the turn off and moves on.
  Lower effort also means a tighter cap.
- Requirements: tool calling, and a big context window for epics (small local models overflow).

## Jira, Linear, custom MCP

- **Jira**: Sign in with Atlassian (OAuth, recommended) or email + API token (needs your org admin
  to allow API-token auth for the Rovo MCP server). **Test connection** lists the server's tools.
- **Linear**: Sign in (read-scope OAuth) or API key, against Linear's read-only endpoint.
- **Custom trackers** (Settings → Custom Servers): any Streamable-HTTP MCP server that holds tickets —
  endpoint plus optional bearer token. Plan from it like Jira or Linear: links containing its **match
  hint** route there, and **Bare keys go to** (or the tracker menu in the ticket field) makes it the
  default. **List tools** shows what it offers with read-only badges; only read-only tools are ever called.
  *Use while researching plans* also lets other plans read from it.

## Research tools

Settings → **Research Tools** (under Intelligence) is for MCP servers that aren't trackers but help write
a better plan: notes in Obsidian, a wiki, or a device cloud like Corellium that can set up the test
environment.

- **What it's for**: a sentence told to the planner, e.g. "Spin up an iPhone 17 on iOS 26 to test on."
- **Tools it may call**: *Read-only* (get/list/search…) by default, or *Chosen tools*, where you tick
  exactly which tools it may call, including ones that act, like creating a device. The planner only acts to
  set up testing, and lists what it set up in the plan's preconditions.
- Turn one off without removing it with *Use while writing plans*.
- **Local stdio servers** can't be launched from the sandboxed app. Expose them over HTTP first with a
  bridge such as `supergateway` or `mcp-proxy`, then add the bridge's URL.

**Why read-only:** Jira and custom trackers expose only get/search/fetch/lookup/list tools to the model;
Linear enforces it server-side. Checkpoint cannot edit your tickets. Only research tools can be given
action tools, and only the ones you tick.

## Secrets and troubleshooting

Keys and tokens live in the macOS **Keychain**; preferences in UserDefaults; plans in
`~/Library/Containers/…/Checkpoint/` (`plans.json`, `folders.json`, `smartFolders.json`,
`evidence/`). To reset: quit, delete that folder, remove the Keychain items.

| Symptom | Likely cause | Fix |
|---|---|---|
| Atlassian rejected credentials (token) | Admin hasn't enabled API-token auth, or email ≠ token owner | Use OAuth sign-in |
| Sign-in tab errors after approving | Org removed loopback from the MCP allowlist | Admin adds `http://127.0.0.1:*/**` |
| Test OK but "Connect tracker" mid-run | Bare key routed to the other tracker | Paste the full link |
| Local model yaps forever | Some local models never stop thinking | Lower effort (tighter cap); it moves on automatically with a feed note |
| Local plan rambles or has no structure | Small models think in the answer and ignore JSON mode | Checkpoint retries once with a strict JSON-only prompt; if that fails, use a larger tool-capable model — the pipeline can't fix model capability |
| Images show ⚠ placeholders | OAuth token refused for attachments | Save an API token (Jira) or use an API key (Linear) |

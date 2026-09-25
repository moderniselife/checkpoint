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
- **Custom MCP** (Settings → Custom Servers): any Streamable-HTTP MCP server — endpoint plus optional
  bearer token. **List tools** shows what it offers with read-only badges. Two jobs:
  - as a *tracker* via match hint (inputs containing it route there), or
  - as a *research source* ("Use for research") whose read-only tools join plan research with citations.

**Why read-only:** Jira exposes only get/search/fetch/lookup/list tools to the model; Linear enforces
it server-side. Checkpoint cannot edit your tickets.

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

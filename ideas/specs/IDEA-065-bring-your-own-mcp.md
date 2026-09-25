# IDEA-065 — Bring your own MCP

**Status:** 🚧 Building'd · **Impact:** L · **Effort:** M · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: per-server "Use for research" toggle; read-only tools appended to planning with owner routing + citation note; compiled, needs real-world check.

## Problem
Research is limited to tracker + codebase; internal docs/specs live elsewhere.

## Proposal
Attach any Streamable-HTTP MCP server as a read-only research source (docs, wiki,3285 specs). Tools listed, read-only filtered, cited in sources.

## User flow
1. Settings → Research sources → Add MCP server (URL + optional token).
2. Test → tools listed with READ badges.
3. Plans cite the source when used.

## Scope
- **In:** generic research servers, read-only filter, citations.
- **Out (for now):** routing tickets to custom trackers (already: `CustomMCPTracker.matchHint`).

## Design notes
Extends the Custom MCP settings UI; source chips in research feed.

## Technical notes
Reuse `MCPClient(endpoint:auth:)` + `PlanGenerator.isReadOnly`; append tools to research phase only (not ticket fetch). Store in `AppSettings` alongside custom trackers with a `researchOnly` flag.

## Risks & open questions
- Prompt bloat — cap tools passed, prefer search/fetch tools.

## Done when
- [ ] Custom server contributes cited research
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

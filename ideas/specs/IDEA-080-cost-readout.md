# IDEA-080 — Cost readout per plan

**Status:** 🚧 Building'd · **Impact:** M · **Effort:** S · **Owner:** —
**Board row:** [`IDEAS.md`](../IDEAS.md)
**Build:** Shipped: LLMUsage capture in both engines (Anthropic response usage, OpenAI stream_options), persisted per plan with provider/model, price table, research-log stat; compiled, needs real-world check.

## Problem
No idea what a plan cost — big epics surprise.

## Proposal
Show tokens + $ per plan in the research log (per-turn usage summed, priced per provider/model table).

## User flow
1. Run a plan → research log footer shows "12k in / 8k out · ≈$0.42".
2. Compare across models/efforts.

## Scope
- **In:** usage capture (both engines), price table, log UI.
- **Out (for now):** pre-run estimates (see IDEA-081).

## Design notes
Footer row in Research tab + plan header tooltip.

## Technical notes
Anthropic: `ClaudeClient` already merges `event["usage"]` into `message["usage"]` — read `response["usage"]` per turn in `runAnthropic`. OpenAI: send `stream_options:{include_usage:true}`, parse `chunk["usage"]` in `OpenAIChatClient.assemble`. Store `SavedPlan.usage {input, output, cost}`. Price table per `LLMProvider` + model prefix, fallback "unknown price".

## Risks & open questions
- Prices drift — table with "as of" date + unknown fallback.

## Done when
- [ ] Plans show tokens + cost
- [ ] Added to `FEATURES.md` and row set to ✅ in `IDEAS.md`

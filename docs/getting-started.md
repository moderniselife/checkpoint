# Getting started

**What:** the five-minute path from download to your first test plan.
**Why:** Checkpoint needs two things — a model to write with, and a tracker to read from — before it can do anything.

## Install

Download the latest DMG from [Releases](https://github.com/moderniselife/checkpoint/releases/latest)
(or [checkpoint.guide](https://checkpoint.guide)), drag Checkpoint to Applications, and open it.
Requires macOS 26+. Ad-hoc signed builds need a first-run right-click → Open.

Building from source: `./build.sh --install --open` (needs Xcode 26+ and XcodeGen). For iPhone
or iPad, run `xcodegen generate`, open `Checkpoint.xcodeproj`, pick the **CheckpointMobile** scheme
and your own signing team, then run it on your device.

On first launch a short welcome walks you through everything below: how you test, your AI provider,
your trackers and sync. Skip any step and do it later here. **Help → Welcome to Checkpoint…** shows it again.

At the end, **Show Me Around** starts a guided tour: a spotlight walks the ticket bar, Dev/QA,
run options, the sidebar, a plan's header, criteria, filters, a task and the Research/Chat tabs.
It opens a sample plan if you don't have one yet. Take it again any time from **Help → Take the Tour**
(Mac) or the **?** menu (iPhone and iPad), or explore the sample plan on your own from the empty state.

## Connect an AI provider

Open **Settings (⌘,)** → **AI Provider**:

1. Pick a provider — Claude, OpenAI, Gemini, Grok, OpenRouter, or a local server
   (Ollama at `http://localhost:11434/v1`, LM Studio, vLLM, or any Anthropic-compatible gateway).
2. Paste the API key (local servers usually skip this).
3. **Fetch models**, pick one with tool calling, then **Test** — it sends a tiny "reply OK" prompt.

**When:** do this first; without a provider every analysis stops with a setup error.
**Why tool calling:** the model researches by calling tracker tools. Models without it can't research.

## Connect your tracker

In Settings → **Jira** (site + Sign in with Atlassian, or email + API token) and/or **Linear**
(Sign in with Linear, or API key). Hit **Test connection** — it lists the server's MCP tools
so you can see exactly what Checkpoint may use. Checkpoint is read-only by design and only
ever calls read tools.

**When:** connect one or both. Pasted links pick the tracker automatically; with both connected,
bare keys (PROJ-123) go to the tracker chosen in the input-bar menu.

## Run your first plan

1. Type a key (`PROJ-123`) or paste a ticket link into the top field (**⌘L** focuses it).
2. Pick **Dev** (you're verifying your own change) or **QA** (black-box testing of the hosted app).
3. Hit **Analyze** (⌘↩) and watch the research feed — it opens the ticket, children, comments
   and specs, then writes the plan.

**Why Dev vs QA matters:** Dev plans may reference branches, APIs and logs. QA plans speak only
in UI terms and start by confirming the fix is actually deployed. Same ticket, different reader.

Next: [Plans](plans.md) explains modes, effort, templates and cost; [Working a plan](working-a-plan.md)
covers ticking things off.

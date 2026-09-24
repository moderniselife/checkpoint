# Contributing to Checkpoint

Thanks for helping make testing tickets less painful! Bug reports, ideas, docs and code are all welcome.

## Ways to help

- **Report a bug** or **request a feature / AI provider / tracker** using the [issue forms](https://github.com/moderniselife/checkpoint/issues/new/choose).
- **Add ideas** to the [idea board](ideas/IDEAS.md) — `./ideas/idea "Your idea"` appends one.
- **Pick something up:** issues labelled `good first issue`, or 👍 ideas on the board.
- **Improve the docs:** README, FEATURES, the landing page in `site/`.

## Development setup

Requirements: macOS 26+, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/moderniselife/checkpoint.git
cd checkpoint
./build.sh --debug --open        # or: xcodegen generate && open Checkpoint.xcodeproj
```

The `.xcodeproj` is generated from `project.yml` — edit `project.yml`, not the project file, and re-run `xcodegen generate`.

To try it you'll need an AI provider (a local model works: `Local / OpenAI-compatible` → `http://localhost:11434/v1`) and a Jira or Linear account.

## Project layout

See [README → Project layout](README.md#project-layout). In short: `Models/` (plan, ticket, provider types), `Services/` (MCP, OAuth, AI clients, plan generator, stores), `Views/` (SwiftUI), `site/` (landing page), `ideas/` (idea board).

## Guidelines

- **Read-only by default.** Never give a model write access to a tracker, or write anything, without an explicit, confirmed user action.
- **No secrets or real data** in code, fixtures, tests or screenshots — use `PROJ-123`, `example.com`, `yourcompany.atlassian.net`.
- **Match the surrounding code:** SwiftUI + Liquid Glass, Swift 6 strict concurrency (default MainActor; network types `nonisolated`/actors), small focused files.
- **Keep existing users working:** saved plans, Keychain items and preferences must keep decoding (`decodeIfPresent` for new fields).
- **Update the docs** in the same PR: `FEATURES.md` rows/limitations, `README.md` for setup changes, and the site if user-facing.
- **Test it in the app** — describe what you tried in the PR (tracker, provider, model, Dev/QA).

## Pull requests

1. Fork and create a branch: `feature/short-name` or `fix/short-name`.
2. Make focused commits with clear messages.
3. Run `./build.sh` — it must succeed.
4. Open a PR using the template and link the issue or `IDEA-###`.

By contributing you agree your contributions are licensed under the project's license, and to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
You'll be added to [CONTRIBUTORS.md](CONTRIBUTORS.md) — thank you!

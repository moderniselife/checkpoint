# Security Policy

Checkpoint handles API keys, OAuth tokens and the contents of your tickets, so we take security reports seriously.

## Reporting a vulnerability

**Please don't open a public issue.** Report privately through GitHub:

➡️ **[Report a vulnerability](https://github.com/moderniselife/checkpoint/security/advisories/new)** (Security → Advisories → *Report a vulnerability*)

Include what you found, how to reproduce it, the version affected, and the impact you think it has.
You'll get an acknowledgement within **3 business days** and a status update within **7 days**.
We'll agree a disclosure date with you and credit you in the release notes (unless you'd rather not be named).

## Supported versions

Security fixes go into the **latest release**. Please update before reporting.

## Scope

In scope — for example:
- Leaking API keys or OAuth tokens (Keychain handling, logs, crash output, network)
- Checkpoint **writing** to Jira or Linear, or exposing write tools to a model, without explicit user action
- Codebase access escaping the folder the user chose (path traversal, symlinks)
- The OAuth loopback listener being reachable from other machines, or accepting forged callbacks
- Prompt injection in ticket or code content that causes actions beyond producing a plan
- Sandbox or entitlement weaknesses in release builds

Out of scope:
- Vulnerabilities in Atlassian, Linear, AI providers or their MCP servers (report to them)
- A model producing an inaccurate test plan
- Issues requiring a compromised Mac or a malicious local user with your account

## How Checkpoint protects you

- **Keys and tokens** live in the macOS Keychain, never in plain files.
- **Read-only trackers:** only read tools are exposed for Jira; Linear uses its read-only MCP endpoint and `read` scope.
- **Codebase access** (scenarios) is read-only and confined to a user-chosen folder via a security-scoped bookmark.
- **Sandboxed app** with network client, a loopback-only listener for sign-in, and read-only access to user-selected folders.
- **No Checkpoint servers:** the app talks directly to your tracker and your chosen AI provider.

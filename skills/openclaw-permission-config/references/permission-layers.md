# Permission Layers

OpenClaw uses five independent permission control layers. Each layer addresses a different security concern. They do not overlap — configuring one does not affect the others.

## Decision Tree

```
Do you need to isolate tool execution in Docker?
  → Yes → Configure Sandbox (Layer 1)
  → No  → Set sandbox.mode = "off"

Do you need to restrict which tools the agent can use?
  → Yes → Configure Tool Policy (Layer 2)
  → No  → Leave tools.* unconfigured (all tools available)

Is sandbox enabled AND do trusted operators need host exec?
  → Yes → Configure Elevated (Layer 3)
  → No  → Leave elevated disabled

Do you need approval workflows for exec commands?
  → Yes → Configure Exec Approvals (Layer 4)
  → No  → Leave defaults (depends on sandbox state)

Does the Gateway accept external connections?
  → Yes → Configure Gateway Auth (Layer 5)
  → No  → Minimal auth for local-only use
```

## Layer 1: Sandbox

**Controls**: Where tools execute — Docker container vs host machine.

**Key fields**:

| Field | Values | Default |
|-------|--------|---------|
| `agents.defaults.sandbox.mode` | `off`, `non-main`, `all` | `off` |
| `agents.defaults.sandbox.scope` | `session`, `agent`, `shared` | `session` |
| `agents.defaults.sandbox.workspaceAccess` | `none`, `ro`, `rw` | `none` |
| `agents.defaults.sandbox.docker.network` | any Docker network | `none` |
| `agents.defaults.sandbox.docker.image` | Docker image name | `openclaw-sandbox:bookworm-slim` |
| `agents.defaults.sandbox.docker.binds` | `["host:container:mode"]` | none |

**What gets sandboxed**: `exec`, `read`, `write`, `edit`, `apply_patch`, `process`, and browser (optionally).

**What is NOT sandboxed**: The Gateway process itself, and tools marked as `tools.elevated`.

**Blocked bind sources**: Docker sockets, `/etc`, `/proc`, `/sys`, `/dev`.

## Layer 2: Tool Policy

**Controls**: Which tools are available to the agent — allow/deny lists.

**Key fields**:

| Field | Description |
|-------|-------------|
| `tools.deny` | Array of tool names to block globally (deny always wins) |
| `tools.sandbox.tools.allow` | Array of tools allowed inside sandbox |

**Tool groups**: Use shortcuts like `group:runtime`, `group:fs` instead of listing individual tools.

**Rule**: Deny always wins. A non-empty allow list acts as a blocklist (anything not listed is denied).

## Layer 3: Elevated

**Controls**: Whether sandboxed sessions can execute commands on the host.

**Key fields**:

| Field | Description |
|-------|-------------|
| `tools.elevated.enabled` | `true` / `false` |
| `tools.elevated.allowFrom` | Per-channel sender allowlists |

**Modes** (set via `/elevated` directive):

| Mode | Behavior |
|------|----------|
| `on` / `ask` | Host exec with approval required |
| `full` | Host exec, approval skipped |
| `off` | Disabled |

**Only affects `exec`**. If `exec` is denied by tool policy, elevated cannot be used.

**Effectively a no-op** when sandbox is off (exec already runs on host).

## Layer 4: Exec Approvals

**Controls**: Approval workflow for exec commands on real hosts.

**Config file**: `~/.openclaw/exec-approvals.json`

> **CRITICAL DEFAULT**: When `exec-approvals.json` does not exist, OpenClaw uses hardcoded defaults: `security: "deny"`, `ask: "on-miss"`, `askFallback: "deny"`. On headless or non-GUI environments (Linux servers, SSH sessions, Docker), this means **all exec requests are silently denied** — including tools that internally rely on exec (web search, web fetch, etc.). You must explicitly create this file to allow execution.
>
> Additionally, `tools.exec.ask` must be set in `openclaw.json` (not just in `exec-approvals.json`). Due to issue #29172, when this field is absent in `openclaw.json`, the gateway defaults to `"on-miss"` and ignores `exec-approvals.json`'s `ask` setting.

**Two config surfaces** (both must agree):

| Surface | Field | Purpose |
|---------|-------|---------|
| `openclaw.json` | `tools.exec.security` | Gateway-side exec policy |
| `openclaw.json` | `tools.exec.ask` | Gateway-side prompt behavior |
| `exec-approvals.json` | `defaults.security` | Approvals-side exec policy |
| `exec-approvals.json` | `defaults.ask` | Approvals-side prompt behavior |
| `exec-approvals.json` | `defaults.askFallback` | Behavior when UI is unreachable |

**Security levels**:

| Policy | Behavior |
|--------|----------|
| `deny` | Block all host exec |
| `allowlist` | Only allowlisted commands pass |
| `full` | Everything auto-approved |

**Prompt behavior**: `off`, `on-miss` (prompt only when allowlist misses), `always`.

**Fallback** (`askFallback`): What happens when UI is unreachable — `deny`, `allowlist-only`, or `full`.

**Safe bins**: `jq`, `cut`, `uniq`, `head`, `tail`, `tr`, `wc` auto-allow in `allowlist` mode (stdin-only).

**Allowlist format**: Per-agent, case-insensitive glob patterns resolving to binary paths. Basename-only patterns are rejected.

## Layer 5: Gateway Auth

**Controls**: Who can access the Gateway and communicate with the agent.

**Key fields**:

| Field | Description |
|-------|-------------|
| `gateway.auth.mode` | `token`, `password`, or `trusted-proxy` (required on v2026.3.7+) |
| `gateway.auth.token` | Access token |
| `gateway.auth.password` | Password |
| `channels.*.dmPolicy` | Per-channel DM access policy |

**DM policies**:

| Policy | Behavior |
|--------|----------|
| `pairing` | One-time approval codes for unknown senders |
| `allowlist` | Only approved senders in `allowFrom` |
| `open` | All DMs allowed (requires `allowFrom: ["*"]`) |
| `disabled` | Block all DMs |

**Trusted Proxy** (`trusted-proxy`): Delegates auth entirely to reverse proxy. Only use behind identity-aware proxies (Pomerium, Caddy + OAuth, nginx + oauth2-proxy).

## Layer Interaction Summary

```
Request arrives
  → Gateway Auth (Layer 5): Is the sender authorized?
  → Tool Policy (Layer 2): Is the requested tool allowed?
  → Sandbox (Layer 1): Should this tool run in Docker?
    → If sandboxed and exec:
      → Elevated (Layer 3): Can exec escape to host?
      → Exec Approvals (Layer 4): Is this command approved?
```

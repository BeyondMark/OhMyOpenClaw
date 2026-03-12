---
name: openclaw-permission-config
description: "Guide users through OpenClaw permission configuration across versions. Use when OpenClaw operations fail due to permission issues, when setting up a new OpenClaw instance, or when hardening security after an upgrade. This skill detects the current version, audits all five permission layers (sandbox, tool policy, elevated, exec approvals, gateway auth), recommends scenario-based presets, applies configuration via openclaw CLI, and verifies the result."
---

# OpenClaw Permission Config

## Overview

Use this skill when a user needs to configure, audit, or fix OpenClaw permissions.

When referring to bundled files, resolve paths relative to this skill directory. Do not assume a user-specific install path.

This skill owns the decision-making layer:

- detect the OpenClaw version and current permission state
- ask the user about their deployment scenario
- recommend permission settings based on the scenario and version
- check for dangerous downgrades before applying changes
- call execution-only scripts with final, explicit values
- verify the result with built-in diagnostics

The scripts in `scripts/` are execution-only. They must be called with final, explicit values and should not be used as the place where you ask the user what to do.

For the five permission layers and when to use each, read `references/permission-layers.md`.

For version-specific breaking changes, read `references/version-changes.md`.

For copy-paste preset configs by scenario, read `references/security-presets.md`.

## Permission Layers

OpenClaw has five independent permission control layers:

| Layer | Controls | Config Path |
|-------|----------|-------------|
| Sandbox | Where tools execute (Docker vs host) | `agents.defaults.sandbox.*` |
| Tool Policy | Which tools are available (allow/deny) | `tools.*` |
| Elevated | Whether sandboxed exec can escape to host | `tools.elevated.*` |
| Exec Approvals | Approval flow for exec commands | `~/.openclaw/exec-approvals.json` |
| Gateway Auth | Who can access the Gateway | `gateway.auth.*` + DM policy |

All five layers are independent. Configuring one does not affect the others. The skill must audit and configure each layer separately.

## Workflow

### 1. Detect Environment

```bash
./scripts/detect_environment.sh --json
```

Interpretation:

- `installed: false`: stop and tell the user OpenClaw CLI is not found
- `installed: true`: continue with the reported version
- Check `config_exists` to know whether `~/.openclaw/openclaw.json` is present
- Check `version` to determine which features are available (see `references/version-changes.md`)

### 2. Audit Current Permissions

```bash
./scripts/audit_permissions.sh --json
```

The script scans all five layers and outputs a structured report. Present the audit result to the user before recommending changes. Highlight:

- any layer set to its most permissive value (sandbox off, exec approvals full, elevated full)
- any missing required field for the detected version (e.g., `gateway.auth.mode` missing on v2026.3.7+)
- any deny rules that may block normal operation

### 3. Guided Configuration (Decision Layer)

#### 3a. Present Scenario Options

Ask the user which deployment scenario matches their setup. For each option, you must clearly explain what OpenClaw will be able to do, what it will not be able to do, and what the risks are. Use the following presentation format:

---

**Option A: Personal local (个人本地开发)**

What OpenClaw CAN do with this configuration:
- Run any shell command on your machine (rm, curl, git, etc.) — without approval prompts
- Read and write any file your user account can access (~/.ssh, ~/.env, etc.)
- Access the network freely (call APIs, download packages, browse the web)
- Install packages, modify system configs, send messages
- Use web search, web fetch, and all tools that internally rely on exec

What OpenClaw CANNOT do:
- Nothing is restricted. This is the most permissive configuration.

What this configuration changes:
- Sandbox: off (all tools run directly on host)
- tools.exec.security: full (no exec approval required)
- tools.exec.ask: off (never prompt for approval)
- exec-approvals.json: security=full, ask=off, askFallback=full (all exec auto-approved)
- Gateway auth: token-based

Important: This preset must create `~/.openclaw/exec-approvals.json` and set `tools.exec` in `openclaw.json`. Without these, OpenClaw defaults to denying all exec requests — even web search will fail silently.

Risks:
- A malicious Skill or prompt injection can execute arbitrary commands on your host
- Your SSH keys, API tokens, browser credentials are all accessible
- No sandbox isolation means a mistake has full blast radius
- Acceptable only if you are the sole user on a trusted personal machine

---

**Option B: Team collaboration (团队协作)**

What OpenClaw CAN do with this configuration:
- Run tools in the main session on the host (for the primary user)
- Read the workspace in read-only mode from sandboxed sessions
- Use runtime and filesystem tool groups inside sandboxed sessions
- Accept messages from users who complete DM pairing

What OpenClaw CANNOT do:
- Non-main sessions cannot write to the host filesystem
- Non-main sessions have no network access by default
- Exec commands from unknown senders require manual approval
- Unapproved exec commands are denied

Risks:
- The main session still runs on the host without sandbox
- A team member who completes pairing has ongoing access
- Exec approval UI unavailable = commands are denied (safe default)
- Moderate risk — suitable for internal development teams

---

**Option C: VPS / Remote (远程服务器)**

What OpenClaw CAN do with this configuration:
- Run tools inside isolated Docker containers
- Use runtime and filesystem tool groups inside containers
- Respond to messages from explicitly allowlisted senders only

What OpenClaw CANNOT do:
- Cannot execute shell commands (exec is globally denied)
- Sandboxed containers have no network access
- Cannot access host filesystem (workspaceAccess = none)
- Cannot respond to unknown senders (DM allowlist only)

Risks:
- If exec deny rule is removed, host is exposed
- Token-based auth can be stolen if transmitted over unencrypted channels
- Public IP exposure increases attack surface
- Recommended: use Tailscale instead of exposing Gateway to internet

---

**Option D: Production (生产环境)**

What OpenClaw CAN do with this configuration:
- Run minimal filesystem tools inside fully isolated Docker containers
- Respond only to admin-paired senders
- Filter sensitive data patterns (API keys, private keys) from agent context

What OpenClaw CANNOT do:
- Cannot execute any shell commands (exec denied + exec approvals deny)
- Cannot access host filesystem
- Cannot access network from containers
- Cannot write to container root filesystem (readOnlyRoot)
- Cannot bypass permissions (disableBypassPermissionsMode)

Risks:
- Minimal. This is the most restrictive configuration.
- Requires identity-aware reverse proxy (Pomerium, Caddy + OAuth)
- Over-restriction may break legitimate workflows — test thoroughly
- Managed hosting (ClawCloud, ClawTank) provides equivalent isolation automatically

---

#### 3b. Present Change Summary

After the user selects a scenario, load the matching preset from `references/security-presets.md` and present a change-by-change summary. For each setting that will change, show:

```
Layer: [层级名称]
Setting: [配置键]
Current value: [当前值 or "unset"]
New value: [将设置的值]
Effect: [一句话说明这个变更的实际效果]
Risk note: [如果是放宽权限，标注风险；如果是收紧权限，标注可能影响的功能]
```

Example:

```
Layer: Sandbox
Setting: agents.defaults.sandbox.mode
Current value: off
New value: all
Effect: 所有会话的工具执行将在 Docker 容器内进行，与宿主机隔离
Risk note: 某些需要宿主机访问的工具可能无法正常工作

Layer: Tool Policy
Setting: tools.deny
Current value: (none)
New value: ["exec"]
Effect: 全局禁止 exec 工具，Agent 无法执行任何 shell 命令
Risk note: 如果有合法的 shell 需求（如构建、部署），需要额外配置 exec approvals 白名单
```

Get explicit confirmation from the user before proceeding to step 4. If the user wants to adjust individual settings, allow them to override specific values from the preset.

#### 3c. Single-Layer Mode

If the user wants to configure only a specific layer, skip the preset and ask targeted questions for that layer only. For each layer, explain:

- What this layer controls (one sentence)
- What the current setting is
- What options are available and what each option means in practice
- Recommend an option and explain why

### 4. Apply Configuration

**Critical: exec approvals must always be explicitly configured.** When `~/.openclaw/exec-approvals.json` does not exist, OpenClaw defaults to `security: "deny"` and `askFallback: "deny"`. On headless or non-GUI environments, this silently blocks all execution — including tools that internally rely on exec (web search, web fetch, etc.). Never assume "no config file = no restrictions".

Additionally, `tools.exec.ask` must be explicitly set in `openclaw.json` because of a known issue (#29172): when this field is absent, the gateway code defaults to `"on-miss"` regardless of what `exec-approvals.json` says.

For each configuration key-value pair in `openclaw.json`, run:

```bash
./scripts/apply_config.sh \
  --key "agents.defaults.sandbox.mode" \
  --value "non-main"
```

The script uses `openclaw config set` internally. Call it once per key-value pair. The decision layer must compute all final values before calling the script.

For `tools.exec` settings in `openclaw.json`:

```bash
./scripts/apply_config.sh \
  --key "tools.exec.security" \
  --value "full"

./scripts/apply_config.sh \
  --key "tools.exec.ask" \
  --value "off"
```

For exec approvals (`exec-approvals.json`), use the `--target exec-approvals` flag:

```bash
./scripts/apply_config.sh \
  --target exec-approvals \
  --key "version" \
  --value "1"

./scripts/apply_config.sh \
  --target exec-approvals \
  --key "defaults.security" \
  --value "full"

./scripts/apply_config.sh \
  --target exec-approvals \
  --key "defaults.ask" \
  --value "off"

./scripts/apply_config.sh \
  --target exec-approvals \
  --key "defaults.askFallback" \
  --value "full"
```

After applying all configuration, always restart the gateway for changes to take effect:

```bash
openclaw gateway restart
```

### 5. Verify Configuration

```bash
./scripts/verify_permissions.sh --json
```

The script runs:

- `openclaw config validate`
- `openclaw doctor --security` (if available on the detected version)
- `openclaw sandbox explain` (if sandbox is enabled)

Present the verification result. If any check fails, surface the exact error and suggest a fix. Do not claim success if verification fails.

## Safety Rules

- Do not silently overwrite existing `tools.deny` rules. Show the user what exists and ask before modifying.
- Do not lower security levels without explicit user confirmation. Changing exec approvals from `allowlist` to `full`, or sandbox from `all` to `off`, requires the user to acknowledge the downgrade.
- If version detection fails, stop. Do not guess the configuration format.
- On v2026.3.7+, warn the user that `gateway.auth.mode` is now required and that missing it causes startup failures.
- Do not write raw JSON to `~/.openclaw/openclaw.json`. Always use `openclaw config set` via the apply script.
- If `openclaw config validate` fails after applying changes, attempt to rollback by restoring the previous value and report the failure.
- Do not configure elevated mode to `full` without warning the user that this bypasses all exec approval checks.
- If the user's current config has custom tool policy rules, preserve them unless explicitly asked to replace.

## Resources

### scripts/

- `scripts/detect_environment.sh`: detect OpenClaw CLI presence, version, and existing config
- `scripts/audit_permissions.sh`: scan all five permission layers, output structured report
- `scripts/apply_config.sh`: write config values via `openclaw config set` or `exec-approvals.json`
- `scripts/verify_permissions.sh`: run config validate, doctor --security, sandbox explain

### references/

- `references/permission-layers.md`: five permission layers explained with decision tree
- `references/version-changes.md`: version-specific breaking changes and migration notes
- `references/security-presets.md`: scenario-based preset configurations

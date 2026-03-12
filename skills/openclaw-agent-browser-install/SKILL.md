---
name: openclaw-agent-browser-install
description: "Install or verify vercel-labs/agent-browser for Claude Code, Codex, or OpenClaw. Use when you need to detect which supported agent CLI is installed, choose a target tool, install the official agent-browser skill and CLI, or confirm that browser automation is ready to use."
---

# OpenClaw Agent Browser Install

## Overview

Use this skill to install `vercel-labs/agent-browser` in a controlled way.

Trigger policy:

- manual-only
- start this skill only when the user explicitly asks to use `openclaw-agent-browser-install`, or explicitly asks to install/verify `agent-browser` for Claude Code, Codex, or OpenClaw
- do not auto-trigger this skill from generic browser automation or tool-install questions
- if the user has not explicitly asked for `agent-browser` installation or verification, stop and ask before proceeding with this skill

When referring to bundled files, resolve paths relative to this skill directory. Do not assume a user-specific checkout path.

This skill owns the decision-making layer:

- detect which supported tools are installed
- ask the user which target to use when more than one target is available
- decide whether installation should proceed
- call execution-only scripts with final arguments
- run verification after installation and report the result

The scripts in `scripts/` are execution-only. They must not be used as a place to ask the user what to do.

For the official install matrix and the chosen best-practice mapping, read `references/install-matrix.md`.

## Workflow

1. Detect the current environment first:

```bash
./scripts/detect_supported_tools.sh --json
```

2. Interpret the result before installing:

- If none of `claude-code`, `codex`, or `openclaw` is installed, stop and tell the user no supported target is available.
- If exactly one target is installed, use it unless the user asks for something else.
- If more than one target is installed, ask the user in chat which target should receive `agent-browser`.

3. Run the installer with an explicit target:

```bash
./scripts/install_agent_browser.sh --target claude-code
./scripts/install_agent_browser.sh --target codex
./scripts/install_agent_browser.sh --target openclaw
```

4. Verify after installation:

```bash
./scripts/verify_agent_browser.sh --target claude-code --json
./scripts/verify_agent_browser.sh --target codex --json
./scripts/verify_agent_browser.sh --target openclaw --json
```

5. Summarize the verification result for the user:

- whether the `agent-browser` CLI is installed
- whether the target skill files exist
- whether the browser smoke test passed
- any exact failure message that still needs manual action

## Target Rules

### Claude Code

- Install the `agent-browser` CLI first
- Then install the official skill with the official `skills` CLI flow
- Prefer a global install so the capability is available across projects

### Codex

- Install the `agent-browser` CLI first
- Then install the official skill with the official `skills` CLI flow
- Prefer a global install so the capability is available across projects

### OpenClaw

- Install the `agent-browser` CLI first
- Then copy the official `skills/agent-browser` bundle into `~/.openclaw/skills/agent-browser`
- Do not assume that `npx skills add` officially targets OpenClaw

## Safety Rules

- Do not let the install script pick a target interactively. The target must be explicit.
- Do not overwrite an existing OpenClaw local skill silently. If the path already exists, either stop or rerun the script with an explicit overwrite flag after user confirmation.
- If an npm or npx step fails because of cache permissions, surface the exact error instead of pretending the install succeeded.
- If verification fails, report which layer failed: CLI install, skill placement, or browser smoke test.

## Resources

### scripts/

- `scripts/detect_supported_tools.sh`: detect installed target tools and prerequisites
- `scripts/install_agent_browser.sh`: execution-only installer for `claude-code`, `codex`, or `openclaw`
- `scripts/verify_agent_browser.sh`: verify CLI presence, target skill placement, and browser smoke test

### references/

- `references/install-matrix.md`: official sources and chosen install mapping

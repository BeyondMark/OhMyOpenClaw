---
name: openclaw-gateway-repair
description: "Diagnose and repair OpenClaw gateway restart loops or blocked starts after upgrades. Use when OpenClaw shows a running LaunchAgent but the gateway keeps restarting, when ~/.openclaw/logs/gateway.err.log contains 'Gateway start blocked: set gateway.mode=local', or when you need to verify and restore a local gateway service with official OpenClaw config and gateway commands."
---

# OpenClaw Gateway Repair

## Overview

Use this skill to diagnose upgrade-related OpenClaw gateway failures where the service appears installed but repeatedly restarts or is blocked by missing local-mode configuration.

Follow the workflow in order. Prefer the bundled script for deterministic repair, then verify with `openclaw status` and recent logs.

## Workflow

1. Inspect the active symptom before changing anything.

```bash
openclaw gateway status
openclaw status
tail -n 40 ~/.openclaw/logs/gateway.err.log
tail -n 40 ~/.openclaw/logs/gateway.log
```

2. If the error log contains `Gateway start blocked: set gateway.mode=local (current: unset)`, treat missing `gateway.mode` as the primary root cause.

3. Run the bundled repair script:

```bash
./scripts/fix_gateway_mode.sh
```

4. If running from another working directory, call it with an absolute path:

```bash
/Users/mark/.codex/skills/openclaw-gateway-repair/scripts/fix_gateway_mode.sh
```

5. Confirm the repair:

```bash
openclaw config get gateway.mode
openclaw config validate
openclaw status
launchctl print gui/$(id -u)/ai.openclaw.gateway | sed -n '1,120p'
```

6. If `gateway.mode` is already `local` but the gateway still fails, read `references/restart-loop.md` and continue from the fallback checks there instead of guessing.

## Expected Healthy State

- `openclaw config get gateway.mode` returns `local`
- `openclaw config validate` reports the config as valid
- `openclaw status` shows `Gateway: local` and `Gateway service: ... running`
- `~/.openclaw/logs/gateway.log` contains a `listening on ws://127.0.0.1:` line

## Resources

### scripts/

- `scripts/fix_gateway_mode.sh`: Idempotently set `gateway.mode=local`, validate config, restart the gateway service, and print verification output.

### references/

- `references/restart-loop.md`: Symptom mapping, official doc links, and fallback checks for cases where the mode is already correct.

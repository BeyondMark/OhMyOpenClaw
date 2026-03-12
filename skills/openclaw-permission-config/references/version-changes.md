# Version Changes

Permission-related breaking changes and migration notes across OpenClaw versions.

## v2026.3.7 — gateway.auth.mode Required

**Breaking change**: If both `gateway.auth.token` and `gateway.auth.password` are configured, you must now set `gateway.auth.mode` to either `token` or `password`.

**Symptom**: Gateway startup failure, pairing failures, or TUI crashes after upgrade.

**Fix**:

```bash
openclaw config set gateway.auth.mode token
# or
openclaw config set gateway.auth.mode password
```

**Detection**: If `gateway.auth.mode` is unset and the version is >= 2026.3.7, flag this as a critical issue.

## v2026.3.x — Sandbox Enhancements

- `sandbox.browser.cdpSourceRange`: CIDR allowlist for CDP access
- `sandbox.browser.allowHostControl`: Explicit flag for host browser targeting
- `sandbox.docker.binds`: Dangerous source paths are now blocked by default

## v2026.2.x — Security Hardening Wave

- **CVE-2026-25253**: Configuration rewrite to address agent hijacking vulnerability
- **Skill Permission Manifests**: Discussion #6401 introduced `permissions:` frontmatter in SKILL.md (advisory, not enforced)
- **security.yaml**: Global security configuration at `~/.openclaw/security.yaml`
- **Sensitive data patterns**: `security.sensitiveData.patterns` to filter credentials from agent context
- **openclaw doctor --security**: New diagnostic subcommand for security checks
- **exec-approvals.json**: New per-agent exec command approval system
- **Tool Policy**: `tools.deny` and `tools.sandbox.tools.allow` introduced

## v2026.1.x — Foundation

- **Gateway modes**: `gateway.mode` = `local` | `remote` | `headless`
- **Sandbox**: Initial `agents.defaults.sandbox.mode` support (`off`, `non-main`, `all`)
- **Tool groups**: `group:runtime`, `group:fs` shortcuts
- **Elevated**: `tools.elevated.enabled` and `tools.elevated.allowFrom`
- **DM Policy**: `pairing`, `allowlist`, `open`, `disabled` per channel
- **Config reload**: `gateway.reload` modes (`hybrid`, `hot`, `restart`, `off`)

## v2025.x (pre-2026) — Legacy

- Configuration used `~/.openclaw/openclaw.json` or earlier `~/.moltbot/` paths
- No sandbox support
- No tool policy
- No exec approvals
- Gateway auth via simple token only
- Upgrade to v2026.1+ required config migration

## Migration Checklist

When upgrading across major versions:

1. Run `openclaw doctor --fix` to detect and auto-repair known issues
2. Check `gateway.auth.mode` is set (v2026.3.7+ requirement)
3. Review `sandbox.mode` — defaults may have changed
4. Check for deprecated config paths (`~/.moltbot/` → `~/.openclaw/`)
5. Validate with `openclaw config validate`
6. Review exec-approvals if upgrading from pre-v2026.2

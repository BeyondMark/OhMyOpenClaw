# Security Presets

Copy-paste preset configurations for common deployment scenarios. Each preset configures all five permission layers.

Each preset includes three sections:

- **Impact Summary**: what OpenClaw can/cannot do, and what risks remain — present this to the user before applying
- **Configuration**: the actual config to apply
- **Post-apply notes**: additional recommendations after applying

## Personal Local Development

For: running OpenClaw on your personal machine for local development.

**Risk profile**: Low. Single user, trusted environment, no external exposure.

### Impact Summary

**What OpenClaw CAN do**:

- Execute any shell command your user account can run (including `rm -rf`, `curl`, `git push --force`)
- Read and write any file accessible to your user (`~/.ssh/`, `~/.aws/`, `~/.env`, browser profiles, crypto wallets)
- Make outbound network requests (call APIs, download files, send HTTP requests to any endpoint)
- Install/uninstall packages, modify dotfiles, send messages through connected channels
- Access browser automation, calendar, email — anything configured in channels

**What OpenClaw CANNOT do**:

- Nothing is restricted at the OpenClaw level. The only limits are your OS user permissions.

**Risks you accept**:

- A malicious ClawHub Skill can silently exfiltrate your SSH keys, API tokens, or passwords
- A prompt injection via Telegram/email can trick OpenClaw into executing destructive commands
- No sandbox means every mistake has full blast radius on your machine
- Your API keys (OpenAI, Anthropic, etc.) stored in `~/.openclaw/.env` are readable by any tool

**Who should use this**: Solo developers on a personal machine who trust all installed Skills and don't expose the Gateway to any network.

### Configuration

```json5
{
  // Layer 1: Sandbox — off for convenience
  agents: {
    defaults: {
      sandbox: {
        mode: "off",
      },
    },
  },

  // Layer 2: Tool Policy — no restrictions, exec fully open
  tools: {
    exec: {
      security: "full",   // allow all exec commands without approval
      ask: "off",          // never prompt for approval
    },
  },

  // Layer 5: Gateway Auth — token only
  gateway: {
    mode: "local",
    auth: {
      mode: "token",
      token: "your-personal-token-here",
    },
  },
}
```

**Exec Approvals** (Layer 4): Must explicitly create `~/.openclaw/exec-approvals.json` to override the deny-all default:

```json
{
  "version": 1,
  "defaults": {
    "security": "full",
    "ask": "off",
    "askFallback": "full",
    "autoAllowSkills": true
  }
}
```

> **Why this is required**: When `exec-approvals.json` does not exist, OpenClaw defaults to `security: "deny"` and `askFallback: "deny"`. On environments without the companion app UI (headless Linux, SSH sessions, etc.), all exec requests — including tool calls like web search that internally invoke exec — are silently denied. You must create this file to unlock execution.
>
> Additionally, `tools.exec.ask` must be set to `"off"` in `openclaw.json` due to a known issue (#29172): when this field is absent, the gateway defaults to `"on-miss"` and ignores any `ask: "off"` in `exec-approvals.json`.

**Elevated** (Layer 3): Leave disabled.

### Post-apply Notes

- Even in personal mode, consider adding `tools.deny` rules for commands you never want OpenClaw to run (e.g., `rm -rf /`)
- Review installed ClawHub Skills periodically — check source code before installing new ones
- If you later connect messaging channels (Telegram, WhatsApp), set `dmPolicy: "pairing"` to prevent strangers from using your agent

## Team Collaboration

For: shared instance among team members in a development environment.

**Risk profile**: Medium. Multiple users, internal network.

### Impact Summary

**What OpenClaw CAN do**:

- In the **main session** (primary user): run tools directly on the host, full filesystem and network access
- In **non-main sessions** (other team members): run tools inside Docker containers
- Sandboxed sessions can read the workspace in read-only mode
- Sandboxed sessions can use runtime tools (process management) and filesystem tools (read/list)
- Accept messages from new users after they complete a one-time DM pairing code
- Execute approved shell commands after user confirmation (on-miss prompt)

**What OpenClaw CANNOT do**:

- Non-main sessions cannot write to the host filesystem
- Non-main sessions have no network access by default (Docker `network: none` applies if you set it)
- Exec commands that don't match the allowlist require manual approval
- When the approval UI is unreachable, exec commands are denied

**Risks you accept**:

- The main session is still unsandboxed — the primary user has full host access
- Anyone who completes DM pairing gets ongoing access (revoke by editing channel config)
- Sandboxed sessions can still read workspace files (read-only); sensitive files in the workspace are visible
- If you enable Elevated mode for trusted members, they can run host-level exec

**Who should use this**: Small teams sharing a development instance on an internal network, where the primary user is trusted and other members have limited access.

### Configuration

```json5
{
  // Layer 1: Sandbox — isolate non-main sessions
  agents: {
    defaults: {
      sandbox: {
        mode: "non-main",
        scope: "session",
        workspaceAccess: "ro",
      },
    },
  },

  // Layer 2: Tool Policy — allow common tools, deny dangerous ones
  tools: {
    deny: [],
    sandbox: {
      tools: {
        allow: ["group:runtime", "group:fs"],
      },
    },
  },

  // Layer 3: Elevated — ask mode for trusted members
  // tools: {
  //   elevated: {
  //     enabled: true,
  //     allowFrom: {
  //       discord: ["trusted-member-id"],
  //     },
  //   },
  // },

  // Layer 5: Gateway Auth — password + DM pairing
  gateway: {
    mode: "local",
    auth: {
      mode: "password",
      password: "team-password-here",
    },
  },

  // DM pairing for new users
  channels: {
    telegram: {
      dmPolicy: "pairing",
    },
    discord: {
      dmPolicy: "pairing",
    },
  },
}
```

**Exec Approvals** (Layer 4):

```json
{
  "policy": "allowlist",
  "prompt": "on-miss",
  "askFallback": "deny"
}
```

### Post-apply Notes

- Consider setting `sandbox.docker.network: "none"` for sandboxed sessions if your team doesn't need outbound network access from containers
- Regularly audit the DM pairing list — remove departed team members
- If a team member needs host-level exec (e.g., for deployment scripts), enable Elevated with `ask` mode (not `full`) and add their sender ID to `allowFrom`

## VPS / Remote Deployment

For: self-hosted on a remote VPS accessible over the network.

**Risk profile**: High. Public exposure, remote access.

### Impact Summary

**What OpenClaw CAN do**:

- Run runtime and filesystem tools inside isolated Docker containers
- Read/list files within the sandbox workspace (but not the host filesystem)
- Respond to messages from explicitly allowlisted phone numbers / user IDs only
- Process text, analyze data, and use tools that don't require shell access

**What OpenClaw CANNOT do**:

- Cannot execute any shell commands — `exec` is globally denied via tool policy
- Sandboxed containers have no network access (`network: "none"`)
- Cannot access the host filesystem (`workspaceAccess: "none"`)
- Cannot respond to messages from unknown senders (DM allowlist only, not pairing)
- Cannot install packages or modify system configuration

**Risks you accept**:

- The Gateway process itself runs on the host (not sandboxed) and listens on a port
- Token-based auth transmitted over unencrypted connections can be intercepted
- If someone obtains your auth token, they can access the Gateway
- Public IP exposure means automated scanners will find your instance
- If the `exec` deny rule is accidentally removed, the host becomes exposed

**Who should use this**: Users running OpenClaw on a VPS or cloud server who need remote access but want strong isolation. Tailscale or VPN is strongly recommended over direct port exposure.

### Configuration

```json5
{
  // Layer 1: Sandbox — all sessions sandboxed
  agents: {
    defaults: {
      sandbox: {
        mode: "all",
        scope: "session",
        workspaceAccess: "none",
        docker: {
          network: "none",  // no egress by default
        },
      },
    },
  },

  // Layer 2: Tool Policy — explicit allow list
  tools: {
    deny: ["exec"],  // deny exec by default; use elevated for exceptions
    sandbox: {
      tools: {
        allow: ["group:runtime", "group:fs"],
      },
    },
  },

  // Layer 3: Elevated — disabled
  // (do not enable on public-facing instances)

  // Layer 5: Gateway Auth — token + DM allowlist
  gateway: {
    mode: "local",
    auth: {
      mode: "token",
      token: "strong-random-token-here",
    },
  },

  channels: {
    whatsapp: {
      dmPolicy: "allowlist",
      allowFrom: ["+your-number"],
    },
    telegram: {
      dmPolicy: "allowlist",
      allowFrom: ["your-telegram-id"],
    },
  },
}
```

**Exec Approvals** (Layer 4):

```json
{
  "policy": "allowlist",
  "prompt": "always",
  "askFallback": "deny"
}
```

### Post-apply Notes

- Use Tailscale for remote access instead of exposing Gateway to public internet
- Set up TLS via reverse proxy (nginx, Caddy) — never run unencrypted on a public IP
- Run `openclaw doctor --security` regularly
- Consider `sandbox.docker.binds` to mount specific data directories read-only if the agent needs access to project files

## Production Environment

For: production deployment with strict security requirements.

**Risk profile**: Critical. Zero tolerance for unauthorized access.

### Impact Summary

**What OpenClaw CAN do**:

- Run minimal filesystem tools (read, list, write within sandbox) inside fully isolated Docker containers
- Each agent gets its own isolated container (per-agent scope)
- Respond only to admin senders who complete DM pairing
- Filter sensitive data patterns (API keys like `sk-*`, GitHub tokens `ghp_*`, AWS keys `AKIA*`, private keys) from agent context before processing

**What OpenClaw CANNOT do**:

- Cannot execute any shell commands — `exec` denied at both tool policy AND exec approvals level
- Cannot access host filesystem in any way (`workspaceAccess: "none"`)
- Cannot access network from containers (`network: "none"`)
- Cannot write to container root filesystem (`readOnlyRoot: true`)
- Cannot bypass permissions even via CLI flags (`disableBypassPermissionsMode`)
- Cannot use runtime tool group — only filesystem tools are available
- Cannot install packages, run builds, or modify any system state

**Risks you accept**:

- Minimal residual risk
- Requires a properly configured identity-aware reverse proxy (Pomerium, Caddy + OAuth, nginx + oauth2-proxy) — misconfigured proxy = full exposure
- Over-restriction may break legitimate workflows — test thoroughly before deploying
- DM pairing code interception is possible if the pairing channel itself is compromised
- Gateway process still runs on host — host OS security is still your responsibility

**Who should use this**: Production deployments serving real users, handling sensitive data, or subject to compliance requirements. Consider managed hosting (ClawCloud, ClawTank) for equivalent isolation without operational overhead.

### Configuration

```json5
{
  // Layer 1: Sandbox — maximum isolation
  agents: {
    defaults: {
      sandbox: {
        mode: "all",
        scope: "agent",  // per-agent isolation
        workspaceAccess: "none",
        docker: {
          network: "none",
          readOnlyRoot: true,
        },
      },
    },
  },

  // Layer 2: Tool Policy — minimal allow, explicit deny
  tools: {
    deny: ["exec"],
    sandbox: {
      tools: {
        allow: ["group:fs"],  // minimal tools only
      },
    },
  },

  // Layer 3: Elevated — disabled
  // Never enable in production

  // Layer 5: Gateway Auth — trusted proxy + DM pairing
  gateway: {
    mode: "local",
    auth: {
      mode: "trusted-proxy",
      // Requires identity-aware reverse proxy (Pomerium, Caddy + OAuth, etc.)
    },
  },

  // Sensitive data filtering
  security: {
    sensitiveData: {
      patterns: ["sk-*", "ghp_*", "AKIA*", "-----BEGIN*PRIVATE KEY-----"],
    },
  },

  channels: {
    telegram: {
      dmPolicy: "pairing",
      allowFrom: ["admin-telegram-id"],
    },
  },
}
```

**Exec Approvals** (Layer 4):

```json
{
  "policy": "deny",
  "prompt": "off",
  "askFallback": "deny"
}
```

### Post-apply Notes

- Deploy behind an identity-aware proxy with mTLS
- Use managed OpenClaw hosting (ClawCloud, ClawTank) for automatic isolation if operational overhead is a concern
- Enable audit logging for compliance
- Run `openclaw doctor --security` as part of CI/CD pipeline
- Review Skill Permission Manifests before installing any ClawHub skill — check source code
- Set `disableBypassPermissionsMode` if managing multiple operators
- Schedule regular security reviews of `~/.openclaw/openclaw.json` and `exec-approvals.json`

## Quick Comparison

| Setting | Personal | Team | VPS | Production |
|---------|----------|------|-----|------------|
| Sandbox mode | off | non-main | all | all |
| Sandbox scope | — | session | session | agent |
| Sandbox workspace | — | ro | none | none |
| Sandbox network | — | (default) | none | none |
| Container root | — | writable | writable | readOnly |
| Tool deny | — | — | exec | exec |
| Tool sandbox allow | — | runtime + fs | runtime + fs | fs only |
| Elevated | off | ask (opt.) | off | off |
| Exec policy | default | allowlist | allowlist | deny |
| Exec prompt | — | on-miss | always | off |
| Gateway auth | token | password | token | trusted-proxy |
| DM policy | — | pairing | allowlist | pairing |
| Sensitive data filter | — | — | — | yes |
| Host exec possible? | yes | main only | no | no |
| Network from sandbox? | — | default | no | no |

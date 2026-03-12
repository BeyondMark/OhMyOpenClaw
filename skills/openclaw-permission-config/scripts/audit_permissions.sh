#!/usr/bin/env bash
set -euo pipefail

# audit_permissions.sh
# Execution-only: audit all five permission layers and output a structured report.
# Called by the skill decision layer with final arguments.

OUTPUT_FORMAT="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUTPUT_FORMAT="json"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if ! command -v openclaw &>/dev/null; then
  echo "Error: openclaw CLI not found" >&2
  exit 1
fi

CONFIG_PATH="$HOME/.openclaw/openclaw.json"
EXEC_APPROVALS_PATH="$HOME/.openclaw/exec-approvals.json"

# Helper: safely get a config value, return empty string if not found
get_config() {
  openclaw config get "$1" 2>/dev/null || echo ""
}

# --- Layer 1: Sandbox ---
SANDBOX_MODE=$(get_config "agents.defaults.sandbox.mode")
SANDBOX_SCOPE=$(get_config "agents.defaults.sandbox.scope")
SANDBOX_WORKSPACE_ACCESS=$(get_config "agents.defaults.sandbox.workspaceAccess")
SANDBOX_DOCKER_NETWORK=$(get_config "agents.defaults.sandbox.docker.network")

# --- Layer 2: Tool Policy ---
TOOLS_DENY=$(get_config "tools.deny")
TOOLS_SANDBOX_ALLOW=$(get_config "tools.sandbox.tools.allow")
TOOLS_EXEC_SECURITY=$(get_config "tools.exec.security")
TOOLS_EXEC_ASK=$(get_config "tools.exec.ask")

# --- Layer 3: Elevated ---
ELEVATED_ENABLED=$(get_config "tools.elevated.enabled")
ELEVATED_ALLOW_FROM=$(get_config "tools.elevated.allowFrom")

# --- Layer 4: Exec Approvals ---
EXEC_APPROVALS_FILE_EXISTS=false
EXEC_POLICY=""
EXEC_PROMPT=""
EXEC_FALLBACK=""
EXEC_AUTO_ALLOW_SKILLS=""
if [[ -f "$EXEC_APPROVALS_PATH" ]]; then
  EXEC_APPROVALS_FILE_EXISTS=true
  # Try to parse exec-approvals.json with available tools
  if command -v jq &>/dev/null; then
    # Support both flat and nested formats
    EXEC_POLICY=$(jq -r '(.defaults.security // .policy // .security) // ""' "$EXEC_APPROVALS_PATH" 2>/dev/null || echo "")
    EXEC_PROMPT=$(jq -r '(.defaults.ask // .prompt // .ask) // ""' "$EXEC_APPROVALS_PATH" 2>/dev/null || echo "")
    EXEC_FALLBACK=$(jq -r '(.defaults.askFallback // .askFallback) // ""' "$EXEC_APPROVALS_PATH" 2>/dev/null || echo "")
    EXEC_AUTO_ALLOW_SKILLS=$(jq -r '(.defaults.autoAllowSkills // .autoAllowSkills) // ""' "$EXEC_APPROVALS_PATH" 2>/dev/null || echo "")
  fi
fi

# --- Layer 5: Gateway Auth ---
GATEWAY_AUTH_MODE=$(get_config "gateway.auth.mode")
GATEWAY_AUTH_TOKEN=$(get_config "gateway.auth.token")
GATEWAY_AUTH_PASSWORD=$(get_config "gateway.auth.password")
# DM policy (check common channels)
DM_POLICY_WHATSAPP=$(get_config "channels.whatsapp.dmPolicy")
DM_POLICY_TELEGRAM=$(get_config "channels.telegram.dmPolicy")
DM_POLICY_DISCORD=$(get_config "channels.discord.dmPolicy")

# --- Risk Assessment ---
RISKS=()

# Sandbox risks
if [[ -z "$SANDBOX_MODE" || "$SANDBOX_MODE" == "off" ]]; then
  RISKS+=("MEDIUM: Sandbox is off — all tools run on host")
fi
if [[ "$SANDBOX_WORKSPACE_ACCESS" == "rw" ]]; then
  RISKS+=("MEDIUM: Sandbox has read-write workspace access")
fi

# Tool policy risks
if [[ -z "$TOOLS_DENY" ]]; then
  RISKS+=("LOW: No tool deny rules configured")
fi
if [[ -z "$TOOLS_EXEC_ASK" ]]; then
  RISKS+=("HIGH: tools.exec.ask not set in openclaw.json — gateway defaults to 'on-miss', ignoring exec-approvals.json (issue #29172). Set tools.exec.ask explicitly to avoid silent blocking")
fi
if [[ -z "$TOOLS_EXEC_SECURITY" ]]; then
  RISKS+=("MEDIUM: tools.exec.security not set — defaults may block execution")
fi

# Elevated risks
if [[ "$ELEVATED_ENABLED" == "true" ]]; then
  RISKS+=("HIGH: Elevated mode is enabled — sandboxed exec can escape to host")
fi

# Exec approvals risks
if [[ "$EXEC_POLICY" == "full" ]]; then
  RISKS+=("HIGH: Exec approvals set to full — all exec commands auto-approved")
fi
if [[ "$EXEC_APPROVALS_FILE_EXISTS" == "false" ]]; then
  RISKS+=("HIGH: exec-approvals.json does not exist — OpenClaw defaults to security=deny, askFallback=deny. All exec requests (including web search, web fetch) will be silently blocked on headless/non-GUI environments. Create this file to fix.")
fi
if [[ "$EXEC_APPROVALS_FILE_EXISTS" == "true" && "$EXEC_POLICY" == "deny" ]]; then
  RISKS+=("HIGH: exec-approvals.json policy is 'deny' — all exec requests blocked")
fi

# Gateway auth risks
if [[ -z "$GATEWAY_AUTH_MODE" ]]; then
  RISKS+=("HIGH: gateway.auth.mode not set — may cause startup failure on v2026.3.7+")
fi
if [[ -z "$GATEWAY_AUTH_TOKEN" && -z "$GATEWAY_AUTH_PASSWORD" ]]; then
  RISKS+=("HIGH: No gateway authentication configured")
fi

# DM policy risks
for channel_policy in "$DM_POLICY_WHATSAPP" "$DM_POLICY_TELEGRAM" "$DM_POLICY_DISCORD"; do
  if [[ "$channel_policy" == "open" ]]; then
    RISKS+=("HIGH: At least one channel has DM policy set to open")
    break
  fi
done

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  # Build risks JSON array
  RISKS_JSON="["
  for i in "${!RISKS[@]}"; do
    if [[ $i -gt 0 ]]; then RISKS_JSON+=","; fi
    # Escape quotes in risk text
    ESCAPED=$(echo "${RISKS[$i]}" | sed 's/"/\\"/g')
    RISKS_JSON+="\"$ESCAPED\""
  done
  RISKS_JSON+="]"

  cat <<EOF
{
  "sandbox": {
    "mode": "$SANDBOX_MODE",
    "scope": "$SANDBOX_SCOPE",
    "workspaceAccess": "$SANDBOX_WORKSPACE_ACCESS",
    "dockerNetwork": "$SANDBOX_DOCKER_NETWORK"
  },
  "toolPolicy": {
    "deny": "$TOOLS_DENY",
    "sandboxAllow": "$TOOLS_SANDBOX_ALLOW",
    "execSecurity": "$TOOLS_EXEC_SECURITY",
    "execAsk": "$TOOLS_EXEC_ASK"
  },
  "elevated": {
    "enabled": "$ELEVATED_ENABLED",
    "allowFrom": "$ELEVATED_ALLOW_FROM"
  },
  "execApprovals": {
    "fileExists": $EXEC_APPROVALS_FILE_EXISTS,
    "policy": "$EXEC_POLICY",
    "prompt": "$EXEC_PROMPT",
    "askFallback": "$EXEC_FALLBACK",
    "autoAllowSkills": "$EXEC_AUTO_ALLOW_SKILLS"
  },
  "gatewayAuth": {
    "mode": "$GATEWAY_AUTH_MODE",
    "hasToken": $([ -n "$GATEWAY_AUTH_TOKEN" ] && echo true || echo false),
    "hasPassword": $([ -n "$GATEWAY_AUTH_PASSWORD" ] && echo true || echo false),
    "dmPolicy": {
      "whatsapp": "$DM_POLICY_WHATSAPP",
      "telegram": "$DM_POLICY_TELEGRAM",
      "discord": "$DM_POLICY_DISCORD"
    }
  },
  "risks": $RISKS_JSON,
  "riskCount": ${#RISKS[@]}
}
EOF
else
  echo "=== OpenClaw Permission Audit ==="
  echo ""
  echo "--- Layer 1: Sandbox ---"
  echo "Mode: ${SANDBOX_MODE:-unset}"
  echo "Scope: ${SANDBOX_SCOPE:-unset}"
  echo "Workspace Access: ${SANDBOX_WORKSPACE_ACCESS:-unset}"
  echo "Docker Network: ${SANDBOX_DOCKER_NETWORK:-unset}"
  echo ""
  echo "--- Layer 2: Tool Policy ---"
  echo "Deny: ${TOOLS_DENY:-none}"
  echo "Sandbox Allow: ${TOOLS_SANDBOX_ALLOW:-none}"
  echo "Exec Security (tools.exec.security): ${TOOLS_EXEC_SECURITY:-unset (CAUTION: defaults may block)}"
  echo "Exec Ask (tools.exec.ask): ${TOOLS_EXEC_ASK:-unset (CAUTION: defaults to on-miss, issue #29172)}"
  echo ""
  echo "--- Layer 3: Elevated ---"
  echo "Enabled: ${ELEVATED_ENABLED:-unset}"
  echo "Allow From: ${ELEVATED_ALLOW_FROM:-none}"
  echo ""
  echo "--- Layer 4: Exec Approvals ---"
  echo "File exists: $EXEC_APPROVALS_FILE_EXISTS"
  if [[ "$EXEC_APPROVALS_FILE_EXISTS" == "false" ]]; then
    echo "  WARNING: exec-approvals.json not found — defaults to deny all exec"
  fi
  echo "Policy: ${EXEC_POLICY:-unset (defaults to deny)}"
  echo "Prompt: ${EXEC_PROMPT:-unset (defaults to on-miss)}"
  echo "Ask Fallback: ${EXEC_FALLBACK:-unset (defaults to deny)}"
  echo "Auto-allow Skills: ${EXEC_AUTO_ALLOW_SKILLS:-unset}"
  echo ""
  echo "--- Layer 5: Gateway Auth ---"
  echo "Auth Mode: ${GATEWAY_AUTH_MODE:-unset}"
  echo "Has Token: $([ -n "$GATEWAY_AUTH_TOKEN" ] && echo yes || echo no)"
  echo "Has Password: $([ -n "$GATEWAY_AUTH_PASSWORD" ] && echo yes || echo no)"
  echo "DM Policy (WhatsApp): ${DM_POLICY_WHATSAPP:-unset}"
  echo "DM Policy (Telegram): ${DM_POLICY_TELEGRAM:-unset}"
  echo "DM Policy (Discord): ${DM_POLICY_DISCORD:-unset}"
  echo ""
  echo "--- Risk Assessment ---"
  if [[ ${#RISKS[@]} -eq 0 ]]; then
    echo "No risks detected."
  else
    echo "Found ${#RISKS[@]} risk(s):"
    for risk in "${RISKS[@]}"; do
      echo "  - $risk"
    done
  fi
fi

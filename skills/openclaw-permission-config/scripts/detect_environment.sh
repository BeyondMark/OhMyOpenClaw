#!/usr/bin/env bash
set -euo pipefail

# detect_environment.sh
# Execution-only: detect OpenClaw CLI, version, and existing config.
# Called by the skill decision layer with final arguments.

OUTPUT_FORMAT="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUTPUT_FORMAT="json"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

INSTALLED=false
VERSION=""
CONFIG_EXISTS=false
CONFIG_PATH="$HOME/.openclaw/openclaw.json"
ENV_EXISTS=false
ENV_PATH="$HOME/.openclaw/.env"
EXEC_APPROVALS_EXISTS=false
EXEC_APPROVALS_PATH="$HOME/.openclaw/exec-approvals.json"

# Check if openclaw CLI is installed
if command -v openclaw &>/dev/null; then
  INSTALLED=true
  VERSION=$(openclaw --version 2>/dev/null | head -n 1 || echo "unknown")
fi

# Check config files
if [[ -f "$CONFIG_PATH" ]]; then
  CONFIG_EXISTS=true
fi

if [[ -f "$ENV_PATH" ]]; then
  ENV_EXISTS=true
fi

if [[ -f "$EXEC_APPROVALS_PATH" ]]; then
  EXEC_APPROVALS_EXISTS=true
fi

# Detect gateway mode if config exists
GATEWAY_MODE=""
if [[ "$INSTALLED" == "true" && "$CONFIG_EXISTS" == "true" ]]; then
  GATEWAY_MODE=$(openclaw config get gateway.mode 2>/dev/null || echo "")
fi

# Detect sandbox mode if config exists
SANDBOX_MODE=""
if [[ "$INSTALLED" == "true" && "$CONFIG_EXISTS" == "true" ]]; then
  SANDBOX_MODE=$(openclaw config get agents.defaults.sandbox.mode 2>/dev/null || echo "")
fi

# Detect gateway auth mode
GATEWAY_AUTH_MODE=""
if [[ "$INSTALLED" == "true" && "$CONFIG_EXISTS" == "true" ]]; then
  GATEWAY_AUTH_MODE=$(openclaw config get gateway.auth.mode 2>/dev/null || echo "")
fi

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  cat <<EOF
{
  "installed": $INSTALLED,
  "version": "$VERSION",
  "config_exists": $CONFIG_EXISTS,
  "config_path": "$CONFIG_PATH",
  "env_exists": $ENV_EXISTS,
  "env_path": "$ENV_PATH",
  "exec_approvals_exists": $EXEC_APPROVALS_EXISTS,
  "exec_approvals_path": "$EXEC_APPROVALS_PATH",
  "gateway_mode": "$GATEWAY_MODE",
  "sandbox_mode": "$SANDBOX_MODE",
  "gateway_auth_mode": "$GATEWAY_AUTH_MODE"
}
EOF
else
  echo "=== OpenClaw Environment ==="
  echo "Installed: $INSTALLED"
  echo "Version: $VERSION"
  echo "Config exists: $CONFIG_EXISTS ($CONFIG_PATH)"
  echo "Env exists: $ENV_EXISTS ($ENV_PATH)"
  echo "Exec approvals exists: $EXEC_APPROVALS_EXISTS ($EXEC_APPROVALS_PATH)"
  echo "Gateway mode: ${GATEWAY_MODE:-unset}"
  echo "Sandbox mode: ${SANDBOX_MODE:-unset}"
  echo "Gateway auth mode: ${GATEWAY_AUTH_MODE:-unset}"
fi

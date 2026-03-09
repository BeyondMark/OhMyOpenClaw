#!/usr/bin/env bash
set -euo pipefail

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_cmd openclaw

echo "[1/5] Inspect current gateway.mode"
current_mode="$(openclaw config get gateway.mode 2>/dev/null || true)"
if [[ "${current_mode}" == "local" ]]; then
  echo "gateway.mode is already local"
else
  echo "gateway.mode is '${current_mode:-unset}', setting it to local"
  openclaw config set gateway.mode local
fi

echo "[2/5] Validate config"
openclaw config validate

echo "[3/5] Restart gateway service"
openclaw gateway restart

echo "[4/5] Wait for service to come back"
sleep 3

echo "[5/5] Verify runtime state"
openclaw status

echo
echo "Recent gateway.err.log lines:"
tail -n 20 "${HOME}/.openclaw/logs/gateway.err.log" 2>/dev/null || true

echo
echo "Recent gateway.log lines:"
tail -n 20 "${HOME}/.openclaw/logs/gateway.log" 2>/dev/null || true

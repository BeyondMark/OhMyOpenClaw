#!/usr/bin/env bash
set -euo pipefail

# apply_config.sh
# Execution-only: write a single config key-value pair via openclaw config set
# or update exec-approvals.json for exec approval settings.
# Called by the skill decision layer with final, explicit values.

TARGET="openclaw"
KEY=""
VALUE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --key) KEY="$2"; shift 2 ;;
    --value) VALUE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$KEY" ]]; then
  echo "Error: --key is required" >&2
  exit 1
fi

if [[ -z "$VALUE" ]]; then
  echo "Error: --value is required" >&2
  exit 1
fi

if [[ "$TARGET" == "openclaw" ]]; then
  # Use openclaw config set for main config
  if ! command -v openclaw &>/dev/null; then
    echo "Error: openclaw CLI not found" >&2
    exit 1
  fi

  # Get the current value for rollback reference
  OLD_VALUE=$(openclaw config get "$KEY" 2>/dev/null || echo "")

  echo "Setting $KEY = $VALUE"
  if openclaw config set "$KEY" "$VALUE" 2>&1; then
    echo "OK: $KEY set to $VALUE"

    # Validate after setting
    if ! openclaw config validate 2>&1; then
      echo "Warning: config validation failed after setting $KEY" >&2
      echo "Previous value was: ${OLD_VALUE:-unset}" >&2
      echo "Consider rolling back with: openclaw config set $KEY \"$OLD_VALUE\"" >&2
      exit 2
    fi
  else
    echo "Error: failed to set $KEY" >&2
    exit 1
  fi

elif [[ "$TARGET" == "exec-approvals" ]]; then
  # Handle exec-approvals.json separately
  EXEC_PATH="$HOME/.openclaw/exec-approvals.json"

  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required for exec-approvals configuration" >&2
    exit 1
  fi

  # Ensure parent directory exists
  mkdir -p "$(dirname "$EXEC_PATH")"

  # Create file if it doesn't exist
  if [[ ! -f "$EXEC_PATH" ]]; then
    echo "{}" > "$EXEC_PATH"
  fi

  # Update the key — supports nested keys like "defaults.security"
  echo "Setting exec-approvals $KEY = $VALUE"
  TEMP=$(mktemp)

  # Convert dot-notation key to a jq path array, e.g. defaults.security -> ["defaults","security"]
  JQ_PATH_JSON=$(printf '%s' "$KEY" | jq -Rc 'split(".")')

  # Determine if value should be a number, boolean, or string
  case "$VALUE" in
    true|false)
      JQ_EXPR="setpath(\$p; $VALUE)"
      ;;
    [0-9]*)
      # Check if it's a pure integer
      if [[ "$VALUE" =~ ^[0-9]+$ ]]; then
        JQ_EXPR="setpath(\$p; $VALUE)"
      else
        JQ_EXPR="setpath(\$p; \$v)"
      fi
      ;;
    *)
      JQ_EXPR="setpath(\$p; \$v)"
      ;;
  esac

  if jq --argjson p "$JQ_PATH_JSON" --arg v "$VALUE" "$JQ_EXPR" "$EXEC_PATH" > "$TEMP" 2>&1; then
    mv "$TEMP" "$EXEC_PATH"
    echo "OK: exec-approvals $KEY set to $VALUE"
  else
    rm -f "$TEMP"
    echo "Error: failed to update exec-approvals.json" >&2
    exit 1
  fi

else
  echo "Error: unknown target '$TARGET'. Use 'openclaw' or 'exec-approvals'." >&2
  exit 1
fi

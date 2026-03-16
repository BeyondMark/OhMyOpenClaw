#!/usr/bin/env bash
# manage_profile.sh — Check, create, or list OpenClaw browser profiles.
#
# Usage:
#   ./scripts/manage_profile.sh --check <profile-name> [--json]
#   ./scripts/manage_profile.sh --create <profile-name> [--json]
#   ./scripts/manage_profile.sh --list [--json]
#
# Profile naming rules:
#   - lowercase letters, digits, and hyphens only
#   - no underscores
#   - recommended format: {provider}-{sequence} (e.g., hostclub-001)
#
# Exit codes:
#   0  success
#   1  usage error or invalid profile name
#   2  profile not found (for --check)
#   3  profile creation failed
#   4  openclaw CLI not available

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/log.sh" ]]; then
  source "$SCRIPT_DIR/log.sh"
fi

ACTION=""
PROFILE_NAME=""
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) ACTION="check"; PROFILE_NAME="$2"; shift 2 ;;
    --create) ACTION="create"; PROFILE_NAME="$2"; shift 2 ;;
    --list) ACTION="list"; shift ;;
    --json) JSON_OUTPUT=true; shift ;;
    --help|-h)
      echo "Usage: $0 --check|--create <profile-name> | --list [--json]"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ACTION" ]]; then
  echo "Error: specify --check, --create, or --list" >&2
  exit 1
fi

# Validate profile name format
validate_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
    if $JSON_OUTPUT; then
      echo "{\"success\": false, \"error\": \"Invalid profile name '$name'. Use only lowercase letters, digits, and hyphens.\"}"
    else
      echo "Error: Invalid profile name '$name'. Use only lowercase letters, digits, and hyphens." >&2
    fi
    exit 1
  fi
}

# Check openclaw CLI availability
if ! command -v openclaw &>/dev/null; then
  if $JSON_OUTPUT; then
    echo '{"success": false, "error": "openclaw CLI not found in PATH"}'
  else
    echo "Error: openclaw CLI not found in PATH" >&2
  fi
  exit 4
fi

case "$ACTION" in
  check)
    validate_name "$PROFILE_NAME"
    if openclaw browser profiles 2>/dev/null | grep -q "^${PROFILE_NAME}\(:\|$\)"; then
      [[ "$(type -t log_info 2>/dev/null)" == "function" ]] && log_info "preflight" 6 "Profile exists: $PROFILE_NAME"
      if $JSON_OUTPUT; then
        echo "{\"success\": true, \"exists\": true, \"profileName\": \"$PROFILE_NAME\"}"
      else
        echo "Profile '$PROFILE_NAME' exists."
      fi
      exit 0
    else
      [[ "$(type -t log_info 2>/dev/null)" == "function" ]] && log_info "preflight" 6 "Profile not found: $PROFILE_NAME"
      if $JSON_OUTPUT; then
        echo "{\"success\": true, \"exists\": false, \"profileName\": \"$PROFILE_NAME\"}"
      else
        echo "Profile '$PROFILE_NAME' not found."
      fi
      exit 2
    fi
    ;;

  create)
    validate_name "$PROFILE_NAME"
    _try_create() {
      openclaw browser create-profile --name "$PROFILE_NAME" 2>&1
    }
    if $JSON_OUTPUT; then
      if cli_output=$(_try_create); then
        [[ "$(type -t log_info 2>/dev/null)" == "function" ]] && log_info "preflight" 6 "Profile created: $PROFILE_NAME"
        echo "{\"success\": true, \"created\": true, \"profileName\": \"$PROFILE_NAME\"}"
        exit 0
      else
        # Retry once after short delay (race condition after delete)
        [[ "$(type -t log_warn 2>/dev/null)" == "function" ]] && log_warn "preflight" 6 "Profile creation failed, retrying after 2s" "{\"profile\":\"$PROFILE_NAME\"}"
        sleep 2
        if cli_output=$(_try_create); then
          [[ "$(type -t log_info 2>/dev/null)" == "function" ]] && log_info "preflight" 6 "Profile created on retry: $PROFILE_NAME"
          echo "{\"success\": true, \"created\": true, \"profileName\": \"$PROFILE_NAME\", \"retried\": true}"
          exit 0
        else
          [[ "$(type -t log_error 2>/dev/null)" == "function" ]] && log_error "preflight" 6 "Profile creation failed after retry" "{\"profile\":\"$PROFILE_NAME\"}"
          echo "{\"success\": false, \"error\": \"Failed to create profile '$PROFILE_NAME' (retried once)\"}"
          exit 3
        fi
      fi
    else
      if _try_create; then
        [[ "$(type -t log_info 2>/dev/null)" == "function" ]] && log_info "preflight" 6 "Profile created: $PROFILE_NAME"
        echo "Profile '$PROFILE_NAME' created."
        exit 0
      else
        [[ "$(type -t log_warn 2>/dev/null)" == "function" ]] && log_warn "preflight" 6 "Profile creation failed, retrying after 2s" "{\"profile\":\"$PROFILE_NAME\"}"
        sleep 2
        if _try_create; then
          [[ "$(type -t log_info 2>/dev/null)" == "function" ]] && log_info "preflight" 6 "Profile created on retry: $PROFILE_NAME"
          echo "Profile '$PROFILE_NAME' created (retried)."
          exit 0
        else
          [[ "$(type -t log_error 2>/dev/null)" == "function" ]] && log_error "preflight" 6 "Profile creation failed after retry" "{\"profile\":\"$PROFILE_NAME\"}"
          echo "Error: Failed to create profile '$PROFILE_NAME' (retried once)" >&2
          exit 3
        fi
      fi
    fi
    ;;

  list)
    profiles=$(openclaw browser profiles 2>/dev/null || true)
    if $JSON_OUTPUT; then
      # Extract profile names only — output lines are "name: status (info)" or just "name"
      echo "$profiles" | sed -n 's/^\([a-z0-9][a-z0-9-]*\).*/\1/p' | jq -R -s 'split("\n") | map(select(. != "")) | {success: true, profiles: .}'
    else
      echo "$profiles"
    fi
    exit 0
    ;;
esac

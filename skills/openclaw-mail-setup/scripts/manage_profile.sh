#!/usr/bin/env bash
# manage_profile.sh — Check, create, or list browser profiles (storageState directories).
#
# Profiles are stored as directories under ~/.openclaw/mail/profiles/{name}/.
# Each profile directory may contain a storage-state.json file with Playwright
# storageState data (cookies, localStorage) for session persistence.
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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/log.sh" ]]; then
  source "$SCRIPT_DIR/log.sh"
fi

PROFILES_DIR="${OPENCLAW_MAIL_PROFILES_DIR:-$HOME/.openclaw/mail/profiles}"
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

case "$ACTION" in
  check)
    validate_name "$PROFILE_NAME"
    PROFILE_PATH="$PROFILES_DIR/$PROFILE_NAME"
    STATE_FILE="$PROFILE_PATH/storage-state.json"

    if [[ -d "$PROFILE_PATH" ]]; then
      has_state=false
      [[ -f "$STATE_FILE" ]] && has_state=true

      [[ "$(type -t log_info 2>/dev/null)" == "function" ]] && log_info "preflight" 6 "Profile exists: $PROFILE_NAME" "{\"hasStorageState\":$has_state}"
      if $JSON_OUTPUT; then
        echo "{\"success\": true, \"exists\": true, \"profileName\": \"$PROFILE_NAME\", \"profilePath\": \"$PROFILE_PATH\", \"hasStorageState\": $has_state}"
      else
        echo "Profile '$PROFILE_NAME' exists (storageState: $has_state)."
      fi
      exit 0
    else
      [[ "$(type -t log_info 2>/dev/null)" == "function" ]] && log_info "preflight" 6 "Profile not found: $PROFILE_NAME"
      if $JSON_OUTPUT; then
        echo "{\"success\": true, \"exists\": false, \"profileName\": \"$PROFILE_NAME\", \"profilePath\": \"$PROFILE_PATH\", \"hasStorageState\": false}"
      else
        echo "Profile '$PROFILE_NAME' not found."
      fi
      exit 2
    fi
    ;;

  create)
    validate_name "$PROFILE_NAME"
    PROFILE_PATH="$PROFILES_DIR/$PROFILE_NAME"

    if [[ -d "$PROFILE_PATH" ]]; then
      [[ "$(type -t log_info 2>/dev/null)" == "function" ]] && log_info "preflight" 6 "Profile already exists: $PROFILE_NAME"
      if $JSON_OUTPUT; then
        echo "{\"success\": true, \"created\": false, \"profileName\": \"$PROFILE_NAME\", \"profilePath\": \"$PROFILE_PATH\", \"message\": \"Profile already exists\"}"
      else
        echo "Profile '$PROFILE_NAME' already exists."
      fi
      exit 0
    fi

    if mkdir -p "$PROFILE_PATH" 2>/dev/null; then
      chmod 700 "$PROFILE_PATH"
      [[ "$(type -t log_info 2>/dev/null)" == "function" ]] && log_info "preflight" 6 "Profile created: $PROFILE_NAME"
      if $JSON_OUTPUT; then
        echo "{\"success\": true, \"created\": true, \"profileName\": \"$PROFILE_NAME\", \"profilePath\": \"$PROFILE_PATH\"}"
      else
        echo "Profile '$PROFILE_NAME' created at $PROFILE_PATH"
      fi
      exit 0
    else
      [[ "$(type -t log_error 2>/dev/null)" == "function" ]] && log_error "preflight" 6 "Profile creation failed" "{\"profile\":\"$PROFILE_NAME\"}"
      if $JSON_OUTPUT; then
        echo "{\"success\": false, \"error\": \"Failed to create profile directory '$PROFILE_PATH'\"}"
      else
        echo "Error: Failed to create profile directory '$PROFILE_PATH'" >&2
      fi
      exit 3
    fi
    ;;

  list)
    if [[ ! -d "$PROFILES_DIR" ]]; then
      if $JSON_OUTPUT; then
        echo '{"success": true, "profiles": []}'
      else
        echo "No profiles directory found."
      fi
      exit 0
    fi

    profiles=()
    for dir in "$PROFILES_DIR"/*/; do
      [[ -d "$dir" ]] || continue
      name="$(basename "$dir")"
      profiles+=("$name")
    done

    if $JSON_OUTPUT; then
      printf '%s\n' "${profiles[@]}" | jq -R -s 'split("\n") | map(select(. != "")) | {success: true, profiles: .}'
    else
      if [[ ${#profiles[@]} -eq 0 ]]; then
        echo "No profiles found."
      else
        for p in "${profiles[@]}"; do
          has_state="no"
          [[ -f "$PROFILES_DIR/$p/storage-state.json" ]] && has_state="yes"
          echo "$p (storageState: $has_state)"
        done
      fi
    fi
    exit 0
    ;;
esac

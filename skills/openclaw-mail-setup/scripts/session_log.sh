#!/usr/bin/env bash
# session_log.sh — Standalone logging script for agent to call at key decision points.
#
# Usage:
#   ./scripts/session_log.sh \
#     --session <session-id> \
#     --domain <domain> \
#     --phase <phase-name> \
#     --step <step-number> \
#     --level <DEBUG|INFO|WARN|ERROR> \
#     --msg <message> \
#     [--data <json-object>] \
#     [--json]
#
# Example:
#   ./scripts/session_log.sh \
#     --session mail-example.com-20260316-093000 \
#     --domain example.com \
#     --phase login \
#     --step 8 \
#     --level INFO \
#     --msg "Login state detected: already logged in" \
#     --json
#
# Exit codes:
#   0  log entry written
#   1  usage error (missing required arguments)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SESSION=""
DOMAIN=""
PHASE=""
STEP=0
LEVEL="INFO"
MSG=""
DATA="null"
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION="$2"; shift 2 ;;
    --domain)  DOMAIN="$2"; shift 2 ;;
    --phase)   PHASE="$2"; shift 2 ;;
    --step)    STEP="$2"; shift 2 ;;
    --level)   LEVEL="$2"; shift 2 ;;
    --msg)     MSG="$2"; shift 2 ;;
    --data)    DATA="$2"; shift 2 ;;
    --json)    JSON_OUTPUT=true; shift ;;
    --help|-h)
      echo "Usage: $0 --session <id> --domain <domain> --phase <phase> --step <n> --level <level> --msg <message> [--data <json>] [--json]"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Validate required fields
missing=""
[[ -z "$SESSION" ]] && missing="${missing} --session"
[[ -z "$DOMAIN" ]]  && missing="${missing} --domain"
[[ -z "$PHASE" ]]   && missing="${missing} --phase"
[[ -z "$MSG" ]]     && missing="${missing} --msg"

if [[ -n "$missing" ]]; then
  echo "Error: missing required arguments:${missing}" >&2
  exit 1
fi

# Validate step is a number
if ! [[ "$STEP" =~ ^[0-9]+$ ]]; then
  echo "Error: --step must be a non-negative integer" >&2
  exit 1
fi

# Validate level (bash 3.2 compatible — no ${^^})
LEVEL="$(printf '%s' "$LEVEL" | tr '[:lower:]' '[:upper:]')"
case "$LEVEL" in
  DEBUG|INFO|WARN|ERROR) ;;
  *)
    echo "Error: --level must be DEBUG, INFO, WARN, or ERROR" >&2
    exit 1
    ;;
esac

# Suppress stderr from log.sh in this context (agent reads stdout)
export LOG_QUIET=1
export LOG_SESSION="$SESSION"

# Source the shared logging library
source "$SCRIPT_DIR/log.sh"
log_init --domain "$DOMAIN" --session "$SESSION"
log_set_script "session_log.sh"

# Write the log entry (LEVEL already uppercased above)
case "$LEVEL" in
  DEBUG) log_debug "$PHASE" "$STEP" "$MSG" "$DATA" ;;
  INFO)  log_info  "$PHASE" "$STEP" "$MSG" "$DATA" ;;
  WARN)  log_warn  "$PHASE" "$STEP" "$MSG" "$DATA" ;;
  ERROR) log_error "$PHASE" "$STEP" "$MSG" "$DATA" ;;
esac

# Return confirmation
if $JSON_OUTPUT; then
  LOG_PATH="$(log_file_path)"
  if command -v jq &>/dev/null; then
    jq -n \
      --arg success "true" \
      --arg session "$SESSION" \
      --arg logFile "$LOG_PATH" \
      '{success: true, session: $session, logFile: $logFile}'
  else
    echo "{\"success\":true,\"session\":\"${SESSION}\",\"logFile\":\"${LOG_PATH}\"}"
  fi
else
  echo "Logged: [${LEVEL}] ${PHASE}:${STEP} ${MSG}"
fi

exit 0

#!/usr/bin/env bash
# log.sh — Shared logging library for openclaw-mail-setup scripts.
#
# Usage (source from another script):
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/log.sh"
#   log_init --domain example.com [--session <id>]
#   log_info "login" 8 "Login state detected: logged in"
#   log_warn "login" 9 "Login failed" '{"attempts_remaining": 4}'
#   log_error "login" 9 "Wrong credentials" '{"url": "https://..."}'
#
# Environment variables:
#   LOG_LEVEL    — minimum level to record: DEBUG|INFO|WARN|ERROR (default: INFO)
#   LOG_QUIET    — set to 1 to suppress stderr output (file logging still works)
#   LOG_DIR      — override log directory (default: ~/.openclaw/mail/logs)
#   LOG_SESSION  — override session ID (default: auto-generated)
#
# Log format: JSONL (one JSON object per line)
#   {"ts":"2026-03-16T09:30:00Z","level":"INFO","session":"mail-example.com-20260316-093000","phase":"login","step":8,"script":"check_config.sh","msg":"...","data":{}}

# Guard against double-sourcing
if [[ -n "${_OPENCLAW_LOG_LOADED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_OPENCLAW_LOG_LOADED=1

_LOG_LEVEL="${LOG_LEVEL:-INFO}"
_LOG_QUIET="${LOG_QUIET:-0}"
_LOG_DIR="${LOG_DIR:-$HOME/.openclaw/mail/logs}"
_LOG_FILE=""
_LOG_SESSION=""
_LOG_DOMAIN=""
_LOG_SCRIPT_NAME=""

# Level to numeric for comparison
_log_level_num() {
  case "${1^^}" in
    DEBUG) echo 0 ;;
    INFO)  echo 1 ;;
    WARN)  echo 2 ;;
    ERROR) echo 3 ;;
    *)     echo 1 ;;
  esac
}

# Initialize logging session.
# Usage: log_init --domain <domain> [--session <id>]
log_init() {
  local domain="" session=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)  domain="$2"; shift 2 ;;
      --session) session="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  _LOG_DOMAIN="${domain:-unknown}"

  if [[ -n "$session" ]]; then
    _LOG_SESSION="$session"
  elif [[ -n "${LOG_SESSION:-}" ]]; then
    _LOG_SESSION="$LOG_SESSION"
  else
    _LOG_SESSION="mail-${_LOG_DOMAIN}-$(date -u +%Y%m%d-%H%M%S)"
  fi

  # Determine calling script name
  _LOG_SCRIPT_NAME="$(basename "${BASH_SOURCE[2]:-${BASH_SOURCE[1]:-unknown}}")"

  # Ensure log directory exists
  mkdir -p "$_LOG_DIR" 2>/dev/null || true

  # Set log file path
  _LOG_FILE="${_LOG_DIR}/${_LOG_SESSION}.jsonl"

  # Write session start marker
  _log_write "INFO" "system" 0 "Log session started" \
    "{\"domain\":\"${_LOG_DOMAIN}\",\"script\":\"${_LOG_SCRIPT_NAME}\",\"logFile\":\"${_LOG_FILE}\"}"
}

# Set script name (call from each script after sourcing if log_init was already called elsewhere)
log_set_script() {
  _LOG_SCRIPT_NAME="${1:-unknown}"
}

# Internal: write a single JSONL line
_log_write() {
  local level="$1" phase="$2" step="$3" msg="$4" data="${5:-null}"

  # Check level threshold
  local threshold current
  threshold=$(_log_level_num "$_LOG_LEVEL")
  current=$(_log_level_num "$level")
  if [[ "$current" -lt "$threshold" ]]; then
    return 0
  fi

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Build JSON using jq if available, fallback to printf
  local line
  if command -v jq &>/dev/null; then
    line=$(jq -cn \
      --arg ts "$ts" \
      --arg level "$level" \
      --arg session "$_LOG_SESSION" \
      --arg phase "$phase" \
      --argjson step "$step" \
      --arg script "$_LOG_SCRIPT_NAME" \
      --arg msg "$msg" \
      --argjson data "$data" \
      '{ts:$ts, level:$level, session:$session, phase:$phase, step:$step, script:$script, msg:$msg, data:$data}')
  else
    # Fallback: escape quotes in msg
    local escaped_msg="${msg//\"/\\\"}"
    line="{\"ts\":\"${ts}\",\"level\":\"${level}\",\"session\":\"${_LOG_SESSION}\",\"phase\":\"${phase}\",\"step\":${step},\"script\":\"${_LOG_SCRIPT_NAME}\",\"msg\":\"${escaped_msg}\",\"data\":${data}}"
  fi

  # Write to file (if initialized)
  if [[ -n "$_LOG_FILE" ]]; then
    echo "$line" >> "$_LOG_FILE" 2>/dev/null || true
  fi

  # Write to stderr (unless quiet)
  if [[ "$_LOG_QUIET" != "1" ]]; then
    echo "[${level}] ${phase}:${step} ${msg}" >&2
  fi
}

# Public logging functions
# Usage: log_info <phase> <step> <message> [<data-json>]
log_info() {
  _log_write "INFO" "${1:-}" "${2:-0}" "${3:-}" "${4:-null}"
}

log_warn() {
  _log_write "WARN" "${1:-}" "${2:-0}" "${3:-}" "${4:-null}"
}

log_error() {
  _log_write "ERROR" "${1:-}" "${2:-0}" "${3:-}" "${4:-null}"
}

log_debug() {
  _log_write "DEBUG" "${1:-}" "${2:-0}" "${3:-}" "${4:-null}"
}

# Convenience: get current session ID
log_session_id() {
  echo "$_LOG_SESSION"
}

# Convenience: get current log file path
log_file_path() {
  echo "$_LOG_FILE"
}

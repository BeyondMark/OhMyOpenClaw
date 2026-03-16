#!/usr/bin/env bash
# update_domain_status.sh — Update domain table after mailbox creation.
#
# Usage:
#   ./scripts/update_domain_status.sh \
#     --domain <domain> \
#     --mailbox <email> \
#     --status <created|trial_started|already_exists|quota_reached|failed|needs_human> \
#     [--json]
#
# Updates the domain entry in ~/.openclaw/mail/domains.json with:
#   - mailboxes: array of created email addresses (appends new, deduplicates)
#   - lastMailboxCreatedAt: ISO 8601 timestamp of most recent creation (or null)
#   - lastStatus: the result status
#   - lastUpdatedAt: current timestamp
#
# Exit codes:
#   0  update succeeded
#   1  usage error
#   2  domains.json not found
#   3  domain not found in table
#   4  write failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/log.sh" ]]; then
  source "$SCRIPT_DIR/log.sh"
fi

CONFIG_DIR="${OPENCLAW_MAIL_CONFIG_DIR:-$HOME/.openclaw/mail}"
DOMAINS_FILE="$CONFIG_DIR/domains.json"
DOMAIN=""
MAILBOX=""
STATUS=""
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2 ;;
    --mailbox) MAILBOX="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --json) JSON_OUTPUT=true; shift ;;
    --help|-h)
      echo "Usage: $0 --domain <domain> --mailbox <email> --status <status> [--json]"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$DOMAIN" ]] || [[ -z "$STATUS" ]]; then
  echo "Error: --domain and --status are required" >&2
  exit 1
fi

if [[ ! -f "$DOMAINS_FILE" ]]; then
  if $JSON_OUTPUT; then
    echo '{"success": false, "error": "domains.json not found"}'
  else
    echo "Error: $DOMAINS_FILE not found" >&2
  fi
  exit 2
fi

# Check domain exists in table
domain_exists=$(jq -r --arg d "$DOMAIN" '.domains[$d] // empty' "$DOMAINS_FILE")
if [[ -z "$domain_exists" ]]; then
  if $JSON_OUTPUT; then
    echo "{\"success\": false, \"error\": \"Domain '$DOMAIN' not found in domain table\"}"
  else
    echo "Error: Domain '$DOMAIN' not found in domain table" >&2
  fi
  exit 3
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build the jq update expression based on status
case "$STATUS" in
  created|trial_started)
    # Append mailbox to mailboxes array (deduplicate), update timestamp
    JQ_EXPR='
      .domains[$d].mailboxes = ((.domains[$d].mailboxes // []) + [$mailbox] | unique) |
      .domains[$d].lastMailboxCreatedAt = $now |
      .domains[$d].lastStatus = $status |
      .domains[$d].lastUpdatedAt = $now'
    ;;
  already_exists)
    # Ensure mailbox is in the array but do not update creation timestamp
    JQ_EXPR='
      .domains[$d].mailboxes = ((.domains[$d].mailboxes // []) + [$mailbox] | unique) |
      .domains[$d].lastStatus = $status |
      .domains[$d].lastUpdatedAt = $now'
    ;;
  *)
    # quota_reached, failed, needs_human — only update status fields, preserve mailboxes
    JQ_EXPR='
      .domains[$d].mailboxes = (.domains[$d].mailboxes // []) |
      .domains[$d].lastStatus = $status |
      .domains[$d].lastUpdatedAt = $now'
    ;;
esac

# Update the domain entry
tmp_file=$(mktemp)
jq --arg d "$DOMAIN" \
   --arg mailbox "$MAILBOX" \
   --arg status "$STATUS" \
   --arg now "$NOW" \
   "$JQ_EXPR" \
   "$DOMAINS_FILE" > "$tmp_file" && mv "$tmp_file" "$DOMAINS_FILE"

if [[ $? -eq 0 ]]; then
  [[ "$(type -t log_info 2>/dev/null)" == "function" ]] && log_info "result" 23 "Domain status updated" "{\"domain\":\"$DOMAIN\",\"status\":\"$STATUS\"}"
  if $JSON_OUTPUT; then
    echo "{\"success\": true, \"domain\": \"$DOMAIN\", \"status\": \"$STATUS\", \"updatedAt\": \"$NOW\"}"
  else
    echo "Domain '$DOMAIN' updated: status=$STATUS"
  fi
  exit 0
else
  [[ "$(type -t log_error 2>/dev/null)" == "function" ]] && log_error "result" 23 "Failed to write domains.json" "{\"domain\":\"$DOMAIN\"}"
  if $JSON_OUTPUT; then
    echo '{"success": false, "error": "Failed to write domains.json"}'
  else
    echo "Error: Failed to write $DOMAINS_FILE" >&2
  fi
  exit 4
fi

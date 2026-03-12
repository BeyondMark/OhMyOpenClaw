#!/usr/bin/env bash
# decrypt_password.sh — Decrypt AES-256-CBC encrypted password from account table.
#
# Usage:
#   ./scripts/decrypt_password.sh --account-id <id> [--json]
#
# Requires:
#   - OPENCLAW_SECRET_KEY environment variable (AES-256-CBC key)
#   - openssl command available
#   - Account table at ~/.openclaw/mail/accounts.json
#
# Exit codes:
#   0  decryption succeeded
#   1  usage error or missing arguments
#   2  OPENCLAW_SECRET_KEY not set
#   3  account not found
#   4  decryption failed

set -euo pipefail

CONFIG_DIR="${OPENCLAW_MAIL_CONFIG_DIR:-$HOME/.openclaw/mail}"
ACCOUNTS_FILE="$CONFIG_DIR/accounts.json"
ACCOUNT_ID=""
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account-id) ACCOUNT_ID="$2"; shift 2 ;;
    --json) JSON_OUTPUT=true; shift ;;
    --help|-h)
      echo "Usage: $0 --account-id <id> [--json]"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ACCOUNT_ID" ]]; then
  echo "Error: --account-id is required" >&2
  exit 1
fi

if [[ -z "${OPENCLAW_SECRET_KEY:-}" ]]; then
  if $JSON_OUTPUT; then
    echo '{"success": false, "error": "OPENCLAW_SECRET_KEY environment variable is not set"}'
  else
    echo "Error: OPENCLAW_SECRET_KEY environment variable is not set" >&2
  fi
  exit 2
fi

# Check accounts file exists
if [[ ! -f "$ACCOUNTS_FILE" ]]; then
  if $JSON_OUTPUT; then
    echo "{\"success\": false, \"error\": \"Account table not found: $ACCOUNTS_FILE\"}"
  else
    echo "Error: Account table not found: $ACCOUNTS_FILE" >&2
  fi
  exit 3
fi

# Read encrypted password from account table
encrypted=$(jq -r --arg id "$ACCOUNT_ID" '.accounts[$id].passwordEncrypted // empty' "$ACCOUNTS_FILE")

if [[ -z "$encrypted" ]]; then
  if $JSON_OUTPUT; then
    echo "{\"success\": false, \"error\": \"Account '$ACCOUNT_ID' not found or has no passwordEncrypted field\"}"
  else
    echo "Error: Account '$ACCOUNT_ID' not found or has no passwordEncrypted field" >&2
  fi
  exit 3
fi

# Decrypt using AES-256-CBC
plaintext=$(echo "$encrypted" | openssl enc -aes-256-cbc -d -a -pass "pass:$OPENCLAW_SECRET_KEY" 2>/dev/null) || {
  if $JSON_OUTPUT; then
    echo '{"success": false, "error": "Decryption failed. Check OPENCLAW_SECRET_KEY and encrypted value."}'
  else
    echo "Error: Decryption failed" >&2
  fi
  exit 4
}

if $JSON_OUTPUT; then
  # Output password in JSON; the caller must handle it securely
  jq -n --arg pw "$plaintext" '{"success": true, "password": $pw}'
else
  echo "$plaintext"
fi

exit 0

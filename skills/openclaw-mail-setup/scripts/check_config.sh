#!/usr/bin/env bash
# check_config.sh — Validate account table and domain table exist and are well-formed.
#
# Usage:
#   ./scripts/check_config.sh [--json]
#
# Checks:
#   1. Account table file exists at ~/.openclaw/mail/accounts.json
#   2. Domain table file exists at ~/.openclaw/mail/domains.json
#   3. Both files are valid JSON
#   4. Account table has at least one account entry
#   5. Each account has required fields: provider, loginUrl, username, passwordEncrypted, browserProfile
#
# Exit codes:
#   0  config valid
#   1  usage error
#   2  config files not found (direct mode should be used)
#   3  config files malformed or missing required fields

set -euo pipefail

CONFIG_DIR="${OPENCLAW_MAIL_CONFIG_DIR:-$HOME/.openclaw/mail}"
ACCOUNTS_FILE="$CONFIG_DIR/accounts.json"
DOMAINS_FILE="$CONFIG_DIR/domains.json"
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --json) JSON_OUTPUT=true ;;
    --help|-h)
      echo "Usage: $0 [--json]"
      echo "Validate account and domain config files."
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

output_result() {
  local status="$1" message="$2" accounts_exist="$3" domains_exist="$4"
  if $JSON_OUTPUT; then
    cat <<EOF
{
  "status": "$status",
  "message": "$message",
  "accountsFile": "$ACCOUNTS_FILE",
  "domainsFile": "$DOMAINS_FILE",
  "accountsFileExists": $accounts_exist,
  "domainsFileExists": $domains_exist,
  "configDir": "$CONFIG_DIR"
}
EOF
  else
    echo "$message"
  fi
}

# Check files exist
if [[ ! -f "$ACCOUNTS_FILE" ]] || [[ ! -f "$DOMAINS_FILE" ]]; then
  accounts_exist="false"
  domains_exist="false"
  [[ -f "$ACCOUNTS_FILE" ]] && accounts_exist="true"
  [[ -f "$DOMAINS_FILE" ]] && domains_exist="true"
  output_result "not_found" "Config files not found. Use direct mode with explicit credentials." "$accounts_exist" "$domains_exist"
  exit 2
fi

# Validate JSON
if ! jq empty "$ACCOUNTS_FILE" 2>/dev/null; then
  output_result "malformed" "accounts.json is not valid JSON" "true" "true"
  exit 3
fi

if ! jq empty "$DOMAINS_FILE" 2>/dev/null; then
  output_result "malformed" "domains.json is not valid JSON" "true" "true"
  exit 3
fi

# Validate account structure
REQUIRED_FIELDS=("provider" "loginUrl" "username" "passwordEncrypted" "browserProfile")
account_count=$(jq '.accounts | length' "$ACCOUNTS_FILE")

if [[ "$account_count" -eq 0 ]]; then
  output_result "malformed" "accounts.json has no account entries" "true" "true"
  exit 3
fi

for field in "${REQUIRED_FIELDS[@]}"; do
  missing=$(jq -r --arg f "$field" '.accounts | to_entries[] | select(.value[$f] == null or .value[$f] == "") | .key' "$ACCOUNTS_FILE")
  if [[ -n "$missing" ]]; then
    output_result "malformed" "Account(s) missing required field '$field': $missing" "true" "true"
    exit 3
  fi
done

output_result "valid" "Config files are valid" "true" "true"
exit 0

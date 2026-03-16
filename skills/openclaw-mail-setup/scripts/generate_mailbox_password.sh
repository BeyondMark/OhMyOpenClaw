#!/usr/bin/env bash
# generate_mailbox_password.sh — Generate a strong mailbox password for Titan account creation.
#
# Usage:
#   ./scripts/generate_mailbox_password.sh [--length <n>] [--json]
#
# Defaults:
#   - length: 18
#
# Guarantees:
#   - includes at least one uppercase letter
#   - includes at least one lowercase letter
#   - includes at least one digit
#   - includes at least one special character from !@#_-
#   - contains no whitespace
#
# Exit codes:
#   0  success
#   1  usage error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/log.sh" ]]; then
  source "$SCRIPT_DIR/log.sh"
fi

JSON_OUTPUT=false
LENGTH=18
UPPER="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
LOWER="abcdefghijklmnopqrstuvwxyz"
DIGITS="0123456789"
SPECIAL="!@#_-"
ALL="${UPPER}${LOWER}${DIGITS}${SPECIAL}"

rand_index() {
  local max="$1"
  local value
  value=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
  echo $((value % max))
}

pick_char() {
  local charset="$1"
  local idx
  idx=$(rand_index "${#charset}")
  printf '%s' "${charset:idx:1}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --length)
      LENGTH="${2:-}"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--length <n>] [--json]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if ! [[ "$LENGTH" =~ ^[0-9]+$ ]] || [[ "$LENGTH" -lt 16 ]]; then
  echo "Error: --length must be an integer >= 16" >&2
  exit 1
fi

password_chars=()
password_chars+=("$(pick_char "$UPPER")")
password_chars+=("$(pick_char "$LOWER")")
password_chars+=("$(pick_char "$DIGITS")")
password_chars+=("$(pick_char "$SPECIAL")")

while [[ "${#password_chars[@]}" -lt "$LENGTH" ]]; do
  password_chars+=("$(pick_char "$ALL")")
done

for ((i=${#password_chars[@]}-1; i>0; i--)); do
  j=$(rand_index $((i + 1)))
  tmp="${password_chars[i]}"
  password_chars[i]="${password_chars[j]}"
  password_chars[j]="$tmp"
done

password=""
for ch in "${password_chars[@]}"; do
  password+="$ch"
done

# Log password generation (do NOT log the password value)
[[ "$(type -t log_info 2>/dev/null)" == "function" ]] && log_info "create" 21 "Mailbox password generated" "{\"length\":$LENGTH}"

if $JSON_OUTPUT; then
    '{success: true, password: $password, length: $length}'
else
  echo "$password"
fi

#!/usr/bin/env bash
set -euo pipefail

# verify_permissions.sh
# Execution-only: verify permission configuration using built-in OpenClaw diagnostics.
# Called by the skill decision layer with final arguments.

OUTPUT_FORMAT="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUTPUT_FORMAT="json"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if ! command -v openclaw &>/dev/null; then
  echo "Error: openclaw CLI not found" >&2
  exit 1
fi

CONFIG_VALID=false
DOCTOR_PASSED=false
SANDBOX_OK=false
CONFIG_OUTPUT=""
DOCTOR_OUTPUT=""
SANDBOX_OUTPUT=""

# 1. Config validation
CONFIG_OUTPUT=$(openclaw config validate 2>&1) && CONFIG_VALID=true || CONFIG_VALID=false

# 2. Doctor --security (may not be available on older versions)
if openclaw doctor --help 2>&1 | grep -q "security"; then
  DOCTOR_OUTPUT=$(openclaw doctor --security 2>&1) && DOCTOR_PASSED=true || DOCTOR_PASSED=false
else
  DOCTOR_OUTPUT="openclaw doctor --security not available on this version"
  DOCTOR_PASSED=true  # Not a failure if the command doesn't exist
fi

# 3. Sandbox explain (only relevant if sandbox is configured)
SANDBOX_MODE=$(openclaw config get agents.defaults.sandbox.mode 2>/dev/null || echo "")
if [[ -n "$SANDBOX_MODE" && "$SANDBOX_MODE" != "off" ]]; then
  if openclaw sandbox --help 2>&1 | grep -q "explain"; then
    SANDBOX_OUTPUT=$(openclaw sandbox explain 2>&1) && SANDBOX_OK=true || SANDBOX_OK=false
  else
    SANDBOX_OUTPUT="openclaw sandbox explain not available on this version"
    SANDBOX_OK=true
  fi
else
  SANDBOX_OUTPUT="Sandbox is off, skipped"
  SANDBOX_OK=true
fi

# Overall result
ALL_PASSED=false
if [[ "$CONFIG_VALID" == "true" && "$DOCTOR_PASSED" == "true" && "$SANDBOX_OK" == "true" ]]; then
  ALL_PASSED=true
fi

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  # Escape output strings for JSON
  escape_json() {
    echo "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"(encoding error)\""
  }

  cat <<EOF
{
  "allPassed": $ALL_PASSED,
  "configValidate": {
    "passed": $CONFIG_VALID,
    "output": $(escape_json "$CONFIG_OUTPUT")
  },
  "doctorSecurity": {
    "passed": $DOCTOR_PASSED,
    "output": $(escape_json "$DOCTOR_OUTPUT")
  },
  "sandboxExplain": {
    "passed": $SANDBOX_OK,
    "output": $(escape_json "$SANDBOX_OUTPUT")
  }
}
EOF
else
  echo "=== Permission Verification ==="
  echo ""
  echo "--- Config Validate ---"
  echo "Passed: $CONFIG_VALID"
  echo "$CONFIG_OUTPUT"
  echo ""
  echo "--- Doctor --security ---"
  echo "Passed: $DOCTOR_PASSED"
  echo "$DOCTOR_OUTPUT"
  echo ""
  echo "--- Sandbox Explain ---"
  echo "Passed: $SANDBOX_OK"
  echo "$SANDBOX_OUTPUT"
  echo ""
  echo "=== Overall: $([ "$ALL_PASSED" == "true" ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED") ==="
fi

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  verify_agent_browser.sh --target claude-code|codex|openclaw [--json]

Verify the agent-browser installation for the chosen target.

Checks:
  1. agent-browser CLI exists
  2. target skill file exists
  3. browser smoke test succeeds against a local data: URL

Options:
  --target NAME   claude-code | codex | openclaw
  --json          Print machine-readable JSON
  --help          Show this help
EOF
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

target=""
json_output="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      target="$2"
      shift 2
      ;;
    --json)
      json_output="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "${target}" in
  claude-code|codex|openclaw) ;;
  *)
    echo "Invalid or missing --target: ${target:-<empty>}" >&2
    usage >&2
    exit 1
    ;;
esac

cli_installed="false"
cli_version=""
skill_path=""
skill_exists="false"
smoke_ok="false"
smoke_output=""
smoke_error=""

resolve_skill_path() {
  local candidate
  for candidate in "$@"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  printf '%s\n' "$1"
}

if command -v agent-browser >/dev/null 2>&1; then
  cli_installed="true"
  cli_version="$(agent-browser --version 2>&1 | awk 'NF { line = $0 } END { print line }')"
fi

case "${target}" in
  claude-code)
    skill_path="${HOME}/.claude/skills/agent-browser/SKILL.md"
    ;;
  codex)
    skill_path="$(resolve_skill_path \
      "${HOME}/.agents/skills/agent-browser/SKILL.md" \
      "${HOME}/.codex/skills/agent-browser/SKILL.md")"
    ;;
  openclaw)
    skill_path="${HOME}/.openclaw/skills/agent-browser/SKILL.md"
    ;;
esac

if [[ -f "${skill_path}" ]]; then
  skill_exists="true"
fi

if [[ "${cli_installed}" == "true" ]]; then
  smoke_html='data:text/html,<html><head><title>agent-browser smoke</title></head><body><button>Ready</button></body></html>'
  tmp_output="$(mktemp)"
  tmp_error="$(mktemp)"
  cleanup() {
    if command -v agent-browser >/dev/null 2>&1; then
      agent-browser close >/dev/null 2>&1 || true
    fi
    rm -f "${tmp_output}" "${tmp_error}"
  }
  trap cleanup EXIT

  if agent-browser open "${smoke_html}" >"${tmp_output}" 2>"${tmp_error}" && \
     agent-browser snapshot -i >>"${tmp_output}" 2>>"${tmp_error}"; then
    smoke_output="$(cat "${tmp_output}")"
    if printf '%s\n' "${smoke_output}" | grep -Eq 'Ready|ref=e|@e'; then
      smoke_ok="true"
    else
      smoke_error="Smoke test ran but snapshot output did not contain the expected marker"
    fi
  else
    smoke_output="$(cat "${tmp_output}" 2>/dev/null || true)"
    smoke_error="$(cat "${tmp_error}" 2>/dev/null || true)"
  fi

  agent-browser close >/dev/null 2>&1 || true
  trap - EXIT
  rm -f "${tmp_output}" "${tmp_error}"
fi

overall_ok="false"
if [[ "${cli_installed}" == "true" && "${skill_exists}" == "true" && "${smoke_ok}" == "true" ]]; then
  overall_ok="true"
fi

if [[ "${json_output}" == "true" ]]; then
  need_cmd python3
  python3 - <<'PY' \
    "${target}" \
    "${overall_ok}" \
    "${cli_installed}" \
    "${cli_version}" \
    "${skill_path}" \
    "${skill_exists}" \
    "${smoke_ok}" \
    "${smoke_output}" \
    "${smoke_error}"
import json
import sys

target = sys.argv[1]
overall_ok = sys.argv[2] == "true"
cli_installed = sys.argv[3] == "true"
cli_version = sys.argv[4]
skill_path = sys.argv[5]
skill_exists = sys.argv[6] == "true"
smoke_ok = sys.argv[7] == "true"
smoke_output = sys.argv[8]
smoke_error = sys.argv[9]

print(json.dumps(
    {
        "target": target,
        "ok": overall_ok,
        "cli": {
            "installed": cli_installed,
            "version": cli_version,
        },
        "skill": {
            "path": skill_path,
            "exists": skill_exists,
        },
        "smokeTest": {
            "ok": smoke_ok,
            "output": smoke_output,
            "error": smoke_error,
        },
    },
    ensure_ascii=False,
    indent=2,
))
PY
  if [[ "${overall_ok}" != "true" ]]; then
    exit 1
  fi
  exit 0
fi

echo "Target: ${target}"
echo "CLI installed: ${cli_installed}"
if [[ -n "${cli_version}" ]]; then
  echo "CLI version: ${cli_version}"
fi
echo "Skill path: ${skill_path}"
echo "Skill exists: ${skill_exists}"
echo "Smoke test: ${smoke_ok}"
if [[ -n "${smoke_error}" ]]; then
  echo "Smoke error:"
  printf '%s\n' "${smoke_error}"
fi

if [[ "${overall_ok}" != "true" ]]; then
  exit 1
fi

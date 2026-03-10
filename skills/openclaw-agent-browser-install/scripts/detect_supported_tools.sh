#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  detect_supported_tools.sh [--json]

Detect whether Claude Code CLI, Codex CLI, or OpenClaw is installed on the current machine.
Also reports common prerequisites used by the installer.

Options:
  --json    Print machine-readable JSON
  --help    Show this help
EOF
}

json_output="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
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

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

detect_command() {
  local candidate
  for candidate in "$@"; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

command_version() {
  local cmd="$1"
  local output
  output="$("${cmd}" --version 2>&1 || true)"
  printf '%s\n' "${output}" | awk '
    NF {
      lines[++count] = $0
    }
    END {
      for (i = 1; i <= count; i++) {
        if (lines[i] !~ /^WARNING:/) {
          print lines[i]
          exit
        }
      }
      if (count > 0) {
        print lines[count]
      }
    }
  '
}

claude_cmd="$(detect_command claude claude-code || true)"
codex_cmd="$(detect_command codex || true)"
openclaw_cmd="$(detect_command openclaw || true)"
node_cmd="$(detect_command node || true)"
npm_cmd="$(detect_command npm || true)"
npx_cmd="$(detect_command npx || true)"
git_cmd="$(detect_command git || true)"
curl_cmd="$(detect_command curl || true)"

claude_installed="false"
codex_installed="false"
openclaw_installed="false"

if [[ -n "${claude_cmd}" ]]; then
  claude_installed="true"
fi
if [[ -n "${codex_cmd}" ]]; then
  codex_installed="true"
fi
if [[ -n "${openclaw_cmd}" ]]; then
  openclaw_installed="true"
fi

installed_targets=()
if [[ "${claude_installed}" == "true" ]]; then
  installed_targets+=("claude-code")
fi
if [[ "${codex_installed}" == "true" ]]; then
  installed_targets+=("codex")
fi
if [[ "${openclaw_installed}" == "true" ]]; then
  installed_targets+=("openclaw")
fi

if [[ "${json_output}" == "true" ]]; then
  need_cmd python3
  claude_version=""
  codex_version=""
  openclaw_version=""
  node_version=""
  npm_version=""
  npx_version=""
  git_version=""
  curl_version=""

  if [[ -n "${claude_cmd}" ]]; then
    claude_version="$(command_version "${claude_cmd}")"
  fi
  if [[ -n "${codex_cmd}" ]]; then
    codex_version="$(command_version "${codex_cmd}")"
  fi
  if [[ -n "${openclaw_cmd}" ]]; then
    openclaw_version="$(command_version "${openclaw_cmd}")"
  fi
  if [[ -n "${node_cmd}" ]]; then
    node_version="$(command_version "${node_cmd}")"
  fi
  if [[ -n "${npm_cmd}" ]]; then
    npm_version="$(command_version "${npm_cmd}")"
  fi
  if [[ -n "${npx_cmd}" ]]; then
    npx_version="$(command_version "${npx_cmd}")"
  fi
  if [[ -n "${git_cmd}" ]]; then
    git_version="$(command_version "${git_cmd}")"
  fi
  if [[ -n "${curl_cmd}" ]]; then
    curl_version="$(command_version "${curl_cmd}")"
  fi

  python3 - <<'PY' \
    "$(uname -s)" \
    "${claude_cmd}" "${claude_installed}" "${claude_version}" \
    "${codex_cmd}" "${codex_installed}" "${codex_version}" \
    "${openclaw_cmd}" "${openclaw_installed}" "${openclaw_version}" \
    "${node_cmd}" "${node_version}" \
    "${npm_cmd}" "${npm_version}" \
    "${npx_cmd}" "${npx_version}" \
    "${git_cmd}" "${git_version}" \
    "${curl_cmd}" "${curl_version}"
import json
import sys

os_name = sys.argv[1]
claude_cmd, claude_installed, claude_version = sys.argv[2], sys.argv[3] == "true", sys.argv[4]
codex_cmd, codex_installed, codex_version = sys.argv[5], sys.argv[6] == "true", sys.argv[7]
openclaw_cmd, openclaw_installed, openclaw_version = sys.argv[8], sys.argv[9] == "true", sys.argv[10]
node_cmd, node_version = sys.argv[11], sys.argv[12]
npm_cmd, npm_version = sys.argv[13], sys.argv[14]
npx_cmd, npx_version = sys.argv[15], sys.argv[16]
git_cmd, git_version = sys.argv[17], sys.argv[18]
curl_cmd, curl_version = sys.argv[19], sys.argv[20]

targets = [
    {
        "id": "claude-code",
        "installed": claude_installed,
        "command": claude_cmd,
        "version": claude_version,
    },
    {
        "id": "codex",
        "installed": codex_installed,
        "command": codex_cmd,
        "version": codex_version,
    },
    {
        "id": "openclaw",
        "installed": openclaw_installed,
        "command": openclaw_cmd,
        "version": openclaw_version,
    },
]

installed_targets = [item["id"] for item in targets if item["installed"]]

prerequisites = {}
for name, cmd in [
    ("node", (node_cmd, node_version)),
    ("npm", (npm_cmd, npm_version)),
    ("npx", (npx_cmd, npx_version)),
    ("git", (git_cmd, git_version)),
    ("curl", (curl_cmd, curl_version)),
]:
    cmd, ver = cmd
    prerequisites[name] = {
        "installed": bool(cmd),
        "command": cmd,
        "version": ver,
    }

print(json.dumps(
    {
        "os": os_name,
        "targets": targets,
        "installedTargets": installed_targets,
        "targetCount": len(installed_targets),
        "prerequisites": prerequisites,
    },
    ensure_ascii=False,
    indent=2,
))
PY
  exit 0
fi

echo "OS: $(uname -s)"
echo
echo "Targets:"

for item in "claude-code:${claude_cmd}" "codex:${codex_cmd}" "openclaw:${openclaw_cmd}"; do
  name="${item%%:*}"
  cmd="${item#*:}"
  if [[ -n "${cmd}" ]]; then
    echo "- ${name}: installed (${cmd})"
    echo "  version: $(command_version "${cmd}")"
  else
    echo "- ${name}: not installed"
  fi
done

echo
echo "Prerequisites:"
for item in "node:${node_cmd}" "npm:${npm_cmd}" "npx:${npx_cmd}" "git:${git_cmd}" "curl:${curl_cmd}"; do
  name="${item%%:*}"
  cmd="${item#*:}"
  if [[ -n "${cmd}" ]]; then
    echo "- ${name}: installed (${cmd})"
  else
    echo "- ${name}: not installed"
  fi
done

echo
if ((${#installed_targets[@]} == 0)); then
  echo "Installed targets: none"
else
  echo "Installed targets: ${installed_targets[*]}"
fi

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  install_agent_browser.sh --target claude-code|codex|openclaw [options]

Install the agent-browser CLI and place the official skill into the chosen target tool.

Required:
  --target NAME              claude-code | codex | openclaw

Options:
  --force                    For openclaw only: back up and replace an existing ~/.openclaw/skills/agent-browser
  --skip-verify              Skip the post-install verification step
  --source-ref REF           Git ref to fetch from vercel-labs/agent-browser (default: main)
  --help                     Show this help
EOF
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

target=""
force="false"
verify_after_install="true"
source_ref="main"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      target="$2"
      shift 2
      ;;
    --force)
      force="true"
      shift
      ;;
    --skip-verify)
      verify_after_install="false"
      shift
      ;;
    --source-ref)
      source_ref="$2"
      shift 2
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

need_cmd npm
need_cmd npx
need_cmd mktemp

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
npm_cache_dir="${TMPDIR:-/tmp}/agent-browser-npm-cache"
mkdir -p "${npm_cache_dir}"
export npm_config_cache="${npm_cache_dir}"

install_cli() {
  echo "[1/4] Install agent-browser CLI"
  npm install -g agent-browser
  need_cmd agent-browser
}

install_browser_runtime() {
  echo "[2/4] Install browser runtime"
  if [[ "$(uname -s)" == "Linux" ]]; then
    if [[ "$(id -u)" == "0" ]]; then
      agent-browser install --with-deps
      return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
      agent-browser install --with-deps
      return 0
    fi
    echo "Linux detected but passwordless sudo is unavailable; falling back to browser-only install"
    agent-browser install
    return 0
  fi
  agent-browser install
}

install_skill_via_skills_cli() {
  local target_agent="$1"
  echo "[3/4] Install official agent-browser skill for ${target_agent}"
  npx --yes skills add vercel-labs/agent-browser --skill agent-browser -g -a "${target_agent}" -y
}

install_skill_for_openclaw() {
  local repo_dir tmp_dir source_dir dest_dir backup_dir backup_path

  echo "[3/4] Install official agent-browser skill for OpenClaw"
  need_cmd git

  dest_dir="${HOME}/.openclaw/skills/agent-browser"
  mkdir -p "${HOME}/.openclaw/skills"

  if [[ -e "${dest_dir}" ]]; then
    if [[ "${force}" != "true" ]]; then
      echo "OpenClaw skill already exists at ${dest_dir}. Re-run with --force to replace it." >&2
      exit 1
    fi
    backup_dir="${HOME}/.openclaw/skills-backups"
    mkdir -p "${backup_dir}"
    backup_path="${backup_dir}/agent-browser.$(date +%Y%m%d%H%M%S)"
    mv "${dest_dir}" "${backup_path}"
    echo "Backed up existing OpenClaw skill to ${backup_path}"
  fi

  tmp_dir="$(mktemp -d)"
  cleanup_tmp() {
    rm -rf "${tmp_dir}"
  }
  trap cleanup_tmp RETURN

  repo_dir="${tmp_dir}/repo"
  git clone --depth 1 --branch "${source_ref}" --filter=blob:none --sparse https://github.com/vercel-labs/agent-browser "${repo_dir}"
  git -C "${repo_dir}" sparse-checkout set skills/agent-browser

  source_dir="${repo_dir}/skills/agent-browser"
  if [[ ! -f "${source_dir}/SKILL.md" ]]; then
    echo "Downloaded repository does not contain skills/agent-browser/SKILL.md" >&2
    exit 1
  fi

  cp -R "${source_dir}" "${dest_dir}"
}

run_verify() {
  echo "[4/4] Verify installation"
  "${script_dir}/verify_agent_browser.sh" --target "${target}"
}

install_cli
install_browser_runtime

case "${target}" in
  claude-code)
    if ! command -v claude >/dev/null 2>&1 && ! command -v claude-code >/dev/null 2>&1; then
      echo "Missing required command: claude or claude-code" >&2
      exit 1
    fi
    install_skill_via_skills_cli "claude-code"
    ;;
  codex)
    need_cmd codex
    install_skill_via_skills_cli "codex"
    ;;
  openclaw)
    need_cmd openclaw
    install_skill_for_openclaw
    ;;
esac

if [[ "${verify_after_install}" == "true" ]]; then
  run_verify
else
  echo "[4/4] Verification skipped"
fi

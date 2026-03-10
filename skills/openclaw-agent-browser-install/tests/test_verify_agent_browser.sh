#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "${script_dir}/.." && pwd)"
verify_script="${skill_dir}/scripts/verify_agent_browser.sh"

make_fake_agent_browser() {
  local bin_dir="$1"
  mkdir -p "${bin_dir}"
  cat > "${bin_dir}/agent-browser" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --version)
    echo "agent-browser 0.17.1"
    ;;
  open)
    exit 0
    ;;
  snapshot)
    echo "Ready"
    ;;
  close)
    exit 0
    ;;
  *)
    echo "unexpected command: ${1:-<empty>}" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${bin_dir}/agent-browser"
}

run_case() {
  local name="$1"
  local skill_relpath="$2"
  local tmp_dir output_file

  tmp_dir="$(mktemp -d)"
  output_file="${tmp_dir}/verify.json"
  trap 'rm -rf "${tmp_dir}"' RETURN

  make_fake_agent_browser "${tmp_dir}/bin"
  mkdir -p "${tmp_dir}/home/${skill_relpath%/*}"
  : > "${tmp_dir}/home/${skill_relpath}"

  if ! PATH="${tmp_dir}/bin:${PATH}" HOME="${tmp_dir}/home" \
      "${verify_script}" --target codex --json > "${output_file}"; then
    echo "FAIL: ${name}" >&2
    cat "${output_file}" >&2 || true
    exit 1
  fi

  if ! grep -q '"exists": true' "${output_file}"; then
    echo "FAIL: ${name} did not mark skill as existing" >&2
    cat "${output_file}" >&2
    exit 1
  fi

  if ! grep -q '"ok": true' "${output_file}"; then
    echo "FAIL: ${name} did not return overall success" >&2
    cat "${output_file}" >&2
    exit 1
  fi
}

run_case "codex unified skills path" ".agents/skills/agent-browser/SKILL.md"
run_case "codex legacy app path" ".codex/skills/agent-browser/SKILL.md"

echo "PASS: verify_agent_browser codex path coverage"

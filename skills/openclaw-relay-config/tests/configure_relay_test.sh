#!/usr/bin/env bash
set -euo pipefail

skill_dir="$(cd "$(dirname "$0")/.." && pwd)"
script_path="${skill_dir}/scripts/configure_relay.sh"

create_fake_openclaw() {
  local bin_dir="$1"

  mkdir -p "${bin_dir}"
  cat > "${bin_dir}/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${HOME}/.openclaw/test-state"
mkdir -p "${state_dir}"

sanitize_key() {
  printf '%s' "$1" | tr './' '__'
}

command_name="${1:-}"
subcommand_name="${2:-}"

case "${command_name}:${subcommand_name}" in
  config:set)
    key="${3:?missing key}"
    value="${4:?missing value}"
    printf '%s' "${value}" > "${state_dir}/$(sanitize_key "${key}")"
    ;;
  config:get)
    key="${3:?missing key}"
    cat "${state_dir}/$(sanitize_key "${key}")"
    ;;
  config:validate)
    ;;
  gateway:restart)
    printf 'restart\n' >> "${state_dir}/gateway_restart.log"
    ;;
  *)
    echo "Unsupported fake openclaw invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${bin_dir}/openclaw"
}

assert_provider_limits() {
  local provider_json_file="$1"
  local expected_context_window="$2"
  local expected_max_tokens="$3"

  python3 - "${provider_json_file}" "${expected_context_window}" "${expected_max_tokens}" <<'PY'
import json
import sys

provider_json_file = sys.argv[1]
expected_context_window = int(sys.argv[2])
expected_max_tokens = int(sys.argv[3])

with open(provider_json_file, "r", encoding="utf-8") as f:
    provider = json.load(f)

model = provider["models"][0]
if model["contextWindow"] != expected_context_window:
    raise SystemExit(
        f"contextWindow mismatch: expected {expected_context_window}, got {model['contextWindow']}"
    )
if model["maxTokens"] != expected_max_tokens:
    raise SystemExit(
        f"maxTokens mismatch: expected {expected_max_tokens}, got {model['maxTokens']}"
    )
PY
}

run_configure_relay() {
  local test_home="$1"
  shift

  PATH="${test_home}/bin:${PATH}" HOME="${test_home}" "${script_path}" "$@"
}

test_requires_explicit_limits() {
  local test_home output_file
  test_home="$(mktemp -d "/tmp/openclaw-relay-test-gpt54.XXXXXX")"
  mkdir -p "${test_home}/.openclaw"
  create_fake_openclaw "${test_home}/bin"
  output_file="${test_home}/configure.out"

  if run_configure_relay "${test_home}" \
    --provider-id packyapi_chatgpt \
    --api-key-env PACKYAPI_CHATGPT_API_KEY \
    --base-url https://api-slb.packyapi.com/v1 \
    --api openai-responses \
    --model-id gpt-5.4 \
    --model-name "GPT-5.4" \
    --api-key-value "sk-test" \
    --skip-restart >"${output_file}" 2>&1; then
    echo "configure_relay.sh should require explicit --context-window/--max-tokens" >&2
    cat "${output_file}" >&2
    exit 1
  fi

  if ! grep -q "Missing required argument: context_window" "${output_file}"; then
    echo "expected missing context_window error" >&2
    cat "${output_file}" >&2
    exit 1
  fi
}

test_explicit_limits_override_presets() {
  local test_home provider_json_file
  test_home="$(mktemp -d "/tmp/openclaw-relay-test-explicit.XXXXXX")"
  mkdir -p "${test_home}/.openclaw"
  create_fake_openclaw "${test_home}/bin"

  run_configure_relay "${test_home}" \
    --provider-id packyapi_chatgpt \
    --api-key-env PACKYAPI_CHATGPT_API_KEY \
    --base-url https://api-slb.packyapi.com/v1 \
    --api openai-responses \
    --model-id gpt-5.4 \
    --model-name "GPT-5.4" \
    --api-key-value "sk-test" \
    --context-window 777777 \
    --max-tokens 55555 \
    --skip-restart

  provider_json_file="${test_home}/.openclaw/test-state/models_providers_packyapi_chatgpt"
  assert_provider_limits "${provider_json_file}" 777777 55555
}

test_requires_explicit_limits
test_explicit_limits_override_presets

printf 'configure_relay tests passed\n'

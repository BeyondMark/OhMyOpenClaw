#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  check_relay_model.sh --base-url URL --api API --model-id ID [options]

Required:
  --base-url URL                Relay endpoint base URL
  --api API                     openai-responses | openai-completions | anthropic-messages | google-generative-ai
  --model-id ID                 Model id to verify

Optional:
  --api-key-env NAME            Environment variable name to read from ~/.openclaw/.env or current shell
  --api-key-value VALUE         API key value used for the probe
  --header KEY=VALUE            Extra static header, may be repeated
  --help                        Show this help

Exit codes:
  0 model found
  1 usage or validation error
  2 model list request failed (auth/network/http)
  3 model list endpoint unsupported or unrecognized
  4 model not found in returned list
EOF
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

load_api_key_from_env_file() {
  local env_file value
  env_file="${HOME}/.openclaw/.env"
  if [[ -z "${api_key_env}" || ! -f "${env_file}" ]]; then
    return 1
  fi

  value="$(
    awk -F= -v key="${api_key_env}" '
      $1 == key {
        sub(/^[^=]*=/, "", $0)
        print $0
        exit
      }
    ' "${env_file}"
  )"

  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
    return 0
  fi

  return 1
}

resolve_effective_api_key() {
  if [[ -n "${api_key_value}" ]]; then
    printf '%s' "${api_key_value}"
    return 0
  fi

  if [[ -n "${api_key_env}" && -n "${!api_key_env:-}" ]]; then
    printf '%s' "${!api_key_env}"
    return 0
  fi

  if load_api_key_from_env_file; then
    return 0
  fi

  return 1
}

base_url=""
api=""
model_id=""
api_key_env=""
api_key_value=""
headers=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      base_url="$2"
      shift 2
      ;;
    --api)
      api="$2"
      shift 2
      ;;
    --model-id)
      model_id="$2"
      shift 2
      ;;
    --api-key-env)
      api_key_env="$2"
      shift 2
      ;;
    --api-key-value)
      api_key_value="$2"
      shift 2
      ;;
    --header)
      headers+=("$2")
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

need_cmd curl
need_cmd python3

for required in base_url api model_id; do
  if [[ -z "${!required}" ]]; then
    echo "Missing required argument: ${required}" >&2
    usage >&2
    exit 1
  fi
done

case "${api}" in
  openai-responses|openai-completions) ;;
  anthropic-messages|google-generative-ai)
    echo "Model list probing is not implemented generically for api=${api}. Check provider docs or use a provider-specific probe." >&2
    exit 3
    ;;
  *)
    echo "Unsupported --api value: ${api}" >&2
    exit 1
    ;;
esac

if [[ ! "${base_url}" =~ ^https?:// ]]; then
  echo "Invalid --base-url: ${base_url}" >&2
  exit 1
fi

effective_api_key="$(resolve_effective_api_key || true)"
endpoint="${base_url%/}/models"
response_file="$(mktemp)"
err_file="${response_file}.err"

curl_args=(
  -sS
  -L
  -o "${response_file}"
  -w "%{http_code}"
  -H "Accept: application/json"
)

if [[ -n "${effective_api_key}" ]]; then
  curl_args+=(-H "Authorization: Bearer ${effective_api_key}")
fi

if ((${#headers[@]} > 0)); then
  for header_item in "${headers[@]}"; do
    curl_args+=(-H "${header_item}")
  done
fi

http_code="$(curl "${curl_args[@]}" "${endpoint}" 2>"${err_file}" || true)"

if [[ ! "${http_code}" =~ ^2 ]]; then
  echo "Model list request failed: ${endpoint} (HTTP ${http_code:-curl-error})" >&2
  if [[ -s "${err_file}" ]]; then
    tr '\n' ' ' < "${err_file}" >&2
    echo >&2
  fi
  rm -f "${response_file}" "${err_file}"
  exit 2
fi

supported_models="$(
  python3 - "${response_file}" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)

ids = []
seen = set()

def add(value):
    if isinstance(value, str) and value and value not in seen:
        seen.add(value)
        ids.append(value)

def walk(node):
    if isinstance(node, dict):
        for key in ("id", "name", "model", "model_id"):
            add(node.get(key))
        for key in ("data", "models", "items", "result"):
            child = node.get(key)
            if isinstance(child, list):
                for item in child:
                    walk(item)
    elif isinstance(node, list):
        for item in node:
            walk(item)

walk(payload)
print("\n".join(ids))
PY
)"

rm -f "${response_file}" "${err_file}"

if [[ -z "${supported_models}" ]]; then
  echo "Model list endpoint responded, but no recognizable model ids were found: ${endpoint}" >&2
  exit 3
fi

if printf '%s\n' "${supported_models}" | grep -Fx -- "${model_id}" >/dev/null 2>&1; then
  echo "Model found: ${model_id}"
  exit 0
fi

echo "Model not found: ${model_id}" >&2
echo "Available models:" >&2
printf '%s\n' "${supported_models}" | sed 's/^/  - /' >&2
exit 4

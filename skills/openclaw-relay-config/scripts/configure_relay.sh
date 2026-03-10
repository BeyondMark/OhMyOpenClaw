#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  configure_relay.sh --provider-id ID --api-key-env NAME --base-url URL --api API --model-id ID [options]

Required:
  --provider-id ID              Provider id written under models.providers, for example packyapi_chatgpt
  --api-key-env NAME            Environment variable name referenced from config, for example PACKYAPI_CHATGPT_API_KEY
  --base-url URL                Relay endpoint base URL, for example https://example.com/v1
  --api API                     openai-responses | openai-completions | anthropic-messages | google-generative-ai
  --model-id ID                 Model id exposed by the relay
  --context-window N            models[].contextWindow
  --max-tokens N                models[].maxTokens

Optional:
  --model-name NAME             Display name stored in models[].name (default: same as model-id)
  --api-key-value VALUE         Write or update the secret in ~/.openclaw/.env
  --reasoning true|false        models[].reasoning (default: false)
  --auth-header true|false      Include authHeader in provider config (default: false)
  --header KEY=VALUE            Extra static header, may be repeated
  --set-default true|false      Update agents.defaults.model.primary (default: true)
  --skip-restart                Do not restart the gateway after validation
  --help                        Show this help

Example:
  configure_relay.sh \
    --provider-id packyapi_chatgpt \
    --api-key-env PACKYAPI_CHATGPT_API_KEY \
    --base-url https://api.example.com/v1 \
    --api openai-responses \
    --model-id gpt-5.4 \
    --model-name "GPT-5.4" \
    --context-window 1050000 \
    --max-tokens 128000 \
    --api-key-value "sk-xxxx"
EOF
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_bool() {
  case "$2" in
    true|false) ;;
    *)
      echo "Invalid value for $1: $2 (expected true or false)" >&2
      exit 1
      ;;
  esac
}

require_integer() {
  if [[ ! "$2" =~ ^[0-9]+$ ]]; then
    echo "Invalid value for $1: $2 (expected a positive integer)" >&2
    exit 1
  fi
}

backup_config() {
  local config_file backup_dir backup_file
  config_file="${HOME}/.openclaw/openclaw.json"
  backup_dir="${HOME}/.openclaw/backups"

  mkdir -p "${backup_dir}"
  if [[ -f "${config_file}" ]]; then
    backup_file="${backup_dir}/openclaw.json.relay.$(date +%Y%m%d%H%M%S).bak"
    cp "${config_file}" "${backup_file}"
    echo "Backup created: ${backup_file}"
  else
    echo "No existing config file found at ${config_file}; continuing without backup"
  fi
}

upsert_env_value() {
  local env_file tmp_file
  env_file="${HOME}/.openclaw/.env"
  mkdir -p "$(dirname "${env_file}")"
  touch "${env_file}"
  chmod 600 "${env_file}"
  tmp_file="$(mktemp)"

  if grep -q "^${api_key_env}=" "${env_file}"; then
    awk -v key="${api_key_env}" -v value="${api_key_value}" '
      BEGIN { updated = 0 }
      $0 ~ ("^" key "=") {
        print key "=" value
        updated = 1
        next
      }
      { print }
      END {
        if (updated == 0) {
          print key "=" value
        }
      }
    ' "${env_file}" > "${tmp_file}"
  else
    cp "${env_file}" "${tmp_file}"
    printf '%s=%s\n' "${api_key_env}" "${api_key_value}" >> "${tmp_file}"
  fi

  mv "${tmp_file}" "${env_file}"
  chmod 600 "${env_file}"
  echo "Updated secret in ${env_file}: ${api_key_env}"
}

provider_id=""
api_key_env=""
api_key_value=""
base_url=""
api=""
model_id=""
model_name=""
context_window=""
max_tokens=""
reasoning="false"
auth_header="false"
set_default="true"
restart_gateway="true"
headers=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider-id)
      provider_id="$2"
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
    --model-name)
      model_name="$2"
      shift 2
      ;;
    --context-window)
      context_window="$2"
      shift 2
      ;;
    --max-tokens)
      max_tokens="$2"
      shift 2
      ;;
    --reasoning)
      reasoning="$2"
      shift 2
      ;;
    --auth-header)
      auth_header="$2"
      shift 2
      ;;
    --header)
      headers+=("$2")
      shift 2
      ;;
    --set-default)
      set_default="$2"
      shift 2
      ;;
    --skip-restart)
      restart_gateway="false"
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

need_cmd openclaw
need_cmd python3
need_cmd mktemp

for required in provider_id api_key_env base_url api model_id context_window max_tokens; do
  if [[ -z "${!required}" ]]; then
    echo "Missing required argument: ${required}" >&2
    usage >&2
    exit 1
  fi
done

case "${api}" in
  openai-responses|openai-completions|anthropic-messages|google-generative-ai) ;;
  *)
    echo "Unsupported --api value: ${api}" >&2
    exit 1
    ;;
esac

if [[ ! "${provider_id}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "Invalid --provider-id: ${provider_id}" >&2
  exit 1
fi

if [[ ! "${api_key_env}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "Invalid --api-key-env: ${api_key_env}" >&2
  exit 1
fi

if [[ ! "${base_url}" =~ ^https?:// ]]; then
  echo "Invalid --base-url: ${base_url}" >&2
  exit 1
fi

require_bool --reasoning "${reasoning}"
require_bool --auth-header "${auth_header}"
require_bool --set-default "${set_default}"

if [[ -z "${model_name}" ]]; then
  model_name="${model_id}"
fi

require_integer --context-window "${context_window}"
require_integer --max-tokens "${max_tokens}"

if [[ -n "${api_key_value}" && "${api_key_value}" == *$'\n'* ]]; then
  echo "--api-key-value must be a single line" >&2
  exit 1
fi

echo "[1/6] Backup current OpenClaw config"
backup_config

if [[ -n "${api_key_value}" ]]; then
  echo "[2/6] Write API key into ~/.openclaw/.env"
  upsert_env_value
else
  echo "[2/6] Skip writing ~/.openclaw/.env"
fi

echo "[3/6] Build provider payload"
python_args=(
  -
  "${base_url}"
  "${api_key_env}"
  "${api}"
  "${model_id}"
  "${model_name}"
  "${reasoning}"
  "${context_window}"
  "${max_tokens}"
  "${auth_header}"
)
if ((${#headers[@]} > 0)); then
  python_args+=("${headers[@]}")
fi

provider_json="$(
  python3 "${python_args[@]}" <<'PY'
import json
import sys

base_url = sys.argv[1]
api_key_env = sys.argv[2]
api = sys.argv[3]
model_id = sys.argv[4]
model_name = sys.argv[5]
reasoning = sys.argv[6] == "true"
context_window = int(sys.argv[7])
max_tokens = int(sys.argv[8])
auth_header = sys.argv[9] == "true"
header_args = sys.argv[10:]

headers = {}
for item in header_args:
    if "=" not in item:
        raise SystemExit(f"Invalid --header value: {item!r}. Expected KEY=VALUE.")
    key, value = item.split("=", 1)
    if not key:
        raise SystemExit(f"Invalid --header value: {item!r}. Header name is empty.")
    headers[key] = value

provider = {
    "baseUrl": base_url,
    "apiKey": "${" + api_key_env + "}",
    "api": api,
    "models": [
        {
            "id": model_id,
            "name": model_name,
            "reasoning": reasoning,
            "input": ["text"],
            "cost": {
                "input": 0,
                "output": 0,
                "cacheRead": 0,
                "cacheWrite": 0,
            },
            "contextWindow": context_window,
            "maxTokens": max_tokens,
        }
    ],
}

if auth_header:
    provider["authHeader"] = True
if headers:
    provider["headers"] = headers

print(json.dumps(provider, ensure_ascii=False))
PY
)"

echo "[4/6] Write models.providers.${provider_id}"
openclaw config set models.mode '"merge"' --strict-json
openclaw config set "models.providers.${provider_id}" "${provider_json}" --strict-json

if [[ "${set_default}" == "true" ]]; then
  echo "[5/6] Set default model to ${provider_id}/${model_id}"
  openclaw config set agents.defaults.model.primary "\"${provider_id}/${model_id}\"" --strict-json
else
  echo "[5/6] Skip default model update"
fi

echo "[6/6] Validate config"
openclaw config validate

if [[ "${restart_gateway}" == "true" ]]; then
  echo "Restart gateway to apply changes"
  openclaw gateway restart
  sleep 3
fi

echo
echo "Configured provider:"
openclaw config get "models.providers.${provider_id}"

echo
if [[ "${set_default}" == "true" ]]; then
  echo "Default model:"
  openclaw config get agents.defaults.model.primary
fi

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  remove_relay.sh --provider-id ID [options]

Required:
  --provider-id ID              Provider id to remove, for example packyapi_chatgpt

Optional:
  --api-key-env NAME            Environment variable to remove from ~/.openclaw/.env
  --clear-default-if-match REF  Remove agents.defaults.model.primary if it equals this provider/model ref
  --skip-restart                Do not restart the gateway after validation
  --help                        Show this help
EOF
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
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
  fi
}

remove_env_key() {
  local env_file tmp_file
  env_file="${HOME}/.openclaw/.env"
  if [[ ! -f "${env_file}" ]]; then
    return 0
  fi

  tmp_file="$(mktemp)"
  awk -F= -v key="${api_key_env}" '$1 != key { print }' "${env_file}" > "${tmp_file}"
  if [[ -s "${tmp_file}" ]]; then
    mv "${tmp_file}" "${env_file}"
    chmod 600 "${env_file}"
  else
    rm -f "${tmp_file}"
    rm -f "${env_file}"
  fi
  echo "Removed env key: ${api_key_env}"
}

provider_id=""
api_key_env=""
clear_default_if_match=""
restart_gateway="true"

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
    --clear-default-if-match)
      clear_default_if_match="$2"
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

if [[ -z "${provider_id}" ]]; then
  echo "Missing required argument: provider_id" >&2
  usage >&2
  exit 1
fi

echo "[1/4] Backup current OpenClaw config"
backup_config

echo "[2/4] Remove provider ${provider_id}"
openclaw config unset "models.providers.${provider_id}"

if [[ -n "${clear_default_if_match}" ]]; then
  current_default="$(openclaw config get agents.defaults.model.primary 2>/dev/null || true)"
  if [[ "${current_default}" == "${clear_default_if_match}" ]]; then
    echo "[3/4] Clear default model ${clear_default_if_match}"
    openclaw config unset agents.defaults.model.primary || true
    openclaw config unset agents.defaults.model || true
  else
    echo "[3/4] Skip default model cleanup"
  fi
else
  echo "[3/4] Skip default model cleanup"
fi

if [[ -n "${api_key_env}" ]]; then
  remove_env_key
else
  echo "[4/4] Skip env cleanup"
fi

openclaw config validate

if [[ "${restart_gateway}" == "true" ]]; then
  openclaw gateway restart
  sleep 3
fi

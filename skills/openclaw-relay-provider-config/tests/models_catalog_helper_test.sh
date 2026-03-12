#!/usr/bin/env bash
set -euo pipefail

skill_dir="$(cd "$(dirname "$0")/.." && pwd)"
helper_path="${skill_dir}/scripts/models_catalog_helper.mjs"

assert_json_equals() {
  local actual_json="$1"
  local expected_json="$2"

  ACTUAL_JSON="${actual_json}" EXPECTED_JSON="${expected_json}" python3 - <<'PY'
import json
import os

actual = json.loads(os.environ["ACTUAL_JSON"])
expected = json.loads(os.environ["EXPECTED_JSON"])

if actual != expected:
    raise SystemExit(f"JSON mismatch:\nactual={actual}\nexpected={expected}")
PY
}

test_upsert_initializes_empty_catalog() {
  local output

  output="$(printf '' | node "${helper_path}" upsert --model-ref 'packyapi_chatgpt/gpt-5.4' --alias 'Packy GPT-5.4')"
  assert_json_equals "${output}" '{"packyapi_chatgpt/gpt-5.4":{"alias":"Packy GPT-5.4"}}'
}

test_upsert_preserves_existing_entries() {
  local input output

  input='{"openai/gpt-5.4":{"alias":"GPT-5.4"}}'
  output="$(
    printf '%s' "${input}" | node "${helper_path}" upsert \
      --model-ref 'packyapi_chatgpt/gpt-5.4' \
      --alias 'Packy GPT-5.4'
  )"

  assert_json_equals "${output}" '{"openai/gpt-5.4":{"alias":"GPT-5.4"},"packyapi_chatgpt/gpt-5.4":{"alias":"Packy GPT-5.4"}}'
}

test_remove_provider_deletes_all_matching_refs() {
  local input output

  input='{"openai/gpt-5.4":{"alias":"GPT-5.4"},"packyapi_chatgpt/gpt-5.4":{"alias":"Packy GPT-5.4"},"packyapi_chatgpt/gpt-5.4-mini":{"alias":"Packy GPT-5.4 Mini"}}'
  output="$(
    printf '%s' "${input}" | node "${helper_path}" remove-provider \
      --provider-id 'packyapi_chatgpt'
  )"

  assert_json_equals "${output}" '{"openai/gpt-5.4":{"alias":"GPT-5.4"}}'
}

test_upsert_initializes_empty_catalog
test_upsert_preserves_existing_entries
test_remove_provider_deletes_all_matching_refs

printf 'models_catalog_helper tests passed\n'

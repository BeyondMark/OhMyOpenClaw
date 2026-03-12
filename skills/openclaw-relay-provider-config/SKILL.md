---
name: openclaw-relay-provider-config
description: "Configure or remove OpenClaw relay providers in ~/.openclaw/openclaw.json. Use when you need to add, update, validate, or remove models.providers.* entries for OpenAI-compatible, Anthropic-compatible, or Google-compatible relays. This skill collects missing inputs, derives naming, checks collisions, validates model limits from official docs, writes config with native openclaw commands, and updates agents.defaults.models through the local helper."
---

# OpenClaw Relay Provider Config

## Overview

Use this skill when OpenClaw needs a relay or proxy model provider.

Trigger policy:

- manual-only
- start this skill only when the user explicitly asks to use `openclaw-relay-provider-config`, explicitly asks to configure/update/remove a relay provider, or explicitly asks for this exact workflow
- do not auto-trigger this skill from loose similarity alone
- if the user has not explicitly asked for relay configuration work, stop and ask before proceeding with this skill

When referring to bundled files, resolve paths relative to this skill directory. Do not assume a user-specific install path.

This skill owns the full decision layer:

- collect missing inputs from the user
- decide naming
- check collisions before any write
- validate the requested model when possible
- verify `contextWindow` and `maxTokens` from official docs
- ensure the configured model is registered in `agents.defaults.models` so it appears in OpenClaw `/model`
- only then execute native `openclaw config` commands

This skill does not rely on flow scripts. The only local helper is `scripts/models_catalog_helper.mjs`, which is limited to safe JSON updates for `agents.defaults.models`.

For protocol choices and current OpenClaw config boundaries, read `references/relay-protocols.md`.

## Guided Input Flow

This skill must behave like a guided wizard, not a loose checklist.

Rules:

- determine the user's intent first: `add`, `update`, or `remove`
- collect only missing fields; do not ask again for values the user already gave
- do not ask the user for derived fields such as `provider_id` or `api_key_env` unless there is a collision and a rename decision is needed
- ask focused questions in batches of at most 4 fields
- before any write, show a final confirmation summary of the exact values that will be written
- treat registration into `agents.defaults.models` as part of the required write path, not as a postscript

Use the following wizard sequence.

### Step 1: Determine Intent

If the user's request does not clearly say whether they want to add, update, or remove a relay, ask:

```text
你这次是要新增 relay、更新已有 relay，还是删除 relay？
```

### Step 2A: Add or Update Intake

For add or update, fill these slots in order:

1. `base_url`
2. `api`
3. `model_id`
4. `api_key`
5. `model_name` if the user wants a custom display name
6. `relay_name` if it cannot be safely derived from the site or domain
7. `model_family` if it cannot be safely derived from the model family
8. whether this model should become `agents.defaults.model.primary`

Preferred intake prompt for missing core fields:

```text
还缺这些关键信息，请按顺序给我：
1. relay 的 base URL
2. 协议类型：openai-responses / openai-completions / anthropic-messages / google-generative-ai
3. 模型 ID
4. API key
```

If only the optional display name is missing, ask:

```text
这个模型要在 OpenClaw 里显示成什么名字？如果不特别指定，我会直接用 model ID。
```

If the default-model choice is missing, ask:

```text
要不要把这个 relay 模型同时设为默认模型？
```

### Step 2B: Remove Intake

For remove, fill these slots in order:

1. target `provider_id`
2. whether the related env key should also be removed
3. the current default model ref if it may match the relay being removed

Preferred remove prompt:

```text
为避免删错，请确认这 3 项：
1. 要删除的 provider_id
2. 是否同时删除对应的 API key 环境变量
3. 如果它当前正被设为默认模型，是否一并清掉默认模型指向
```

### Step 3: Protocol-Specific Guidance

If `api` is `openai-responses` or `openai-completions`:

- do not ask the user whether probing is needed
- probe `GET <baseUrl>/models` directly
- only ask the user for extra headers if the relay explicitly requires them

If `api` is `anthropic-messages` or `google-generative-ai`:

- tell the user that generic probing is unreliable
- ask for an official provider doc link if they already have one
- if they do not, use available search/browsing tools to find official docs yourself

Preferred prompt when an official doc link would help:

```text
这个协议类型不适合走通用 /models 探测。你如果有这个 relay 或模型的官方文档链接，直接发我；没有的话我会按官方来源自己查。
```

### Step 4: Collision Resolution

If `models.providers.<provider_id>`, `~/.openclaw/.env`, or `agents.defaults.models["<provider_id>/<model_id>"]` already exists and does not clearly match the requested target, stop and ask one explicit resolution question:

```text
我发现现有配置里已经有同名项，不能安全直接覆盖。你要我：
1. 复用现有名称并覆盖
2. 保留现有项，改一个新的 relay_name / model_family
3. 先停止，我把冲突细节列给你确认
```

### Step 5: Pre-Execution Confirmation

Before any write or delete, show a final summary and wait for explicit confirmation.

Add or update confirmation template:

```text
我将执行以下配置：
- provider_id: <provider_id>
- api_key_env: <API_KEY_ENV>
- base_url: <base_url>
- api: <api>
- model_id: <model_id>
- model_name: <model_name>
- contextWindow: <context_window>
- maxTokens: <max_tokens>
- 注册到 agents.defaults.models: <provider_id>/<model_id>
- 是否设为默认模型: <yes-or-no>

确认后我再执行写入。
```

Remove confirmation template:

```text
我将执行以下删除：
- 删除 provider: <provider_id>
- 从 agents.defaults.models 删除: <provider_id>/...
- 删除环境变量: <yes-or-no>
- 清理默认模型指向: <yes-or-no>

确认后我再执行删除。
```

## Required Inputs

Before writing any config, make sure you know:

- relay base URL
- protocol type
- model ID
- API key

If any of these are missing, ask the user directly in chat following the guided flow above. Do not rely on shell prompts for missing business inputs.

## Naming Rules

Always derive names before writing config:

- `relay_name`: normalized relay/site name
  - Example: `packyapi`
- `model_family`: normalized model family/group
  - Example: `chatgpt`, `claude`, `gemini`
- `provider_id`: `relay_name + "_" + model_family`
  - Example: `packyapi_chatgpt`
- `api_key_env`: uppercase `relay_name + "_" + model_family + "_API_KEY"`
  - Example: `PACKYAPI_CHATGPT_API_KEY`

These names must be decided in the skill layer, not guessed during execution. Do not ask the user for these derived values unless a collision requires a rename choice.

## Collision Checks

Before writing:

1. Inspect current config and env:

```bash
sed -n '1,240p' ~/.openclaw/openclaw.json
sed -n '1,120p' ~/.openclaw/.env
```

2. Check whether `models.providers.<provider_id>` already exists.
3. Check whether `api_key_env` already exists in `~/.openclaw/.env`.
4. Check whether `agents.defaults.models` already contains a conflicting `<provider_id>/<model_id>` entry.

If any of these names already exist and clearly point to a different relay, model family, or secret, stop and ask the user whether to:

- reuse the existing name
- overwrite the existing entry
- choose a different `relay_name` or `model_family`

Do not overwrite a collided name silently.

## Model Validation

If the chosen protocol is `openai-responses` or `openai-completions`, probe the model list before writing config:

```bash
curl -sS -L \
  -H "Accept: application/json" \
  -H "Authorization: Bearer <api-key>" \
  "<base-url-without-trailing-slash>/models"
```

Interpretation:

- HTTP/network failure: stop and surface the failure
- endpoint responds but no recognizable model list: stop unless you have provider docs proving the model/protocol pair
- model not found: tell the user and do not write config

For `anthropic-messages` or `google-generative-ai`, generic probing is not reliable. Use provider docs first.

After model existence is confirmed, resolve the model limits from official docs before writing config:

- prefer the vendor's official model page or comparison table
- use `exa` / `context7` when available to pull those docs into the current session
- if `exa` / `context7` are unavailable, use a user-provided official doc link or the current platform's native web browsing/search capability
- record the exact `contextWindow` and `maxTokens` you verified
- do not guess limits

If you cannot access an official source at all, stop and tell the user you cannot safely verify the limits.

Use this fixed sequence:

1. confirm the model id and protocol
2. probe model existence when the protocol supports it
3. fetch official documentation with `exa` / `context7`; if unavailable, fall back to a user-provided official link or native web browsing/search
4. extract `contextWindow` and `maxTokens`
5. show the user the resolved limits and source links
6. only then write config

User-facing summary template before execution:

```text
已确认模型: <model-id>
协议: <api>
官方规格:
- contextWindow: <N>
- maxTokens: <N>
来源:
- <official-link-1>
- <official-link-2>
接下来将写入 models.providers.<provider_id>，并把 <provider_id>/<model_id> 注册进 agents.defaults.models。
```

## Add or Update Flow

When the values are final:

1. Write the provider payload:

```bash
openclaw config set models.mode '"merge"' --strict-json

openclaw config set "models.providers.<provider_id>" '{
  "baseUrl": "<base-url>",
  "apiKey": "${<API_KEY_ENV>}",
  "api": "<api>",
  "models": [
    {
      "id": "<model-id>",
      "name": "<model-name>",
      "reasoning": false,
      "input": ["text"],
      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
      "contextWindow": <context-window>,
      "maxTokens": <max-tokens>
    }
  ]
}' --strict-json
```

2. If the user provided an API key, update `~/.openclaw/.env`.

3. Read and update `agents.defaults.models`. This step is required. If `<provider_id>/<model_id>` is not added here, the relay model may not appear in OpenClaw `/model`.

```bash
current_models_json="$(openclaw config get agents.defaults.models 2>/dev/null || true)"

updated_models_json="$(
  printf '%s' "${current_models_json}" | \
    node ./scripts/models_catalog_helper.mjs upsert \
      --model-ref "<provider_id>/<model_id>" \
      --alias "<model-name>"
)"

openclaw config set agents.defaults.models "${updated_models_json}" --strict-json
openclaw config set agents.defaults.model.primary '"<provider_id>/<model_id>"' --strict-json
```

4. Confirm:

```bash
openclaw config get "models.providers.<provider_id>"
openclaw config get agents.defaults.models
openclaw config get agents.defaults.model.primary
openclaw models list
openclaw config validate
openclaw status
```

If gateway did not hot reload correctly:

```bash
openclaw gateway restart
```

## Remove Flow

When the user wants a relay removed, decide the exact `provider_id`, `api_key_env`, and target default model ref first.

1. Remove the provider:

```bash
openclaw config unset "models.providers.<provider_id>"
```

2. Remove matching entries from `agents.defaults.models`:

```bash
current_models_json="$(openclaw config get agents.defaults.models 2>/dev/null || true)"

updated_models_json="$(
  printf '%s' "${current_models_json}" | \
    node ./scripts/models_catalog_helper.mjs remove-provider \
      --provider-id "<provider_id>"
)"
```

3. Write the remaining catalog back. If the result is `{}`, unset `agents.defaults.models` instead of writing an empty object.

```bash
if [[ "${updated_models_json}" == "{}" ]]; then
  openclaw config unset agents.defaults.models || true
else
  openclaw config set agents.defaults.models "${updated_models_json}" --strict-json
fi
```

4. If `agents.defaults.model.primary` equals the relay model ref being removed, clear or move it as intended.

5. Remove the env key from `~/.openclaw/.env` when requested.

6. Confirm:

- `models.providers.<provider_id>` no longer exists
- any `agents.defaults.models` entries for `<provider_id>/...` are removed
- the env key is gone
- `agents.defaults.model.primary` is cleared or moved elsewhere as intended

## Resources

### scripts/

- `scripts/models_catalog_helper.mjs`: JSON-only helper for `agents.defaults.models`

### references/

- `references/relay-protocols.md`: protocol guidance, naming rules, and structure notes

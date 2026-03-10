---
name: openclaw-relay-config
description: "Configure or remove OpenClaw relay providers in ~/.openclaw/openclaw.json. Use when you need to add, update, validate, or remove models.providers.* entries for OpenAI-compatible, Anthropic-compatible, or Google-compatible relays. This skill is responsible for collecting missing inputs, deriving naming, checking collisions, validating model availability, and then calling the execution-only scripts."
---

# OpenClaw Relay Config

## Overview

Use this skill when OpenClaw needs a relay or proxy model provider.

When referring to bundled files, resolve paths relative to this skill directory. Do not assume a user-specific install path.

This skill owns the decision-making layer:

- collect missing inputs from the user
- decide the naming
- check collisions before any write
- validate the requested model when possible
- only then call the scripts

The scripts in `scripts/` are execution-only. They must be called with final, explicit values and should not be used as the place where you ask the user what to do.

For protocol choices and current OpenClaw config boundaries, read `references/relay-protocols.md`.

## Required Inputs

Before calling any script, make sure you know:

- relay base URL
- protocol type
- model ID
- API key

If any of these are missing, ask the user directly in chat. Do not rely on shell prompts for missing business inputs.

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

These names should be decided in the skill layer, not guessed inside the execution scripts.

## Collision Checks

Before writing:

1. Inspect current config and env:

```bash
sed -n '1,240p' ~/.openclaw/openclaw.json
sed -n '1,120p' ~/.openclaw/.env
```

2. Check whether `models.providers.<provider_id>` already exists.

3. Check whether `api_key_env` already exists in `~/.openclaw/.env`.

4. If either name already exists and clearly points to a different relay, model family, or secret, stop and ask the user whether to:

- reuse the existing name
- overwrite the existing entry
- choose a different `relay_name` or `model_family`

Do not overwrite a collided name silently.

## Model Validation

If the chosen protocol is `openai-responses` or `openai-completions`, validate the model before writing config:

```bash
./scripts/check_relay_model.sh \
  --base-url https://your-relay.example.com/v1 \
  --api openai-responses \
  --model-id your-model-id \
  --api-key-value "sk-xxxx"
```

Interpretation:

- exit `0`: model exists, continue
- exit `2`: model list request failed, stop and surface the failure
- exit `3`: endpoint does not expose a recognizable list, stop unless you have provider docs proving the model/protocol pair
- exit `4`: model not found, tell the user and do not write config

If the protocol is `anthropic-messages` or `google-generative-ai`, generic probing is not reliable. In those cases:

- use provider docs first
- use documentation search tools such as `exa` or `context7` only if the current platform provides them
- if docs remain ambiguous, tell the user that the model list cannot be safely verified from the generic probe path

## Add or Update Flow

When the values are final, run:

```bash
./scripts/configure_relay.sh \
  --provider-id packyapi_chatgpt \
  --api-key-env PACKYAPI_CHATGPT_API_KEY \
  --base-url https://your-relay.example.com/v1 \
  --api openai-responses \
  --model-id gpt-5.4 \
  --model-name "GPT-5.4" \
  --api-key-value "sk-xxxx"
```

Then confirm:

```bash
openclaw config get models.providers.packyapi_chatgpt
openclaw config get agents.defaults.model.primary
openclaw config validate
openclaw status
```

## Remove Flow

When the user wants a relay removed, decide the exact `provider_id` and `api_key_env` first, then run:

```bash
./scripts/remove_relay.sh \
  --provider-id packyapi_chatgpt \
  --api-key-env PACKYAPI_CHATGPT_API_KEY \
  --clear-default-if-match packyapi_chatgpt/gpt-5.4
```

Then confirm that:

- `models.providers.<provider_id>` no longer exists
- the env key is gone
- `agents.defaults.model.primary` is cleared or moved elsewhere as intended

## Resources

### scripts/

- `scripts/configure_relay.sh`: execution-only add/update script
- `scripts/check_relay_model.sh`: execution-only model existence probe
- `scripts/remove_relay.sh`: execution-only remove script

### references/

- `references/relay-protocols.md`: protocol guidance, naming rules, and structure notes

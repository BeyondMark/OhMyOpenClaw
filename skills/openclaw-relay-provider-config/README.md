# OpenClaw Relay Provider Config

这个目录提供一个轻脚本 Skill，用于为 OpenClaw 配置、验证、更新或删除 relay provider。

## 触发限制

- 这个 skill 是“仅手动触发 / 仅显式调用”
- 只有在用户明确要求配置、更新、删除 relay provider，或者明确点名 `openclaw-relay-provider-config` 时才允许启动
- 不能因为用户只是提到模型、中转、OpenClaw、代理之类的相近话题就自动触发

## 目标

- 在 `~/.openclaw/openclaw.json` 中按新版结构维护 `models.providers.<providerId>`
- 同步维护 `agents.defaults.models`，让新 relay 模型能出现在 OpenClaw `/model`
- 记录协议选择、命名规则、重名检查和最小验证步骤
- 提供真正的向导式输入流程，避免 agent 漏问、乱问或跳步执行
- 将流程逻辑保留在 `SKILL.md`，只保留一个极小 helper 处理 catalog JSON

## 版本结论

- 本文档对应的核对时间是 `2026-03-09`
- 当时确认的 OpenClaw 最新稳定版为 `v2026.3.8`
- 这一版本下，relay 配置位置是 `models.providers.<providerId>`，不是旧式根级代理字段

## 关键配置位置

- 配置文件：`~/.openclaw/openclaw.json`
- 推荐同时设置：
  - `models.mode: "merge"`
  - `models.providers.<providerId>`
  - `agents.defaults.models["<providerId>/<modelId>"]`
  - `agents.defaults.model.primary`

推荐结构：

```json5
{
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
      models: {
        "packyapi_chatgpt/your-model-id": { alias: "Your Relay Model" },
      },
      model: { primary: "packyapi_chatgpt/your-model-id" },
    },
  },
  models: {
    mode: "merge",
    providers: {
      packyapi_chatgpt: {
        baseUrl: "https://your-relay.example.com/v1",
        apiKey: "${PACKYAPI_CHATGPT_API_KEY}",
        api: "openai-responses",
        models: [
          {
            id: "your-model-id",
            name: "Your Relay Model",
            reasoning: false,
            input: ["text"],
            cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
            contextWindow: 1050000,
            maxTokens: 128000,
          },
        ],
      },
    },
  },
}
```

说明：

- `agents.defaults.models` 一旦存在，就会成为 OpenClaw 的模型 allowlist/catalog。
- 如果只写 `models.providers.*` 或只写 `agents.defaults.model.primary`，新 relay 模型仍可能不会出现在 `/model`。
- 在这个 skill 里，把 `<providerId>/<modelId>` 注册进 `agents.defaults.models` 是必做步骤，不是可选优化。
- 上面这组 `1050000 / 128000` 只适用于示例模型，不应用作其它模型的默认值。

## 精简后的职责边界

### `SKILL.md`

负责：

- 收集缺失业务参数
- 按固定顺序做向导式提问和确认
- 推导命名
- 检查重名和覆盖风险
- 通过官方资料确认 `contextWindow` / `maxTokens`
- 直接执行 `openclaw config` 和环境变量修改命令
- 调用 helper 同步 `agents.defaults.models`

### `scripts/models_catalog_helper.mjs`

只负责：

- 从 stdin 读取当前 `agents.defaults.models` JSON
- 为 `<providerId>/<modelId>` 添加或更新 alias
- 删除某个 provider 的全部 catalog 条目
- 输出新的 JSON 到 stdout

它不负责：

- 读写真实配置文件
- 调用 `openclaw`
- 模型探测
- 命名推导
- 环境变量写入

## 推荐流程模板

1. 先确认 `model_id` 和 `api`
2. 对 `openai-responses` / `openai-completions` 先探测 relay 是否暴露模型列表
3. 再用官方文档配合 `exa` / `context7` 查 `contextWindow` 和 `maxTokens`
4. 把数值和来源回显给用户
5. 写入 `models.providers.<providerId>`
6. 把 `<providerId>/<modelId>` 注册进 `agents.defaults.models`
7. 再检查 `/model`、validate 和 status

## 向导式输入流程

这个 skill 现在要求 agent 按固定顺序收集参数，而不是自由发挥：

1. 先判断是 `新增`、`更新` 还是 `删除`
2. 新增/更新时，优先收集：
   - `base_url`
   - `api`
   - `model_id`
   - `api_key`
3. 只在必要时再补问：
   - `model_name`
   - `relay_name`
   - `model_family`
   - 是否设为默认模型
4. 删除时，优先确认：
   - `provider_id`
   - 是否删除 env key
   - 是否清理默认模型指向
5. 发生命名冲突时，不允许静默覆盖，必须先让用户做三选一决策
6. 在任何写入前，都要先回显最终将写入的 provider、catalog 和默认模型变更，再等用户确认

推荐核心提问模板：

```text
还缺这些关键信息，请按顺序给我：
1. relay 的 base URL
2. 协议类型：openai-responses / openai-completions / anthropic-messages / google-generative-ai
3. 模型 ID
4. API key
```

执行前确认模板：

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

## helper 用法

新增或更新一个模型：

```bash
current_models_json="$(openclaw config get agents.defaults.models 2>/dev/null || true)"

updated_models_json="$(
  printf '%s' "${current_models_json}" | \
    node ./scripts/models_catalog_helper.mjs upsert \
      --model-ref "packyapi_chatgpt/gpt-5.4" \
      --alias "Packy GPT-5.4"
)"
```

删除一个 provider 的所有 catalog 条目：

```bash
current_models_json="$(openclaw config get agents.defaults.models 2>/dev/null || true)"

updated_models_json="$(
  printf '%s' "${current_models_json}" | \
    node ./scripts/models_catalog_helper.mjs remove-provider \
      --provider-id "packyapi_chatgpt"
)"
```

写回时：

```bash
if [[ "${updated_models_json}" == "{}" ]]; then
  openclaw config unset agents.defaults.models || true
else
  openclaw config set agents.defaults.models "${updated_models_json}" --strict-json
fi
```

## 最小验证

写入或更新后至少执行一次：

```bash
openclaw config get models.providers.packyapi_chatgpt
openclaw config get agents.defaults.models
openclaw models list
openclaw config validate
openclaw status
```

如果 gateway 没有热更新成功，再执行：

```bash
openclaw gateway restart
```

## 兼容性说明

### Claude Code

- 兼容核心是 `SKILL.md`、`scripts/models_catalog_helper.mjs`、`references/`

### OpenAI / Codex

- 兼容 `SKILL.md` 核心结构
- `agents/openai.yaml` 作为 OpenAI/Codex 的扩展提示保留

### OpenClaw

- 兼容 `SKILL.md` 核心结构
- 如未来需要 `metadata.openclaw.requires` 等加载约束，可作为 OpenClaw 增强层追加

## 本目录文件

- `SKILL.md`：agent 入口
- `README.md`：人类说明
- `agents/openai.yaml`：OpenAI / Codex 扩展元数据
- `references/relay-protocols.md`：协议选择说明
- `scripts/models_catalog_helper.mjs`：`agents.defaults.models` 的 JSON helper
- `tests/models_catalog_helper_test.sh`：helper 测试

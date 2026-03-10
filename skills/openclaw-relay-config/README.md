# OpenClaw Relay Config

这个目录提供一个可执行 Skill，用于为 OpenClaw 配置、验证、更新或删除 relay provider。

## 目标

- 在 `~/.openclaw/openclaw.json` 中按新版结构维护 `models.providers.<providerId>`
- 记录协议选择、命名规则、重名检查和最小验证步骤
- 保持 `SKILL.md` 可被 Claude Code、OpenAI/Codex、OpenClaw 共同理解

## 版本结论

- 本文档对应的核对时间是 `2026-03-09`
- 当时确认的 OpenClaw 最新稳定版为 `v2026.3.8`
- 这一版本下，relay 配置位置是 `models.providers.<providerId>`，不是旧式根级代理字段

## 关键配置位置

- 配置文件：`~/.openclaw/openclaw.json`
- 推荐同时设置：
  - `models.mode: "merge"`
  - `models.providers.<providerId>`
  - `agents.defaults.model.primary`

推荐结构：

```json5
{
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
      model: { primary: "relay/your-model-id" },
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
            contextWindow: 128000,
            maxTokens: 16384,
          },
        ],
      },
    },
  },
}
```

## 支持的协议类型

当前官方文档确认 `models.providers.<providerId>.api` 支持这 4 种值：

- `openai-completions`
- `openai-responses`
- `anthropic-messages`
- `google-generative-ai`

选择建议：

- `openai-responses`
  - 优先用于兼容 OpenAI Responses API 的新中转
- `openai-completions`
  - 用于只兼容 `/v1/chat/completions` 的 OpenAI 风格接口
- `anthropic-messages`
  - 用于 Claude / Anthropic 风格的 `/v1/messages` 接口
- `google-generative-ai`
  - 用于 Gemini / Google Generative AI 风格接口

## 命名规则

- `relay_name`：归一化的中转站名
  - 例如：`packyapi`
- `model_family`：归一化的模型分组名
  - 例如：`chatgpt`、`claude`、`gemini`
- `provider_id = relay_name + "_" + model_family`
  - 例如：`packyapi_chatgpt`
- `api_key_env = relay_name + "_" + model_family + "_API_KEY"` 的大写形式
  - 例如：`PACKYAPI_CHATGPT_API_KEY`

这样做是为了避免多个中转站、多个模型分组并存时的命名冲突。

## Skill 与脚本的职责边界

### `SKILL.md`

负责：

- 收集缺失业务参数
- 推导命名
- 检查重名和覆盖风险
- 判断是否继续
- 在合适时调用脚本

### `scripts/check_relay_model.sh`

负责：

- 对 `openai-responses` / `openai-completions` 做模型存在性探测
- 返回明确退出码供 skill 判断

### `scripts/configure_relay.sh`

负责：

- 用明确参数写入或更新配置
- 可选写入 `~/.openclaw/.env`
- 校验配置并重启 gateway

### `scripts/remove_relay.sh`

负责：

- 删除指定 provider
- 可选删除对应 env key
- 可选清理匹配的默认模型

## 最小验证

写入或更新后至少执行一次：

```bash
openclaw config get models.providers.packyapi_chatgpt
openclaw config validate
openclaw status
```

如果 gateway 没有热更新成功，再执行：

```bash
openclaw gateway restart
```

## 兼容性说明

### Claude Code

- 兼容核心是 `SKILL.md`、`scripts/`、`references/`
- 若需额外 subagent 能力，应通过 Claude Code 自己的 agent 机制定义，而不是依赖 `agents/openai.yaml`

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
- `scripts/configure_relay.sh`：配置或更新 relay
- `scripts/check_relay_model.sh`：探测模型是否存在
- `scripts/remove_relay.sh`：移除 relay

## 参考资料

- <https://github.com/openclaw/openclaw/releases/tag/v2026.3.8>
- <https://openclawlab.com/en/docs/gateway/configuration/>
- <https://openclawlab.com/en/docs/concepts/model-providers/>
- <https://github.com/openclaw/openclaw/blob/main/docs/gateway/configuration-reference.md>
- <https://github.com/openclaw/openclaw/blob/main/docs/gateway/configuration-examples.md>

# OpenClaw Relay Protocols

## 当前结论
- 适用版本：`OpenClaw v2026.3.8`
- 模型中转通过 `models.providers.<providerId>.api` 选择协议类型。
- 当前官方文档列出的有效值只有 4 个：
  - `openai-completions`
  - `openai-responses`
  - `anthropic-messages`
  - `google-generative-ai`

## 如何选择

### `openai-responses`
- 适合兼容 OpenAI Responses API 的新中转。
- 如果中转文档明确提到 Responses API、`/v1/responses`、结构化 output 或更现代的 OpenAI 兼容接口，优先选它。

### `openai-completions`
- 适合只兼容 Chat Completions 的 OpenAI 风格网关。
- 如果中转文档只提供 `/v1/chat/completions` 示例，通常应该选这个。

### `anthropic-messages`
- 适合 Claude 风格的 `/v1/messages` 接口。
- 常见于 Anthropic 兼容网关或 Anthropic 风格自建中转。

### `google-generative-ai`
- 适合 Gemini/Google Generative AI 风格的接口。

## 字段提醒

命名建议：

- `providerId` 建议使用 `中转站名_模型分组名`
  - 例如：`packyapi_chatgpt`、`packyapi_claude`、`packyapi_gemini`
- `apiKey` 对应环境变量建议使用 `中转站名_模型分组名_API_KEY`
  - 例如：`PACKYAPI_CHATGPT_API_KEY`、`PACKYAPI_CLAUDE_API_KEY`、`PACKYAPI_GEMINI_API_KEY`

这样做的目的是避免以后接多个中转站、多个模型分组时命名冲突。

结构提醒：

- 外层 `models` 是 OpenClaw 的总配置容器。
- 内层 `models.providers.<providerId>.models` 是这个 provider 自己的模型目录。
- 这两个 `models` 不是重复字段，不能合并成一个。

推荐写法：

```json5
{
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

## 不要误判成“版本号配置”
- 模型中转这里没有单独的 `apiVersion` 或 `protocolVersion` 配置项。
- 协议选择方式就是 `api` 字段的枚举值。
- 如果看见 `protocolVersion: 1`，那是别的内部协议文档，不是模型中转配置。

## 修改后最少验证

```bash
openclaw config get models.providers.packyapi_chatgpt
openclaw config validate
openclaw status
```

## Skill 与脚本的职责边界
- `SKILL.md` 负责：
  - 向用户收集缺失参数
  - 推导 `relay_name`、`model_family`、`provider_id`、`api_key_env`
  - 检查 `openclaw.json` 与 `~/.openclaw/.env` 是否重名
  - 在写配置前决定是否继续
- `scripts/configure_relay.sh` 负责：
  - 用明确参数写入或更新配置
  - 可选写入 `~/.openclaw/.env`
  - 校验配置并重启 gateway
- `scripts/check_relay_model.sh` 负责：
  - 对 `openai-responses` / `openai-completions` 走 `GET <baseUrl>/models` 探测
  - 返回明确的退出码，供 skill 判断是否继续
- `scripts/remove_relay.sh` 负责：
  - 删除指定 provider
  - 可选删除 env key
  - 可选清理匹配的默认模型

## 命名规则
- `providerId = 中转站名_模型分组名`
- `apiKeyEnv = 中转站名_模型分组名_API_KEY`
- 示例：
  - `packyapi_chatgpt`
  - `PACKYAPI_CHATGPT_API_KEY`

## 模型探测规则
- `openai-responses` / `openai-completions`
  - 优先用 `scripts/check_relay_model.sh`
- `anthropic-messages` / `google-generative-ai`
  - 通用 `GET /models` 不可靠
  - 需要结合文档判断；如果当前平台提供 `exa` / `context7` 等文档搜索工具，可辅助确认

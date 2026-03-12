# OpenClaw Relay Protocols

## 当前结论

- 适用版本：`OpenClaw v2026.3.8`
- 模型中转通过 `models.providers.<providerId>.api` 选择协议类型
- 当前官方文档列出的有效值只有 4 个：
  - `openai-completions`
  - `openai-responses`
  - `anthropic-messages`
  - `google-generative-ai`

## 如何选择

### `openai-responses`

- 适合兼容 OpenAI Responses API 的新中转
- 如果中转文档明确提到 Responses API、`/v1/responses`、结构化 output 或更现代的 OpenAI 兼容接口，优先选它

### `openai-completions`

- 适合只兼容 Chat Completions 的 OpenAI 风格网关
- 如果中转文档只提供 `/v1/chat/completions` 示例，通常应该选这个

### `anthropic-messages`

- 适合 Claude 风格的 `/v1/messages` 接口
- 常见于 Anthropic 兼容网关或 Anthropic 风格自建中转

### `google-generative-ai`

- 适合 Gemini / Google Generative AI 风格的接口

## 字段提醒

命名建议：

- `providerId` 建议使用 `中转站名_模型分组名`
  - 例如：`packyapi_chatgpt`、`packyapi_claude`、`packyapi_gemini`
- `apiKeyEnv` 建议使用 `中转站名_模型分组名_API_KEY` 的大写形式
  - 例如：`PACKYAPI_CHATGPT_API_KEY`、`PACKYAPI_CLAUDE_API_KEY`、`PACKYAPI_GEMINI_API_KEY`

结构提醒：

- 外层 `models` 是 OpenClaw 的总配置容器
- 内层 `models.providers.<providerId>.models` 是这个 provider 自己的模型目录
- `agents.defaults.models` 是 OpenClaw `/model` 使用的 allowlist/catalog
- 这两个 `models` 不是重复字段，不能合并成一个

推荐写法：

```json5
{
  agents: {
    defaults: {
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

如果没有把 `<providerId>/<modelId>` 同步写进 `agents.defaults.models`，OpenClaw `/model` 里通常不会出现这个 relay 模型。

## 无脚本执行边界

- `SKILL.md` 负责：
  - 向用户收集缺失参数
  - 推导 `relay_name`、`model_family`、`provider_id`、`api_key_env`
  - 检查 `openclaw.json` 与 `~/.openclaw/.env` 是否重名
  - 确认模型 limits 的官方来源
  - 直接执行 `openclaw config` 和 `.env` 修改命令
- `scripts/models_catalog_helper.mjs` 负责：
  - 为 `agents.defaults.models` 做安全的 JSON upsert/remove
  - 保证 `<providerId>/<modelId>` 能被正确加入 catalog
  - 在删除 provider 时移除对应的全部 catalog 项

## 模型探测规则

- `openai-responses` / `openai-completions`
  - 优先请求 `GET <baseUrl>/models`
  - 通过模型存在性探测后，再用官方文档确认 `contextWindow` / `maxTokens`
- `anthropic-messages` / `google-generative-ai`
  - 通用 `GET /models` 不可靠
  - 需要结合文档判断；如果当前平台提供 `exa` / `context7` 等文档搜索工具，可辅助确认
  - 如果没有这些工具，退回到用户提供的官方文档链接，或当前平台原生网页搜索/浏览能力
  - 如果拿不到官方来源，就不要猜测 `contextWindow` / `maxTokens`

## 修改后最少验证

```bash
openclaw config get models.providers.packyapi_chatgpt
openclaw config get agents.defaults.models
openclaw models list
openclaw config validate
openclaw status
```

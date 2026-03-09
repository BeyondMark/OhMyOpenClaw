# 2026-03-09 OpenClaw 中转 API 配置笔记

## 目标
- 在最新版本 OpenClaw 中，为 `~/.openclaw/openclaw.json` 增加一套可复用的中转 API 配置方法。
- 记录“应该写哪些字段”“支持哪些协议”“什么时候该用哪种协议”，避免下次重复查文档。
- 配套提供一个可执行 skill，直接把配置写进 OpenClaw，而不是只留一段手工教程。

## 版本结论
- 联网核对后，`2026-03-09` 的 OpenClaw 最新稳定版是 `v2026.3.8`。
- 本机执行 `openclaw --version`，当前已安装版本也是 `OpenClaw 2026.3.8`。
- 这一版下，`~/.openclaw/openclaw.json` 的中转 API 配置方式是新增 `models.providers.<providerId>`，而不是在根级写旧式代理字段。

## 正确配置位置
- 配置文件：`~/.openclaw/openclaw.json`
- 推荐同时设置：
  - `models.mode: "merge"`
  - `models.providers.<providerId>`
  - `agents.defaults.model.primary`

命名建议：

- `providerId` 用 `中转站名_模型分组名`
  - 例如：`packyapi_chatgpt`
- 环境变量名用 `中转站名_模型分组名_API_KEY`
  - 例如：`PACKYAPI_CHATGPT_API_KEY`

这样后面继续添加 `claude`、`gemini`、`chatgpt` 或不同中转时，不容易冲突。

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

注意：

- 外层 `models` 是 OpenClaw 的总配置容器。
- 内层 `providers.<providerId>.models` 是某个 provider 的模型列表。
- 这两个 `models` 不是重复配置，不能合并。

## 支持的协议类型
当前官方文档确认 `models.providers.<providerId>.api` 支持这 4 种值：

- `openai-completions`
- `openai-responses`
- `anthropic-messages`
- `google-generative-ai`

选择建议：

- `openai-responses`
  - 优先用于兼容 OpenAI Responses API 的新中转。
  - 如果中转站明确支持 Responses，这个通常是首选。
- `openai-completions`
  - 用于只兼容 `/v1/chat/completions` 的 OpenAI 风格接口。
  - 很多传统兼容站、老 LiteLLM 配置、部分社区代理仍然停留在这一层。
- `anthropic-messages`
  - 用于 Claude/Anthropic 风格的 `/v1/messages` 接口。
  - 适合 Anthropic 兼容中转或自建 Anthropic 风格代理。
- `google-generative-ai`
  - 用于 Gemini/Google Generative AI 风格接口。

## 一个容易混淆的点
- 这类模型中转配置没有查到单独的 `apiVersion` 或 `protocolVersion` 字段。
- 在 OpenClaw 这里，中转协议是通过 `api` 枚举值选择的，不是通过再填一个数字版本号选择的。
- 唯一查到的 `protocolVersion: 1` 出现在 secrets 的 exec provider 协议里，和模型中转 API 不是一回事。

## 当前本机配置状态
当前 `~/.openclaw/openclaw.json` 已有：

- `agents.defaults.workspace`
- `gateway.mode`
- `gateway.auth`

但还没有：

- `models.providers`
- `agents.defaults.model.primary`

所以要做的是“按新版结构新增”，不是迁移一套旧的中转字段。

## 配置时的实践建议
- 密钥优先放到 `~/.openclaw/.env`，配置文件中只引用 `${ENV_NAME}`。
- `models.mode` 建议显式写成 `merge`，避免把其他 provider 目录覆盖掉。
- `providerId` 建议按 `中转站名_模型分组名` 命名，例如 `packyapi_chatgpt`、`packyapi_claude`、`packyapi_gemini`。
- 环境变量建议按 `中转站名_模型分组名_API_KEY` 命名，例如 `PACKYAPI_CHATGPT_API_KEY`。
- 写完后至少执行一次：

```bash
openclaw config validate
openclaw status
```

- 如果 gateway 没有热更新成功，再手动执行：

```bash
openclaw gateway restart
```

## 配套 Skill
- Skill 路径：`01-笔记/99-AI记录/OpenClaw/skills/openclaw-relay-config/`
- 入口文件：`01-笔记/99-AI记录/OpenClaw/skills/openclaw-relay-config/SKILL.md`
- 执行脚本：`01-笔记/99-AI记录/OpenClaw/skills/openclaw-relay-config/scripts/configure_relay.sh`
- 探测脚本：`01-笔记/99-AI记录/OpenClaw/skills/openclaw-relay-config/scripts/check_relay_model.sh`
- 删除脚本：`01-笔记/99-AI记录/OpenClaw/skills/openclaw-relay-config/scripts/remove_relay.sh`

示例：

```bash
cd /Users/mark/notes/01-笔记/99-AI记录/OpenClaw/skills/openclaw-relay-config

./scripts/configure_relay.sh \
  --relay-name packyapi \
  --model-family chatgpt \
  --base-url https://your-relay.example.com/v1 \
  --api openai-responses \
  --model-id your-model-id \
  --model-name "Your Relay Model" \
  --api-key-env PACKYAPI_CHATGPT_API_KEY \
  --api-key-value "sk-xxxx"
```

重构后的职责划分：

1. `SKILL.md` 负责收集参数、命名推导、重名检查、决定是否继续
2. `check_relay_model.sh` 负责执行模型列表探测
3. `configure_relay.sh` 只负责按已确定参数写配置
4. `remove_relay.sh` 只负责按已确定参数删除配置

这样后面如果命名策略、重名规则、协议判断要调整，优先改 skill，不用反复改脚本。

## 适用场景
- 新增一个通用中转 API
- 把本地 OpenClaw 改为走 OpenAI 兼容中转
- 把 OpenClaw 接到 Anthropic 兼容代理
- 对现有 relay provider 进行覆盖更新

## 参考资料
- <https://github.com/openclaw/openclaw/releases/tag/v2026.3.8>
- <https://openclawlab.com/en/docs/gateway/configuration/>
- <https://openclawlab.com/en/docs/concepts/model-providers/>
- <https://github.com/openclaw/openclaw/blob/main/docs/gateway/configuration-reference.md>
- <https://github.com/openclaw/openclaw/blob/main/docs/gateway/configuration-examples.md>

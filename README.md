# OpenClaw Skills

这里是 `/home/mark/notes/01-笔记/99-AI记录/OpenClaw` 的 Skill 真源目录。

## 目录结构

- 根目录 `README.md`：总览和导航
- `skills/<skill-name>/SKILL.md`：给 agent 读取的入口文件
- `skills/<skill-name>/README.md`：给人阅读的说明文档
- `skills/<skill-name>/scripts/`：执行脚本
- `skills/<skill-name>/references/`：补充参考资料
- `skills/<skill-name>/agents/openai.yaml`：OpenAI / Codex 专用扩展元数据

## Skill 目录

### `openclaw-relay-config`

- 目录：`skills/openclaw-relay-config/`
- 人类说明：`skills/openclaw-relay-config/README.md`
- 作用：为 `~/.openclaw/openclaw.json` 新增、更新、验证或删除 relay provider
- 规则：先确认模型与协议，再从官方文档核实 `contextWindow` / `maxTokens`，把数值显式传给脚本；`configure_relay.sh` 不负责猜测这些 limits
- 降级：优先用 `exa` / `context7` 拉官方文档；如果没有这些工具，退回到用户提供的官方链接或当前平台原生网页搜索/浏览能力；拿不到官方来源时停止执行
- 入口脚本：
  - `scripts/configure_relay.sh`
  - `scripts/check_relay_model.sh`
  - `scripts/remove_relay.sh`

### `openclaw-gateway-repair`

- 目录：`skills/openclaw-gateway-repair/`
- 人类说明：`skills/openclaw-gateway-repair/README.md`
- 作用：排查并修复 OpenClaw 升级后 gateway 无限重启、阻塞启动或 `gateway.mode` 缺失问题
- 入口脚本：
  - `scripts/fix_gateway_mode.sh`

### `openclaw-agent-browser-install`

- 目录：`skills/openclaw-agent-browser-install/`
- 人类说明：`skills/openclaw-agent-browser-install/README.md`
- 作用：检测 Claude Code、Codex、OpenClaw 的安装情况，并为选定目标安装、配置、验证 `agent-browser`
- 入口脚本：
  - `scripts/detect_supported_tools.sh`
  - `scripts/install_agent_browser.sh`
  - `scripts/verify_agent_browser.sh`

## 说明

- 根目录 `README.md` 只保留目录导航。
- Skill 的具体背景、兼容性、执行流程和验证说明，都放在各自目录下的 `README.md` 与 `SKILL.md` 中。

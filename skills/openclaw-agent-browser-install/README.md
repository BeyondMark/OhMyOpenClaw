# OpenClaw Agent Browser Install

这个目录提供一个可执行 Skill，用于为 `Claude Code`、`Codex` 或 `OpenClaw` 安装并验证 `vercel-labs/agent-browser`。

## 目标

- 先检测机器上是否已安装 `Claude Code CLI`、`Codex CLI`、`OpenClaw`
- 当检测到多个目标时，由 AI 在对话里询问用户要装到哪个工具
- 用官方推荐方式安装 `agent-browser` CLI
- 对 `Claude Code` / `Codex` 安装官方 Skill
- 对 `OpenClaw` 安装本地共享 Skill
- 最后验证 CLI、Skill 文件和浏览器 smoke test

## 版本结论

- 本文档对应的核对时间是 `2026-03-10`
- 当时 `agent-browser` 官方站点推荐优先使用全局安装：

```bash
npm install -g agent-browser
agent-browser install
```

- 当时 `agent-browser` 官方对 AI coding agents 推荐使用：

```bash
npx skills add vercel-labs/agent-browser --skill agent-browser
```

- 当时 `OpenClaw` 官方说明本地共享 Skill 目录为 `~/.openclaw/skills`

## 为什么分两条安装流

### Claude Code / Codex

对这两类工具，直接跟随 `agent-browser` 官方 `skills` CLI 安装流最稳妥：

- 更新路径跟官方一致
- Skill 内容跟仓库保持同步
- 不需要手工复制 Skill 文件

### OpenClaw

对 OpenClaw，本 Skill 选择把官方 `skills/agent-browser` 目录复制到：

```text
~/.openclaw/skills/agent-browser
```

原因是：

- OpenClaw 官方明确支持从本地共享目录加载 AgentSkills 兼容 Skill
- 目前没有查到 `agent-browser` 官方把 OpenClaw 明确列为 `skills` CLI 目标
- 直接复制官方 Skill 目录更符合 OpenClaw 的加载模型

## 脚本职责

### `scripts/detect_supported_tools.sh`

负责：

- 检测 `claude`、`codex`、`openclaw`
- 返回版本信息
- 返回 `node`、`npm`、`npx`、`git`、`curl` 等前置命令状态

### `scripts/install_agent_browser.sh`

负责：

- 安装 `agent-browser` CLI
- 初始化 Chromium
- 按目标工具执行 Skill 安装
- 对 OpenClaw 在覆盖现有本地 Skill 时要求显式 `--force`

### `scripts/verify_agent_browser.sh`

负责：

- 检查 `agent-browser` CLI 是否存在
- 检查目标 Skill 文件是否落到正确位置
- 通过本地 `data:` URL 做一次无外网依赖的浏览器 smoke test

## 最小验证

至少确认以下三层：

```bash
./scripts/verify_agent_browser.sh --target claude-code --json
./scripts/verify_agent_browser.sh --target codex --json
./scripts/verify_agent_browser.sh --target openclaw --json
```

验证通过时，应能确认：

- `agent-browser` 命令存在
- 目标 Skill 目录下存在 `SKILL.md`
- `agent-browser open ...` 与 `snapshot -i` 能成功运行

对 `codex`，当前验证脚本会优先检查 `~/.agents/skills/agent-browser/SKILL.md`，并兼容旧的 `~/.codex/skills/agent-browser/SKILL.md`。

## 兼容性说明

### Claude Code

- 通过官方 `skills` CLI 安装 Skill
- 目标是全局可用

### OpenAI / Codex

- 通过官方 `skills` CLI 安装 Skill
- `agents/openai.yaml` 仅作为 OpenAI / Codex 的扩展元数据

### OpenClaw

- 通过 `~/.openclaw/skills` 加载官方 Skill 目录副本
- 新开 session 后即可被 OpenClaw 识别

## 本目录文件

- `SKILL.md`：agent 入口
- `README.md`：人类说明
- `agents/openai.yaml`：OpenAI / Codex 扩展元数据
- `references/install-matrix.md`：官方来源与安装映射
- `scripts/detect_supported_tools.sh`：环境检测脚本
- `scripts/install_agent_browser.sh`：安装脚本
- `scripts/verify_agent_browser.sh`：验证脚本

## 参考资料

- <https://agent-browser.dev/installation>
- <https://agent-browser.dev/skills>
- <https://agent-browser.dev/agent-mode>
- <https://github.com/vercel-labs/agent-browser>
- <https://github.com/vercel-labs/skills>
- <https://docs.openclaw.ai/tools/skills>

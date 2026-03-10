# Agent Browser 安装矩阵

## 核对时间

- `2026-03-10`

## 官方结论

### 1. CLI 安装

`agent-browser` 官方安装页推荐优先使用全局安装：

```bash
npm install -g agent-browser
agent-browser install
```

Linux 额外说明：

```bash
agent-browser install --with-deps
```

如果无法自动安装系统依赖，官方也给出手工回退：

```bash
npx playwright install-deps chromium
```

### 2. AI coding agent Skill 安装

`agent-browser` 官方安装页与 skills 页都说明，推荐通过 `skills` CLI 安装官方 Skill：

```bash
npx skills add vercel-labs/agent-browser --skill agent-browser
```

`vercel-labs/skills` 官方 README 也确认 `skills add` 支持：

- `-a, --agent`
- `-g, --global`
- `-y, --yes`
- `--list`

并示例使用 `claude-code`、`codex` 作为 agent 标识。

## 本 Skill 采用的映射

### 目标：`claude-code`

- 安装 CLI：

```bash
npm install -g agent-browser
agent-browser install
```

- 安装 Skill：

```bash
npx --yes skills add vercel-labs/agent-browser --skill agent-browser -g -a claude-code -y
```

### 目标：`codex`

- 安装 CLI：

```bash
npm install -g agent-browser
agent-browser install
```

- 安装 Skill：

```bash
npx --yes skills add vercel-labs/agent-browser --skill agent-browser -g -a codex -y
```

### 目标：`openclaw`

- 安装 CLI：

```bash
npm install -g agent-browser
agent-browser install
```

- 安装 Skill：

把官方仓库中的：

```text
skills/agent-browser
```

复制到：

```text
~/.openclaw/skills/agent-browser
```

## 选择理由

- `Claude Code` 与 `Codex`：直接跟随 `agent-browser` 官方 `skills` CLI 流程
- `OpenClaw`：直接跟随 OpenClaw 官方本地 Skill 目录加载机制

## 验证建议

### CLI 层

```bash
agent-browser --version
```

### Skill 文件层

- Claude Code：`~/.claude/skills/agent-browser/SKILL.md`
- Codex：优先检查 `~/.agents/skills/agent-browser/SKILL.md`，兼容 `~/.codex/skills/agent-browser/SKILL.md`
- OpenClaw：`~/.openclaw/skills/agent-browser/SKILL.md`

### 浏览器运行层

推荐使用本地 `data:` URL 而不是公网地址做 smoke test：

```bash
agent-browser open 'data:text/html,<button>Ready</button>'
agent-browser snapshot -i
agent-browser close
```

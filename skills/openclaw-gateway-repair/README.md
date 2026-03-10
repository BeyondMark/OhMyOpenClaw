# OpenClaw Gateway Repair

这个目录提供一个可执行 Skill，用于排查并修复 OpenClaw 升级后 gateway 无限重启、启动被阻塞，或 `gateway.mode` 缺失的问题。

## 背景

- 核对场景来自 `2026-03-09`
- 升级到 `OpenClaw 2026.3.8` 后，表面上 `gateway status` 可见服务信息，但后台实际可能持续重启
- 根因不是安装脚本损坏，而是新版对 `gateway.mode=local` 的显式要求

## 典型现象

- `launchd` 反复拉起 `ai.openclaw.gateway`
- `~/.openclaw/logs/gateway.err.log` 出现：

```text
Gateway start blocked: set gateway.mode=local (current: unset) or pass --allow-unconfigured.
```

- `/tmp/openclaw/openclaw-*.log` 可能伴随：

```text
gateway connect failed: Error: gateway closed (1008):
```

## 根因

- 新版本 gateway 启动时要求配置文件里显式存在 `gateway.mode=local`
- 如果缺失，gateway 会被阻止启动
- LaunchAgent 又带有 `keepalive`，所以外部表现会像“无限重启”

## 修复动作

推荐直接按 skill 中的流程执行：

```bash
openclaw gateway status
openclaw status
tail -n 40 ~/.openclaw/logs/gateway.err.log
tail -n 40 ~/.openclaw/logs/gateway.log
./scripts/fix_gateway_mode.sh
```

脚本内部目标是：

- 设置 `gateway.mode=local`
- 运行 `openclaw config validate`
- 重启 gateway
- 打印后续验证信息

## 修复后验证

至少确认以下几项：

```bash
openclaw config get gateway.mode
openclaw config validate
openclaw status
launchctl print gui/$(id -u)/ai.openclaw.gateway | sed -n '1,120p'
```

健康状态应表现为：

- `openclaw config get gateway.mode` 返回 `local`
- `openclaw config validate` 通过
- `openclaw status` 显示 `Gateway: local`
- `~/.openclaw/logs/gateway.log` 出现监听 `ws://127.0.0.1:` 的记录

## 如果脚本修完仍异常

- 优先阅读 `references/restart-loop.md`
- 不要继续猜端口、token 或 LaunchAgent 本身
- 先确认是否已经满足 `gateway.mode=local`

## 兼容性说明

### Claude Code

- `SKILL.md` 的核心工作流与脚本目录结构兼容 Claude Code skill 模式
- 不再依赖写死的个人绝对路径

### OpenAI / Codex

- `SKILL.md` 与 `agents/openai.yaml` 可配合使用
- `agents/openai.yaml` 只作为 OpenAI / Codex 扩展，不是通用前提

### OpenClaw

- 可直接作为 OpenClaw skill 使用
- 如未来需要 OpenClaw 专用加载约束，可通过 frontmatter 扩展追加

## 本目录文件

- `SKILL.md`：agent 入口
- `README.md`：人类说明
- `agents/openai.yaml`：OpenAI / Codex 扩展元数据
- `references/restart-loop.md`：补充排障说明
- `scripts/fix_gateway_mode.sh`：修复脚本

## 参考资料

- <https://docs.openclaw.ai/cli/gateway>
- <https://docs.openclaw.ai/cli/config>
- <https://docs.openclaw.ai/troubleshooting>

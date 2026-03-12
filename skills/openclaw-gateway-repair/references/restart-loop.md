# OpenClaw gateway 重启循环参考

## 典型命中信号

- `~/.openclaw/logs/gateway.err.log` 中出现：

```text
Gateway start blocked: set gateway.mode=local (current: unset) or pass --allow-unconfigured.
```

- `launchctl print gui/$(id -u)/ai.openclaw.gateway` 显示 LaunchAgent 已安装，但服务被反复拉起。
- `openclaw gateway status` 或 `/tmp/openclaw/*.log` 中伴随出现 `gateway closed (1008)` 一类连接失败日志。

## 首选修复

```bash
openclaw config set gateway.mode local
openclaw config validate
openclaw gateway restart
```

也可以按官方排障文档重新执行：

```bash
openclaw setup --mode local
```

## 为什么会循环

- 新版本要求显式存在 `gateway.mode=local`
- 未满足条件时 gateway 会拒绝启动
- LaunchAgent 仍会按 keepalive 策略再次拉起进程，于是表现为无限重启

## 如果 mode 已经是 local 仍异常

1. 重新查看 `~/.openclaw/logs/gateway.err.log` 和 `~/.openclaw/logs/gateway.log`
2. 运行 `openclaw config validate`
3. 运行 `openclaw status`
4. 核对 `~/.openclaw/openclaw.json` 中 `gateway.auth.mode`、`gateway.auth.token` 是否完整
5. 检查是否有端口占用或旧进程残留，再决定是否执行 `openclaw gateway restart`

如果这几项都正常，但某个自定义 relay 模型仍然没有出现在 OpenClaw `/model`，优先检查：

```bash
openclaw config get agents.defaults.models
openclaw models list
```

这通常不是 gateway 启动问题，而是 relay/provider 没有把 `<providerId>/<modelId>` 注册进 OpenClaw 的模型 allowlist。此时应改走 `openclaw-relay-provider-config`。

## 官方文档

- <https://docs.openclaw.ai/cli/gateway>
- <https://docs.openclaw.ai/cli/config>
- <https://docs.openclaw.ai/troubleshooting>

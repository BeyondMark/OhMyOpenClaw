# OpenClaw Permission Config

引导式权限配置工具，帮助用户在不同版本的 OpenClaw 中正确配置权限。

## 背景

OpenClaw 迭代频繁，权限体系跨越五个独立层级（Sandbox、Tool Policy、Elevated、Exec Approvals、Gateway Auth），不同版本之间存在 breaking changes（如 v2026.3.7 要求显式设置 `gateway.auth.mode`）。用户经常因为权限配置不当导致操作失败或安全暴露。

本 Skill 通过检测→审计→引导→应用→验证的流程，帮助用户一次性配置好所有权限层。

## 兼容性

- OpenClaw v2026.1.x 及以上
- macOS / Linux
- 需要 `openclaw` CLI 已安装
- `jq` 用于 exec-approvals 配置（可选）

## 五大权限层

| 层级 | 控制什么 | 配置位置 |
|------|---------|---------|
| Sandbox | 工具在哪里执行（Docker vs 宿主机） | `agents.defaults.sandbox.*` |
| Tool Policy | 哪些工具可用（allow/deny） | `tools.*` |
| Elevated | 沙箱中 exec 能否逃逸到宿主机 | `tools.elevated.*` |
| Exec Approvals | exec 命令的审批流程 | `~/.openclaw/exec-approvals.json` |
| Gateway Auth | 谁能访问 Gateway | `gateway.auth.*` + DM policy |

## 使用方式

### 在 Claude Code / Codex 中

```
使用 $openclaw-permission-config 检测我的 OpenClaw 版本并配置权限
```

### 手动流程

1. 运行 `scripts/detect_environment.sh --json` 检测环境
2. 运行 `scripts/audit_permissions.sh --json` 审计当前配置
3. 根据场景选择预设（见 `references/security-presets.md`）
4. 用 `scripts/apply_config.sh` 逐项应用配置
5. 用 `scripts/verify_permissions.sh --json` 验证结果

## 文件结构

```
openclaw-permission-config/
├── SKILL.md                         # AI agent 决策入口
├── README.md                        # 本文件
├── agents/openai.yaml               # Codex 扩展元数据
├── scripts/
│   ├── detect_environment.sh        # 检测 OpenClaw 版本和环境
│   ├── audit_permissions.sh         # 五维度权限审计
│   ├── apply_config.sh              # 配置写入（openclaw config set）
│   └── verify_permissions.sh        # 诊断验证
└── references/
    ├── permission-layers.md         # 五层权限详解 + 决策树
    ├── version-changes.md           # 版本间 breaking changes
    └── security-presets.md          # 四场景预设配置
```

## 参考

- [OpenClaw 官方配置文档](https://docs.openclaw.ai/gateway/configuration)
- [OpenClaw 沙箱文档](https://docs.openclaw.ai/gateway/sandboxing)
- [Sandbox vs Tool Policy vs Elevated](https://docs.openclaw.ai/gateway/sandbox-vs-tool-policy-vs-elevated)
- [Exec Approvals](https://docs.openclaw.ai/tools/exec-approvals)
- [Gateway Authentication](https://docs.openclaw.ai/gateway/authentication)

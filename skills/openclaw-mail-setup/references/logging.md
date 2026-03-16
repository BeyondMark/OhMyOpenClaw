# Logging Reference

本文档描述 `openclaw-mail-setup` skill 的日志系统。

## 日志文件

### 位置

```
~/.openclaw/mail/logs/{session-id}.jsonl
```

可通过 `LOG_DIR` 环境变量覆盖日志目录。

### Session ID 命名规则

```
mail-{domain}-{YYYYMMDD-HHMMSS}
```

示例: `mail-visionate.net-20260316-093000`

同一次执行（一个域名的完整 Phase 1–6 流程）共用一个 session ID。批量模式下每个域名生成独立 session。

## 日志格式

JSONL（每行一条独立 JSON 对象），方便 `jq` 查询。

### 字段定义

| 字段 | 类型 | 描述 |
|------|------|------|
| `ts` | string | ISO 8601 UTC 时间戳 |
| `level` | string | `DEBUG` / `INFO` / `WARN` / `ERROR` |
| `session` | string | Session ID |
| `phase` | string | 当前阶段: `preflight` / `login` / `navigate` / `email-status` / `create` / `result` |
| `step` | number | SKILL.md 中的步骤编号 |
| `script` | string | 产生该日志的脚本名 |
| `msg` | string | 人类可读的描述 |
| `data` | object\|null | 结构化附加数据 |

### 示例

```jsonl
{"ts":"2026-03-16T09:30:00Z","level":"INFO","session":"mail-visionate.net-20260316-093000","phase":"preflight","step":2,"script":"session_log.sh","msg":"Credential mode resolved: direct","data":{"mode":"direct"}}
{"ts":"2026-03-16T09:30:05Z","level":"INFO","session":"mail-visionate.net-20260316-093000","phase":"login","step":7,"script":"session_log.sh","msg":"Navigated to login page","data":{"url":"https://www.hostclub.org/login.php"}}
{"ts":"2026-03-16T09:30:15Z","level":"INFO","session":"mail-visionate.net-20260316-093000","phase":"login","step":8,"script":"session_log.sh","msg":"Login state: already logged in","data":{"indicator":"欢迎 Yuan Jian !"}}
{"ts":"2026-03-16T09:30:20Z","level":"ERROR","session":"mail-visionate.net-20260316-093000","phase":"login","step":9,"script":"session_log.sh","msg":"Login failed: wrong credentials","data":{"pageText":"无效的用户名或密码","attemptsRemaining":4}}
```

## Agent 调用时机

Agent 应在以下关键决策点调用 `session_log.sh`：

### Phase 1: Pre-flight

| Step | 事件 | Level |
|------|------|-------|
| 1 | 输入验证完成（query/create mode） | INFO |
| 2 | 凭证模式确定（direct/config） | INFO |
| 3 | 密码解密结果（仅 config mode） | INFO/ERROR |
| 5 | Profile 解析结果 | INFO |
| 6 | Profile 存在性检查/创建 | INFO/WARN |

### Phase 2: Login

| Step | 事件 | Level |
|------|------|-------|
| 7 | 导航到登录页 | INFO |
| 8 | 登录态检测结果 | INFO |
| 9 | 登录表单提交 | INFO |
| 9 | 登录成功/失败 | INFO/ERROR |

### Phase 3: Navigate

| Step | 事件 | Level |
|------|------|-------|
| 10 | 进入账号管理区域 | INFO |
| 11 | SSO 跳转结果 | INFO/ERROR |
| 12 | 域名搜索结果 | INFO/WARN |

### Phase 4: Email Status

| Step | 事件 | Level |
|------|------|-------|
| 14 | Titan 区块检测结果 | INFO |
| 15 | Email 状态判定 | INFO |
| 16 | Query mode 完成 | INFO |
| 17 | 标签切换到 Titan 面板 | INFO/WARN |

### Phase 5: Create

| Step | 事件 | Level |
|------|------|-------|
| 18 | Titan 面板访问结果 | INFO/WARN |
| 20 | 幂等性检查结果 | INFO |
| 21 | 邮箱创建提交 | INFO |
| 22 | 创建结果 | INFO/ERROR |

### Phase 6: Result

| Step | 事件 | Level |
|------|------|-------|
| 23 | 状态更新（config mode） | INFO |
| 24 | 最终结果返回 | INFO |

### 调用示例

```bash
# Session 开始
./scripts/session_log.sh \
  --session "mail-visionate.net-20260316-093000" \
  --domain "visionate.net" \
  --phase preflight --step 2 --level INFO \
  --msg "Credential mode resolved: direct" \
  --data '{"mode":"direct"}' \
  --json

# 登录失败
./scripts/session_log.sh \
  --session "mail-visionate.net-20260316-093000" \
  --domain "visionate.net" \
  --phase login --step 9 --level ERROR \
  --msg "Login failed: wrong credentials" \
  --data '{"pageText":"无效的用户名或密码","attemptsRemaining":4}' \
  --json

# 标签切换
./scripts/session_log.sh \
  --session "mail-visionate.net-20260316-093000" \
  --domain "visionate.net" \
  --phase email-status --step 17 --level INFO \
  --msg "Switched to Titan tab" \
  --data '{"tabId":"ABC123","url":"https://mailhostbox.titan.email/..."}' \
  --json
```

## 排查示例

```bash
# 查看某次执行的所有错误
jq 'select(.level == "ERROR")' ~/.openclaw/mail/logs/mail-visionate.net-20260316-093000.jsonl

# 查看某个 phase 的所有日志
jq 'select(.phase == "login")' ~/.openclaw/mail/logs/mail-visionate.net-20260316-093000.jsonl

# 查看最近所有 session 的最终结果
for f in ~/.openclaw/mail/logs/*.jsonl; do
  tail -1 "$f" | jq '{session: .session, phase: .phase, level: .level, msg: .msg}'
done

# 统计某个域名的所有失败
jq 'select(.level == "ERROR")' ~/.openclaw/mail/logs/mail-visionate.net-*.jsonl | jq -s 'length'

# 查看日志文件列表（按时间排序）
ls -lt ~/.openclaw/mail/logs/*.jsonl
```

## 日志级别控制

通过 `LOG_LEVEL` 环境变量控制最低记录级别：

| 值 | 记录的级别 |
|----|-----------|
| `DEBUG` | DEBUG + INFO + WARN + ERROR |
| `INFO` (默认) | INFO + WARN + ERROR |
| `WARN` | WARN + ERROR |
| `ERROR` | 仅 ERROR |

## 安全说明

- 日志中 **绝对不记录** 密码（无论是 Hostclub 登录密码还是生成的邮箱密码）
- 日志中 **不记录** `OPENCLAW_SECRET_KEY` 或任何加密密钥
- 日志中可以记录 username（用于定位账号问题），但不应包含完整的加密密文
- 日志文件权限建议设为 `600`（仅当前用户可读写）

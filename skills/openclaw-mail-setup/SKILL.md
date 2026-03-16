---
name: openclaw-mail-setup
description: "Automate enterprise email (企业邮箱) creation on Hostclub (hostclub.org) and Titan Email (mailhostbox.titan.email) via OpenClaw browser automation. Always use this skill when the user mentions: creating mailboxes on hostclub or Titan, checking Titan Email status or quota, starting a Titan free trial, batch domain email setup, navigating cp.hostclub.org, or any unattended/automated email account provisioning for domains managed through Hostclub. Also triggers for: 域名邮箱创建, hostclub 后台操作, Titan 邮箱额度检查, 批量建邮箱, 无人值守邮箱自动化. Handles login-state detection, domain routing, idempotent creation, quota checking, and structured result reporting in a headless browser profile."
---

# OpenClaw Mail Setup

## Overview

Use this skill to create enterprise email accounts on Hostclub/Titan Email through browser automation, running unattended on an OpenClaw-managed browser profile.

When referring to bundled files, resolve paths relative to this skill directory. Do not assume a user-specific checkout path.

This skill owns the decision-making layer:

- validate inputs and configuration before starting any browser work
- resolve which browser profile to use for the given account
- detect login state and decide whether to re-authenticate
- navigate the Hostclub control panel to the target domain
- check email status (enabled, trial started, quota) before attempting creation
- enforce idempotency: never create a mailbox that already exists
- call execution-only scripts for config validation, Hostclub password decryption, mailbox password generation, and status updates
- report structured results with screenshots

The browser automation steps (navigation, clicks, form fills) are performed by the agent directly using OpenClaw browser capabilities. The scripts in `scripts/` handle non-browser tasks: config file validation, AES password decryption, mailbox password generation, domain status updates, and profile management.

For the detailed Hostclub/Titan navigation flow, read `references/hostclub-flow.md`.
For account table and domain table schemas, read `references/config-schema.md`.
For OpenClaw browser CLI commands and ref 歧义处理, read `references/browser-commands.md`.

## Required Inputs

The skill supports two operation modes based on whether `mailboxName` is provided:

### Query Mode (check email status only)

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `domain` | always | Target domain name | `visionate.net` |
| `username` | direct mode only | Hostclub backend login account | `monetize@visionate.net` |
| `password` | direct mode only | Hostclub backend login password (明文) | `***` |

Query mode executes Phase 1–4 only: login, navigate to domain, check Titan Email status (enabled/trial/quota), list existing mailboxes, then return the result. No mailbox is created.

### Create Mode (create a mailbox)

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `domain` | always | Target domain name | `visionate.net` |
| `mailboxName` | always | Email prefix to create | `sales` |
| `username` | direct mode only | Hostclub backend login account | `monetize@visionate.net` |
| `password` | direct mode only | Hostclub backend login password (明文) | `***` |

Create mode executes the full Phase 1–6 workflow. The resulting mailbox will be: `mailboxName@domain` (e.g., `sales@visionate.net`).

The mailbox password is not supplied by the caller. The skill generates a strong password immediately before creation, uses it in the Titan form, and returns it once in the structured result.

### Production Config Mode

In production mode (when account/domain tables exist **and** the caller does not provide `username`/`password`), only `domain` is needed for query, or `domain` and `mailboxName` for create. The skill resolves account credentials and browser profile from the config files. The account table also provides `provider` (platform identifier for multi-platform routing) and `loginUrl` (so the login address is not hardcoded).

**注意**: 如果调用方同时提供了 `username` 和 `password`，即使配置文件存在，也使用 direct mode（调用方提供的明文凭证优先）。详见 Phase 1 Step 2 的判定逻辑。

## Workflow

### Phase 1: Pre-flight Checks

1. Validate inputs:

   - `domain` must be非空且是合法域名格式。
   - 如果调用方提供了 `username` 和 `password`，两者都必须非空（不允许只提供其中一个）。
   - 如果调用方未提供 `username`/`password`，则必须在 Step 2 中通过 config mode 解析凭证。
   - If `mailboxName` is provided, it must be a valid email local part. The skill runs in **create mode**.
   - If `mailboxName` is absent or empty, the skill runs in **query mode** (status check only, no creation).

2. Determine credential mode:

   Mode selection follows **caller-provided credentials优先** 原则，按以下顺序判定：

   - **Direct mode**（调用方提供了 `username` 和 `password`）: 直接使用调用方提供的明文凭证。**不运行** `decrypt_password.sh`，不查询 account table。即使配置文件存在也不进入 config mode。
   - **Config mode**（调用方未提供 `username`/`password`，且 account/domain tables 存在）: 运行 config check script，从 domain table 解析 `accountId`，再从 account table 解密密码。
   - **错误**: 调用方未提供凭证，且配置文件不存在或无效 → 立即停止，报告缺少凭证。

   判定伪代码：

   ```
   if caller provided username AND password:
       mode = "direct"
       # 使用调用方提供的明文 username 和 password，跳过 Step 3
   else:
       run ./scripts/check_config.sh --json
       if config valid AND domain found in domain table:
           mode = "config"
           # 从 config 解析凭证，进入 Step 3
       elif config valid AND domain NOT in domain table:
           # 配置存在但目标域名未配置
           stop with error: "Domain '<domain>' not found in domain table. Provide username and password for direct mode."
       else:
           stop with error: "No credentials provided and config files not available."
   ```

   **⚠️ 关键规则**: 调用方提供的 `password` 是**明文密码**，绝对不要对其运行 `decrypt_password.sh`。只有 config mode 下从 `accounts.json` 读取的 `passwordEncrypted` 字段才需要解密。

3. **仅在 config mode 下**解密密码:

   ```bash
   # 仅当 Step 2 判定为 config mode 时执行。Direct mode 跳过此步骤。
   ./scripts/decrypt_password.sh --account-id <account-id> --json
   ```

   This requires the `OPENCLAW_SECRET_KEY` environment variable. If the variable is missing, stop and report the error.

   **禁止**: 在 direct mode 下运行此脚本。调用方提供的密码已经是明文，解密会产生乱码导致登录失败。

4. In config mode, read `loginUrl` from the account table. In direct mode, default to `https://www.hostclub.org/login.php`.

5. Resolve the browser profile name:

   - Config mode: read `browserProfile` from the account table.
   - Direct mode: use `hostclub-001` as default. If a profile name is not provided, generate one following the naming convention: `{provider}-{sequence}` (e.g., `hostclub-001`). Profile names only allow lowercase letters, digits, and hyphens — no underscores. Sequence numbers use three digits (e.g., `001`, `002`).

6. Ensure the browser profile exists:

   ```bash
   ./scripts/manage_profile.sh --check <profile-name> --json
   ```

   If the profile does not exist, create it:

   ```bash
   ./scripts/manage_profile.sh --create <profile-name>
   ```

### Phase 2: Login

7. Launch the browser profile and navigate to the login URL (from account table `loginUrl`, or `https://www.hostclub.org/login.php` in direct mode).

8. Detect login state by checking the page content:

   - If the page contains text matching the pattern `欢迎 ` (e.g., `欢迎 Yuan Jian !`，注意 `!` 前有空格), the session is active. Skip to Phase 3.
   - If the page shows a login form (fields `txtUserName` / `txtPassword` visible), proceed with authentication.
   - If the page shows neither (e.g., redirected to homepage with only a `登录/注册` link), navigate to `https://www.hostclub.org/login.php` first, then re-check. **最多重试 3 次**。如果 3 次后仍无法识别页面状态，返回 `failed`，error: `Unable to detect login state after 3 navigation attempts`。
   - Do not rely solely on cookies; always check rendered page content.

9. If not logged in:

   - **注意**: 登录页面同时包含登录表单和注册表单，两者都有 text/password 输入框。直接使用 snapshot ref 可能匹配到错误的表单。
   - 使用 `openclaw browser evaluate --fn` 或 `openclaw browser fill --fields-file` 方式，通过字段 name 属性（`txtUserName`, `txtPassword`）精确定位登录表单字段。详见 `references/browser-commands.md` 的 "处理 Ref 歧义" 章节。
   - **不要**通过匹配"登录"文字来寻找提交按钮——页面顶部有 `登录/注册` 导航链接，匹配文字会点到导航而非表单提交。应直接提交登录表单本身（`HTMLFormElement.prototype.submit.call(form)`）或精确定位表单内的提交按钮。
   - Submit the login form.
   - Wait for the page to load.
   - **登录结果检测**: 不要仅依赖 `snapshot --labels --efficient` 判断结果（精简 snapshot 可能不包含错误横幅文本，实测已确认）。必须使用 `openclaw browser evaluate --fn "document.body.innerText"` 获取完整页面文本，然后按以下优先级检查：
     - 包含 `欢迎` → 登录成功，继续。
     - 包含 `无效的用户名或密码` / `invalid` / `login attempts remaining` → 密码错误，**立即停止**，返回 `failed`。不要重试（重复尝试会触发账号锁定）。
     - 包含 `locked` / `锁定` → 账号锁定，返回 `needs_human`。
     - 出现 CAPTCHA / 验证码 / 2FA 提示 → 返回 `needs_human`。
   - 详见 `references/hostclub-flow.md` Step 3 "登录结果检测" 章节。

### Phase 3: Navigate to Domain

10. From the Hostclub homepage (logged in),进入账号管理区域。`欢迎 <用户名> !` 文本在 `<li>` 元素内不可直接点击，其内部包含 `我的账号` 链接 (`href="javascript:void(0)"`)。必须使用 `openclaw browser evaluate --fn` 方式点击该链接。详见 `references/hostclub-flow.md` Step 4。

11. The system redirects through SSO token (`CustomerIndexServlet?redirectpage=null&userLoginId=...`) to `cp.hostclub.org`. **SSO 跳转检测**: 等待页面加载后，用 `openclaw browser evaluate --fn "location.href"` 检查 URL。如果 URL 包含 `cp.hostclub.org` 则成功；如果仍在 `hostclub.org` 则重试点击"我的账号"（最多 2 次）；3 次尝试后仍未跳转则返回 `failed`，error: `SSO redirect to cp.hostclub.org timed out`。详见 `references/hostclub-flow.md` Step 5。

12. On the `cp.hostclub.org` management center, locate the search field (placeholder: `输入域名或订单号`), enter the target domain, and navigate to the domain's order detail page. 在域名详情页上，还有一个 `跳转到域名` 搜索字段可用于域名间跳转。**注意**: 搜索可能返回多条订单（如域名管理 + Titan Email 分开列出）。优先点击包含 `Titan Email` 关键词的订单行；如果没有明确标识，点击第一条结果进入后检查是否有 Titan 区块；详见 `references/hostclub-flow.md` Step 6。

13. If the domain is not found in the account, stop and return a `failed` result with an appropriate error message.

### Phase 4: Check Email Status

14. On the domain order detail page, locate the `Titan Email (Global)` section.

15. Determine the current email status:

    - **Not enabled**: no Titan Email section, or a `Start Free Trial Now` button is visible.
    - **Enabled (trial active)**: `Business (Free Trial)` label is visible, along with `TOTAL EMAIL ACCOUNTS X/Y`.
    - **Quota reached**: `TOTAL EMAIL ACCOUNTS` shows `1/1` (or max reached).

16. **Query mode**: if `mailboxName` is not provided, collect the status information from this page (emailEnabled, trialStarted, quota) and skip to Phase 6 to return the result with status `query_ok`. Do not click any buttons or navigate further. If the Titan section shows existing mailbox info, include it in `existingMailboxes`.

17. **Create mode**: based on status:

    - If not enabled: click `Start Free Trial Now`, wait for activation（最多 30 秒，每 10 秒 snapshot 检查 `Business (Free Trial)` 和 `Go to Admin Panel` 是否出现）。超时则返回 `failed`，error: `Free trial activation timed out`。激活成功后继续进入 Titan 面板。When creation succeeds in this path, use status `trial_started` (not `created`) to distinguish first-time activation from subsequent creations.
    - If enabled and quota not reached: 点击 `Go to Admin Panel` 按钮进入 Titan 管理面板（`manage.titan.email`）。该按钮位于 `MANAGE EMAIL ACCOUNTS` 区块内，是 `<span class="wp-btn-blue-hollow">` 元素，`cursor: pointer`，**可点击**。它在 closed shadow DOM 内，常规 `document.querySelector` 无法找到，必须通过 Playwright 的 `getByText('Go to Admin Panel')` 或 OpenClaw snapshot ref 来定位。**注意**: `Login to Webmail` 链接指向 `mailhostbox.titan.email`（终端用户邮箱登录页），**不要**用它来进入管理面板。
    - If quota reached: still click `Go to Admin Panel` to enter the Titan admin panel and check the existing mailbox list. If `mailboxName@domain` is already in the list, return `already_exists`. If the target mailbox is not in the list, return `quota_reached`.

    **⚠️ 标签页切换**: `Go to Admin Panel` 会在新标签页打开 Titan 管理面板（URL: `manage.titan.email/partner/autoLogin?partnerId=...&jwt=...`，通过 JWT 自动认证，无需单独登录）。点击后必须执行以下步骤才能操作 Titan 页面：
    1. `openclaw browser tabs` — 获取标签页列表
    2. `openclaw browser focus <titan-tab-targetId>` — 切换到 Titan 标签页
    3. 在 Titan 标签页上执行 snapshot
    详见 `references/hostclub-flow.md` Step 8 和 `references/browser-commands.md` "标签页管理工作流" 章节。

### Phase 5: Idempotency Check and Mailbox Creation (Create Mode Only)

> This phase is skipped entirely in query mode.

18. Verify Titan panel access. **前提**: 已通过 Step 17 切换到 Titan 标签页。`Go to Admin Panel` 通过 JWT 自动认证，正常情况下会直接进入 `manage.titan.email/email-accounts` 管理面板。用 `openclaw browser evaluate --fn "location.href"` 确认 URL，详见 `references/hostclub-flow.md` Step 9。

    - **管理面板可达**: URL 包含 `manage.titan.email` 且显示邮箱列表页面 → 设 `adminPanelAccessible=true`，继续步骤 19。
    - **管理面板不可达（JWT 过期或异常）**: 设 `adminPanelAccessible=false`。此时无法枚举已有邮箱，依据 Phase 4 获取的配额判断：配额已满返回 `quota_reached`，配额未满可尝试创建但无法做精确幂等性检查。

19. In the Titan admin panel, check the existing mailbox list (仅当 `adminPanelAccessible=true`).

20. **Idempotency**: if `mailboxName@domain` already appears in the list, do not create it again. Return `already_exists` with `success: true`.

21. If the target mailbox does not exist and quota allows:

    - Generate a mailbox password before opening or submitting the creation form:

      ```bash
      ./scripts/generate_mailbox_password.sh --json
      ```

      The generated password must be strong and form-safe:
      - length: 16+ characters
      - include uppercase, lowercase, digit, and special character
      - avoid whitespace
      - do not log it, print it to commentary, or persist it in `domains.json`

    - Click the create new mailbox button (`新建邮箱帐户`).
    - Fill in the mailbox creation form with `mailboxName`, the generated password, and any required fields.
      - **邮箱** 输入框 (placeholder: "e.g John"): 填入 `mailboxName`。域名后缀 `@domain` 会自动显示。
      - **密码** 输入框 (placeholder: "最少8个字符。"): 填入生成的密码。
      - **密码恢复邮箱地址** (可选): 可留空。
    - Submit the form by clicking `创建新帐户` button.
    - Wait for confirmation dialog showing `创建成功！`。

22. If the creation form shows an upgrade prompt instead of a usable form, the quota is actually reached. Return `quota_reached`.

### Phase 6: Result Reporting

23. If in config mode, update the domain table:

    ```bash
    ./scripts/update_domain_status.sh \
      --domain <domain> \
      --mailbox "<mailboxName>@<domain>" \
      --status <created|already_exists|quota_reached|failed|needs_human> \
      --json
    ```

    The script also records `mailboxCreatedAt` (ISO 8601 timestamp) for successful creations.

24. Return the structured result (see Output Structure below).

25. **Tab cleanup**: 如果在 Phase 4/5 中打开了 Titan 标签页，关闭它并确认回到 Hostclub 标签页（或原始标签页）。在 batch 模式下这是切换到下一个域名的前提。详见 `references/hostclub-flow.md` Step 14。

## Error Handling

### Retryable Errors

These errors should be retried up to 3 times with increasing delays (5s, 15s, 30s):

- Page load timeout (expected element not found within timeout)
- Network interruption or request failure
- Target element briefly invisible after page transition (DOM not fully rendered)

### Terminal Errors

These errors should stop execution immediately:

- Login failure (wrong credentials)
- Target domain not found in account
- Titan panel returns unexpected page (service unavailable, maintenance)
- Retry count exhausted

### Human-Required Errors

These errors should stop execution and flag for manual intervention:

- CAPTCHA during login (image CAPTCHA, SMS verification)
- Two-factor authentication (2FA) prompt
- Account locked (requires manual unlock, different from wrong password)
- Unexpected dialog or upgrade prompt that cannot be dismissed
- SSO token expiration causing Titan panel redirect failure after retries

### Error Impact Scope (Batch Context)

When the caller runs multiple domains under the same account, errors have different blast radii:

| Error Type | Impact Scope | Handling |
|-----------|-------------|----------|
| Single domain Titan panel load failure | Current domain only | Retry then skip, continue next domain |
| Single domain quota reached | Current domain only | Record `quota_reached`, continue next domain |
| Wrong password | Entire batch | Terminate all tasks immediately |
| CAPTCHA / 2FA / Account locked | Entire batch | Terminate all, mark `needs_human` |
| Session expired mid-batch | Current and subsequent | Re-authenticate, then continue current domain |

The skill itself handles one domain per invocation. The caller is responsible for implementing the batch loop and applying these rules to decide whether to continue or abort.

## Output Structure

Every execution must return this JSON structure:

**Create mode example:**

```json
{
  "success": true,
  "mode": "create",
  "status": "created",
  "createdMailbox": "sales@visionate.net",
  "mailboxPassword": "N7!qk2@Lm4#pRs8Z",
  "emailEnabled": true,
  "trialStarted": true,
  "adminPanelAccessible": true,
  "existingMailboxes": ["sales@visionate.net"],
  "mailboxQuotaReached": true,
  "canCreateAnotherMailbox": false,

  "error": null
}
```

**Query mode example:**

```json
{
  "success": true,
  "mode": "query",
  "status": "query_ok",
  "createdMailbox": null,
  "mailboxPassword": null,
  "emailEnabled": true,
  "trialStarted": true,
  "adminPanelAccessible": false,
  "existingMailboxes": [],
  "mailboxQuotaReached": false,
  "canCreateAnotherMailbox": false,

  "error": null
}
```

`status` values:

| Status | Meaning | Mode |
|--------|---------|------|
| `query_ok` | Status check completed, no action taken | Query |
| `created` | Mailbox created successfully | Create |
| `already_exists` | Target mailbox already exists, no action taken | Create |
| `quota_reached` | Free trial quota full, cannot create | Create |
| `trial_started` | Free trial activated and mailbox created | Create |
| `failed` | Operation failed (see `error` field) | Both |
| `needs_human` | Requires manual intervention (e.g., CAPTCHA) | Both |

### Output Field Calculation Rules

- `emailEnabled`: set to `true` if the domain order page shows a `Titan Email (Global)` section with `Business (Free Trial)` or any active status. `false` if no Titan section or only a `Start Free Trial Now` button.
- `trialStarted`: `true` if the free trial has been activated (either previously or during this execution). `false` only if the domain has never had Titan Email enabled.
- `mailboxPassword`: the generated password used for creation. Set it only when a new mailbox was actually created (`status=created` or `status=trial_started`). For `query_ok`, `already_exists`, `quota_reached`, `failed`, and `needs_human`, set it to `null`.
- `adminPanelAccessible`: `true` if the skill successfully navigated to `mailhostbox.titan.email`. `false` if the panel was unreachable (SSO failure, timeout, etc.). In query mode, this is always `false` because the skill does not navigate to the Titan panel.
- `mailboxQuotaReached`: `true` if `TOTAL EMAIL ACCOUNTS` shows the maximum (e.g., `1/1`). `false` otherwise. In query mode, this is inferred from the domain order page text if visible.
- `canCreateAnotherMailbox`: `true` only when all three conditions are met: `emailEnabled=true`, `adminPanelAccessible=true`, and `mailboxQuotaReached=false`. If any condition fails, this is `false` — even when quota is not reached, an unreachable admin panel means creation is impossible. In query mode, since `adminPanelAccessible` is always `false`, this field is always `false` — the caller should rely on `emailEnabled` and `mailboxQuotaReached` to infer availability.
- `status` distinction: use `query_ok` in query mode. Use `trial_started` when the free trial was activated during this execution (Phase 4 step 17, "not enabled" branch). Use `created` when the trial was already active and the mailbox was created normally.

## Batch Dispatching (Caller's Responsibility)

The skill handles one domain per invocation. For batch processing (multiple domains under one account), the caller should follow this pattern:

### Batch Input Structure

```json
{
  "account": "acct_hostclub_001",
  "tasks": [
    { "domain": "visionate.net", "mailboxName": "sales" },
    { "domain": "abc.com", "mailboxName": "contact" },
    { "domain": "xyz.org", "mailboxName": "info" }
  ]
}
```

### Execution Order

Same-account domains run serially, reusing the browser session:

```
Login (first domain only)
  → Domain A: check status → create mailbox → record result
  → Domain B: check status → create mailbox → record result
  → Domain C: check status → create mailbox → record result
```

Login happens once. Subsequent domains reuse the same session. Switching domains does not require going back to `hostclub.org` — navigate directly on `cp.hostclub.org` using搜索字段（管理中心: `输入域名或订单号`；域名详情页: `跳转到域名`）。

### Session Expiry During Batch

Before each domain, re-check login state. If the session expired (no `欢迎` text, or redirect to login), re-authenticate and continue the current domain. Already-completed domains do not need to be re-run.

### Batch Result Structure

```json
{
  "account": "acct_hostclub_001",
  "totalDomains": 3,
  "succeeded": 2,
  "failed": 1,
  "results": [
    { "domain": "visionate.net", "mailboxName": "sales", "success": true, "status": "created", "mailboxPassword": "N7!qk2@Lm4#pRs8Z" },
    { "domain": "abc.com", "mailboxName": "contact", "success": true, "status": "already_exists", "mailboxPassword": null },
    { "domain": "xyz.org", "mailboxName": "info", "success": false, "status": "needs_human", "error": "Titan panel unreachable after 3 retries" }
  ]
}
```

### Failure Isolation

Single-domain failures do not block subsequent domains — the caller skips the failed domain and moves to the next. However, account-level failures (wrong password, CAPTCHA, account locked) terminate the entire batch because all domains share the same session. See the Error Impact Scope table above.

## Concurrency Rules

- Same account (same profile): tasks must run serially. The browser process and data directory cannot be shared across concurrent invocations.
- Different accounts: tasks can run in parallel (separate profiles and data directories).
- The skill handles one domain per invocation. Batch processing is the caller's responsibility.

Production environments should implement a profile-level lock to enforce serial execution:

- On skill start: acquire a file lock named after the profile (e.g., `/tmp/openclaw-mail-{profile}.lock`).
- If the lock is held: either queue the task or return immediately with an error indicating the profile is in use.
- On skill completion or abnormal exit: release the lock.

## Safety Rules

- **Password encryption**: passwords are stored as AES-256-CBC encrypted Base64 strings in the `passwordEncrypted` field. The encryption key comes from the `OPENCLAW_SECRET_KEY` environment variable — it must never appear in config files, code, or logs.
- **Password handling**: decrypted Hostclub passwords must be used immediately and discarded. Generated mailbox passwords must be returned once in structured output, then treated as caller-managed secrets. Never cache them in local files, log them, or include them in screenshots.
- **禁止对明文密码解密**: 调用方提供的 `password` 字段是明文，绝对不要传给 `decrypt_password.sh`。只有从 `accounts.json` 的 `passwordEncrypted` 字段读取的值才需要解密。对明文运行 AES 解密会产生乱码，导致登录失败（账号密码不匹配）。
- **Profile data isolation**: browser profile data directories must be readable only by the OpenClaw runtime user (`chmod 700`). Other users must not have read access.
- Do not silently overwrite existing browser profiles.
- Do not attempt to create a mailbox if quota is reached — check first.
- If login state detection is ambiguous, re-authenticate rather than proceeding with a potentially invalid session.

## Tab Management

`Go to Admin Panel` 按钮始终在新标签页打开 Titan Email 管理面板。执行过程中必须主动管理标签页。

### 核心规则

1. **点击 `Go to Admin Panel` 后立即切换标签页**: `openclaw browser tabs` → `openclaw browser focus <titan-tab>`
2. **操作完 Titan 面板后关闭该标签页**: `openclaw browser close <titan-tab>`（batch 模式下必需，防止标签堆积）
3. **每次 snapshot/click/type 前确认在正确的标签页**: 错误的标签页会导致元素不匹配
4. **记录 Hostclub 标签页的 targetId**: 在 Step 17 点击 `Go to Admin Panel` 之前记录，方便后续切回

### 标签页生命周期

```
Phase 1–3: [Hostclub 标签页] (唯一)
Phase 4 Step 17: [Hostclub] → 点击 Go to Admin Panel → [Hostclub, Titan(新)]
                  → tabs → focus Titan
Phase 5: [Hostclub, Titan(活跃)] — 操作 Titan 面板
Phase 6 Step 25: close Titan → [Hostclub(活跃)]
Batch 切换: 回到 Hostclub 搜索下一个域名
```

### 两个入口的区别

| 入口 | 目标 URL | 用途 |
|------|----------|------|
| `Go to Admin Panel` | `manage.titan.email/partner/autoLogin?...jwt=...` | **管理面板**（JWT 自动认证，可创建/管理邮箱） |
| `Login to Webmail` | `mailhostbox.titan.email` | **终端用户邮箱登录页**（需要邮箱密码登录，不能管理邮箱） |

**始终使用 `Go to Admin Panel` 进入 Titan 管理面板，不要使用 `Login to Webmail`。**

详见 `references/hostclub-flow.md` "Tab Management" 章节和 `references/browser-commands.md` "标签页管理工作流" 章节。

## Logging

所有执行过程通过日志系统记录关键决策点和操作结果，方便排查问题。

### Session 初始化

每次执行开始时生成一个 session ID，格式为 `mail-{domain}-{YYYYMMDD-HHMMSS}`。后续所有日志调用使用同一 session ID。

### Agent 日志记录

Agent 在关键步骤调用 `session_log.sh` 记录决策点：

```bash
./scripts/session_log.sh \
  --session <session-id> \
  --domain <domain> \
  --phase <phase-name> \
  --step <step-number> \
  --level <INFO|WARN|ERROR> \
  --msg <message> \
  [--data <json-object>] \
  --json
```

Phase 名称: `preflight` / `login` / `navigate` / `email-status` / `create` / `result`

### 必须记录的关键决策点

| Phase | Step | 事件 |
|-------|------|------|
| preflight | 2 | 凭证模式确定（direct/config） |
| login | 8 | 登录态检测结果 |
| login | 9 | 登录成功/失败 |
| navigate | 11 | SSO 跳转结果 |
| navigate | 12 | 域名搜索结果 |
| email-status | 15 | Email 状态判定 |
| email-status | 17 | 标签切换到 Titan |
| create | 18 | Titan 面板访问结果 |
| create | 21 | 邮箱创建结果 |
| result | 24 | 最终结果 |

### 脚本自动记录

所有 `scripts/` 下的脚本已集成 `log.sh`，会自动记录各自的操作结果到同一 session 日志文件。

### 日志文件

日志文件路径: `~/.openclaw/mail/logs/{session-id}.jsonl`

格式为 JSONL（每行一条 JSON 对象），可用 `jq` 查询。详见 `references/logging.md`。

## Profile Naming Convention

Profile names only allow lowercase letters, digits, and hyphens. No underscores.

Recommended format: `{provider}-{sequence}`

- `provider`: platform identifier, all lowercase (e.g., `hostclub`, `namesilo`)
- `sequence`: three-digit number starting from `001` (e.g., `001`, `002`)
- Same-platform multiple accounts are distinguished by sequence number
- The `browserProfile` field in the account table must match this convention

Examples: `hostclub-001`, `hostclub-002`, `namesilo-001`

## Resources

### scripts/

- `scripts/log.sh`: shared logging library, sourced by all other scripts (JSONL output)
- `scripts/session_log.sh`: standalone logging script for agent to call at key decision points
- `scripts/check_config.sh`: validate account table and domain table exist and are well-formed
- `scripts/decrypt_password.sh`: decrypt AES-256-CBC encrypted password using `OPENCLAW_SECRET_KEY`
- `scripts/generate_mailbox_password.sh`: generate a strong mailbox password for newly created Titan accounts
- `scripts/manage_profile.sh`: check, create, or list OpenClaw browser profiles
- `scripts/update_domain_status.sh`: update domain table after mailbox creation with result status

### references/

- `references/hostclub-flow.md`: step-by-step Hostclub/Titan navigation flow with element selectors
- `references/browser-commands.md`: OpenClaw browser CLI 命令速查和 ref 歧义处理指南
- `references/config-schema.md`: account table and domain table JSON schemas with examples
- `references/logging.md`: 日志系统使用指南、格式定义和排查示例

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
- call execution-only scripts for config validation, password decryption, and status updates
- report structured results with screenshots

The browser automation steps (navigation, clicks, form fills) are performed by the agent directly using OpenClaw browser capabilities. The scripts in `scripts/` handle non-browser tasks: config file validation, AES password decryption, domain status updates, and profile management.

For the detailed Hostclub/Titan navigation flow, read `references/hostclub-flow.md`.
For account table and domain table schemas, read `references/config-schema.md`.
For OpenClaw browser CLI commands and ref 歧义处理, read `references/browser-commands.md`.

## Required Inputs

The skill supports two operation modes based on whether `mailboxName` is provided:

### Query Mode (3 fields — check email status only)

| Field | Description | Example |
|-------|-------------|---------|
| `username` | Hostclub backend login account | `monetize@visionate.net` |
| `password` | Hostclub backend login password | `***` |
| `domain` | Target domain name | `visionate.net` |

Query mode executes Phase 1–4 only: login, navigate to domain, check Titan Email status (enabled/trial/quota), list existing mailboxes, then return the result. No mailbox is created.

### Create Mode (4 fields — create a mailbox)

| Field | Description | Example |
|-------|-------------|---------|
| `username` | Hostclub backend login account | `monetize@visionate.net` |
| `password` | Hostclub backend login password | `***` |
| `domain` | Target domain name | `visionate.net` |
| `mailboxName` | Email prefix to create | `sales` |

Create mode executes the full Phase 1–6 workflow. The resulting mailbox will be: `mailboxName@domain` (e.g., `sales@visionate.net`).

### Production Config Mode

In production mode (when account/domain tables exist), only `domain` is needed for query, or `domain` and `mailboxName` for create. The skill resolves account credentials and browser profile from the config files. The account table also provides `provider` (platform identifier for multi-platform routing) and `loginUrl` (so the login address is not hardcoded).

## Workflow

### Phase 1: Pre-flight Checks

1. Validate inputs:

   - `username`, `password`, `domain` must be non-empty. `domain` must look like a valid domain.
   - If `mailboxName` is provided, it must be a valid email local part. The skill runs in **create mode**.
   - If `mailboxName` is absent or empty, the skill runs in **query mode** (status check only, no creation).

2. Determine credential mode:

   - **Config mode** (account/domain tables exist): run the config check script, resolve account from domain mapping, decrypt password.
   - **Direct mode** (no config tables): use the raw inputs directly.

   ```bash
   # Check if config files exist and are valid
   ./scripts/check_config.sh --json
   ```

3. In config mode, decrypt the password:

   ```bash
   ./scripts/decrypt_password.sh --account-id <account-id> --json
   ```

   This requires the `OPENCLAW_SECRET_KEY` environment variable. If the variable is missing, stop and report the error.

4. In config mode, read `loginUrl` from the account table. In direct mode, default to `https://www.hostclub.org/`.

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

7. Launch the browser profile and navigate to the login URL (from account table `loginUrl`, or `https://www.hostclub.org/` in direct mode).

8. Detect login state by checking the page content:

   - If the page contains text matching the pattern `欢迎 ` (e.g., `欢迎 Yuan Jian !`，注意 `!` 前有空格), the session is active. Skip to Phase 3.
   - If the page shows a login form or the URL contains `login`, proceed with authentication.
   - Do not rely solely on cookies; always check rendered page content.

9. If not logged in:

   - **注意**: 登录页面同时包含登录表单和注册表单，两者都有 text/password 输入框。直接使用 snapshot ref 可能匹配到错误的表单。
   - 使用 `openclaw browser evaluate --fn` 或 `openclaw browser fill --fields-file` 方式，通过字段 name 属性（`txtUserName`, `txtPassword`）精确定位登录表单字段。详见 `references/browser-commands.md` 的 "处理 Ref 歧义" 章节。
   - **不要**通过匹配"登录"文字来寻找提交按钮——页面顶部有 `登录/注册` 导航链接，匹配文字会点到导航而非表单提交。应直接提交登录表单本身（`HTMLFormElement.prototype.submit.call(form)`）或精确定位表单内的提交按钮。
   - Submit the login form.
   - Wait for the page to load and verify login succeeded (look for `欢迎` text).
   - If login fails due to wrong credentials, stop immediately and return a `failed` result.
   - If login fails due to account locked, stop and return a `needs_human` result (requires manual unlock).
   - If a CAPTCHA or 2FA prompt appears, stop and return a `needs_human` result.

### Phase 3: Navigate to Domain

10. From the Hostclub homepage (logged in),进入账号管理区域。`欢迎 <用户名> !` 文本在 `<li>` 元素内不可直接点击，其内部包含 `我的账号` 链接 (`href="javascript:void(0)"`)。必须使用 `openclaw browser evaluate --fn` 方式点击该链接。详见 `references/hostclub-flow.md` Step 4。

11. The system redirects through SSO token (`CustomerIndexServlet?redirectpage=null&userLoginId=...`) to `cp.hostclub.org`.

12. On the `cp.hostclub.org` management center, locate the search field (placeholder: `输入域名或订单号`), enter the target domain, and navigate to the domain's order detail page. 在域名详情页上，还有一个 `跳转到域名` 搜索字段可用于域名间跳转。

13. If the domain is not found in the account, stop and return a `failed` result with an appropriate error message.

### Phase 4: Check Email Status

14. On the domain order detail page, locate the `Titan Email (Global)` section.

15. Determine the current email status:

    - **Not enabled**: no Titan Email section, or a `Start Free Trial Now` button is visible.
    - **Enabled (trial active)**: `Business (Free Trial)` label is visible, along with `TOTAL EMAIL ACCOUNTS X/Y`.
    - **Quota reached**: `TOTAL EMAIL ACCOUNTS` shows `1/1` (or max reached).

16. **Query mode**: if `mailboxName` is not provided, collect the status information from this page (emailEnabled, trialStarted, quota) and skip to Phase 6 to return the result with status `query_ok`. Do not click any buttons or navigate further. If the Titan section shows existing mailbox info, include it in `existingMailboxes`.

17. **Create mode**: based on status:

    - If not enabled: click `Start Free Trial Now`, wait for activation, then proceed to the Titan admin panel. When creation succeeds in this path, use status `trial_started` (not `created`) to distinguish first-time activation from subsequent creations.
    - If enabled and quota not reached: click `Login to Webmail` 链接进入 Titan 管理面板（`mailhostbox.titan.email`）。**注意**: `Go to Admin Panel` 是纯文本标签，不可点击/不可交互，不要尝试点击它。
    - If quota reached: still click `Login to Webmail` to enter the Titan panel and check the existing mailbox list. If `mailboxName@domain` is already in the list, return `already_exists`. If the target mailbox is not in the list, return `quota_reached`.

### Phase 5: Idempotency Check and Mailbox Creation (Create Mode Only)

> This phase is skipped entirely in query mode.

18. Verify Titan panel access. `Login to Webmail` 不一定直接进入管理面板，可能落在 `mailhostbox.titan.email/login/` 终端用户登录页。详见 `references/hostclub-flow.md` Step 9。

    - **管理面板可达**: URL 显示邮箱列表页面 → 设 `adminPanelAccessible=true`，继续步骤 19。
    - **管理面板不可达（登录页）**: 设 `adminPanelAccessible=false`。此时无法枚举已有邮箱，依据 Phase 4 获取的配额判断：配额已满返回 `quota_reached`，配额未满可尝试创建但无法做精确幂等性检查。

19. In the Titan admin panel, check the existing mailbox list (仅当 `adminPanelAccessible=true`).

20. **Idempotency**: if `mailboxName@domain` already appears in the list, do not create it again. Return `already_exists` with `success: true`.

21. If the target mailbox does not exist and quota allows:

    - Click the create new mailbox button (`新建邮箱帐户`).
    - Fill in the mailbox creation form with `mailboxName` and any required fields.
    - Submit the form.
    - Wait for confirmation that creation succeeded.

22. If the creation form shows an upgrade prompt instead of a usable form, the quota is actually reached. Return `quota_reached`.

### Phase 6: Result Reporting

21. Take a screenshot of the final state for evidence.

22. If in config mode, update the domain table:

    ```bash
    ./scripts/update_domain_status.sh \
      --domain <domain> \
      --mailbox "<mailboxName>@<domain>" \
      --status <created|already_exists|quota_reached|failed|needs_human> \
      --json
    ```

    The script also records `mailboxCreatedAt` (ISO 8601 timestamp) for successful creations.

23. Return the structured result (see Output Structure below).

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
  "emailEnabled": true,
  "trialStarted": true,
  "adminPanelAccessible": true,
  "existingMailboxes": ["sales@visionate.net"],
  "mailboxQuotaReached": true,
  "canCreateAnotherMailbox": false,
  "screenshotPath": "/path/to/screenshot.png",
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
  "emailEnabled": true,
  "trialStarted": true,
  "adminPanelAccessible": false,
  "existingMailboxes": [],
  "mailboxQuotaReached": false,
  "canCreateAnotherMailbox": false,
  "screenshotPath": "/path/to/screenshot.png",
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
    { "domain": "visionate.net", "mailboxName": "sales", "success": true, "status": "created" },
    { "domain": "abc.com", "mailboxName": "contact", "success": true, "status": "already_exists" },
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
- **Password handling**: decrypted passwords must be used immediately and discarded. Never cache, log, or include them in screenshots.
- **Profile data isolation**: browser profile data directories must be readable only by the OpenClaw runtime user (`chmod 700`). Other users must not have read access.
- Do not silently overwrite existing browser profiles.
- Always take a screenshot before returning results, for audit trail.
- Do not attempt to create a mailbox if quota is reached — check first.
- If login state detection is ambiguous, re-authenticate rather than proceeding with a potentially invalid session.

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

- `scripts/check_config.sh`: validate account table and domain table exist and are well-formed
- `scripts/decrypt_password.sh`: decrypt AES-256-CBC encrypted password using `OPENCLAW_SECRET_KEY`
- `scripts/manage_profile.sh`: check, create, or list OpenClaw browser profiles
- `scripts/update_domain_status.sh`: update domain table after mailbox creation with result status

### references/

- `references/hostclub-flow.md`: step-by-step Hostclub/Titan navigation flow with element selectors
- `references/browser-commands.md`: OpenClaw browser CLI 命令速查和 ref 歧义处理指南
- `references/config-schema.md`: account table and domain table JSON schemas with examples

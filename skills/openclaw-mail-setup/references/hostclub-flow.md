# Hostclub / Titan Email Navigation Flow

This document describes the exact browser navigation path for creating an email account through the Hostclub control panel and Titan Email admin panel.

> **Important**: This flow is based on真实环境浏览器自动化测试验证（2026-03）。所有元素名、字段名、URL 路径均来自实际页面 snapshot。

## Table of Contents

- [Login Flow](#login-flow)
- [Navigate to Domain](#navigate-to-domain)
- [Email Status Detection](#email-status-detection)
- [Titan Admin Panel](#titan-admin-panel)
- [Mailbox Creation](#mailbox-creation)
- [Domain Switching (Batch)](#domain-switching-batch)

## Login Flow

### Step 1: Open Hostclub

Navigate to `https://www.hostclub.org/`.

```bash
openclaw browser navigate "https://www.hostclub.org/" --browser-profile <profile>
```

### Step 2: Detect Login State

Take a snapshot and check the page content:

```bash
openclaw browser snapshot --browser-profile <profile> --labels --efficient
```

- **Logged in**: page contains text matching pattern `欢迎 ` (e.g., `欢迎 Yuan Jian !`)。注意 `!` 前有空格。
- **Not logged in**: page shows a login form, or URL contains `login`.

### Step 3: Login (if needed)

**重要**: 登录页面同时包含登录表单和注册表单，两者都有 text/password 类型的输入框。直接用 snapshot ref 匹配可能命中多个元素（ref 歧义）。

实际字段名：
- 用户名: `txtUserName` (type=text)
- 密码: `txtPassword` (type=password)

**推荐方式**: 使用 `openclaw browser fill` 通过字段 name 精确填写，或使用 `evaluate --fn` 方式：

```bash
# 方式 1: 使用 evaluate 精确定位字段
openclaw browser evaluate --fn "document.querySelector('input[name=txtUserName]').value = 'user@example.com'" --browser-profile <profile>
openclaw browser evaluate --fn "document.querySelector('input[name=txtPassword]').value = 'password123'" --browser-profile <profile>
openclaw browser evaluate --fn "document.querySelector('input[name=txtUserName]').form.submit()" --browser-profile <profile>

# 方式 2: 使用 fill --fields-file (推荐)
# 创建 fields JSON 文件: [{"selector": "input[name=txtUserName]", "value": "..."}, {"selector": "input[name=txtPassword]", "value": "..."}]
openclaw browser fill --fields-file /tmp/login-fields.json --browser-profile <profile>
```

**不要**直接使用 `openclaw browser type <ref>` 来填写登录表单，因为 snapshot 中 text 和 password 类型的 ref 可能匹配到注册表单的同类型输入框。

**不要**通过匹配"登录"文字来寻找提交按钮。页面顶部有 `登录/注册` 导航链接，模糊匹配会点到导航而非表单提交按钮。提交表单应使用 `HTMLFormElement.prototype.submit.call(form)` 或精确定位表单内的 `input[type=submit]`。

登录后等待页面刷新，验证 `欢迎` 文本出现：

```bash
openclaw browser snapshot --browser-profile <profile> --labels --efficient
# 检查输出中是否包含 "欢迎"
```

Watch for:
- CAPTCHA challenges (image, slider, etc.) — cannot be automated, return `needs_human`.
- 2FA prompts — cannot be automated, return `needs_human`.
- "Account locked" or "Too many attempts" messages — return `failed`.

## Navigate to Domain

### Step 4: Enter Account Area

登录后页面右上角有 `欢迎 <用户名> !` 文本。该文本在 `<li>` 元素内，不可直接点击。其内部包含一个 `我的账号` 链接 (`href="javascript:void(0)"`)。

**必须使用 JS evaluate 方式点击**：

```bash
# 点击 "我的账号" 链接进入账号管理
openclaw browser evaluate --fn "document.querySelector('a[href=\"javascript:void(0)\"]').click()" --browser-profile <profile>
# 或者更精确地定位：
openclaw browser evaluate --fn "Array.from(document.querySelectorAll('a')).find(a => a.textContent.includes('我的账号')).click()" --browser-profile <profile>
```

不要尝试点击 `欢迎 * !` 文本本身，它不是可交互元素。

### Step 5: Redirect to Control Panel

系统通过 SSO token 跳转到 `cp.hostclub.org`。实际跳转路径：

```
hostclub.org → CustomerIndexServlet?redirectpage=null&userLoginId=...&... → cp.hostclub.org
```

**注意**: 跳转不是通过 `content.php?action=cp_login`，而是通过 `CustomerIndexServlet` 带 SSO token 的 URL。

等待 `cp.hostclub.org` 管理中心完全加载：

```bash
openclaw browser snapshot --browser-profile <profile> --labels --efficient
# 确认 URL 包含 cp.hostclub.org
```

### Step 6: Search for Domain

管理中心页面有搜索字段：

- **管理中心首页**: 搜索字段 placeholder 为 `输入域名或订单号`
- **域名详情页**: 有另一个搜索字段 `跳转到域名`

```bash
# 在管理中心搜索域名
# 先 snapshot 找到搜索框的 ref
openclaw browser snapshot --browser-profile <profile> --labels --efficient
# 在搜索框中输入域名并提交
openclaw browser type <search-ref> "example.com" --browser-profile <profile> --submit
```

如果域名未找到，搜索可能返回空结果或错误信息。检查并报告失败。

## Email Status Detection

### Step 7: Check Titan Email Section

On the domain order detail page, look for the `Titan Email (Global)` section.

```bash
openclaw browser snapshot --browser-profile <profile> --labels --efficient
```

Three possible states:

#### State A: Not Enabled

- No `Titan Email (Global)` section visible, OR
- A `Start Free Trial Now` button is present.

**Action**: Click `Start Free Trial Now` to activate the free trial.

```bash
openclaw browser click <start-trial-ref> --browser-profile <profile>
```

#### State B: Enabled (Trial Active)

实际页面元素：
- `Business (Free Trial)` 按钮（可点击）
- `1/1 Account(s)` 按钮（显示当前配额，可点击）
- `TOTAL EMAIL ACCOUNTS 1/1` 纯文本
- `buy more` 按钮
- `Login to Webmail` 链接（`https://mailhostbox.titan.email`）
- `Delete Accounts` 按钮

**注意**: `Go to Admin Panel` 在页面上是**纯文本标签 (text)**，没有 ref，不可点击、不可交互。不要尝试点击它。

#### State C: Quota判断

- 检查 `TOTAL EMAIL ACCOUNTS` 后的数字（如 `0/1` 表示有空位，`1/1` 表示已满）
- 也可以看 `Account(s)` 按钮上的数字

### Step 8: Enter Titan Panel

**实际入口**: 点击 `Login to Webmail` 链接，跳转到 `https://mailhostbox.titan.email`。

```bash
# 找到 "Login to Webmail" 链接的 ref
openclaw browser snapshot --browser-profile <profile> --labels --efficient
openclaw browser click <login-to-webmail-ref> --browser-profile <profile>
```

**不要**尝试点击 `Go to Admin Panel`（它是纯文本，不可交互）。

## Titan Admin Panel

### Step 9: Access Titan Panel

点击 `Login to Webmail` 后，浏览器跳转到 `mailhostbox.titan.email`（不是 `manage.titan.email`）。

**重要**: `Login to Webmail` 不一定直接进入管理员邮箱列表页。实测中存在两种结果：

- **情况 A — 直接进入管理面板**: URL 类似 `mailhostbox.titan.email/mail/...` 或直接显示 email accounts 列表。此时可以正常读取已有邮箱和执行创建操作。
- **情况 B — 落在终端用户登录页**: URL 为 `mailhostbox.titan.email/login/` 或类似登录页面。此时无法枚举已有邮箱地址。

```bash
openclaw browser snapshot --browser-profile <profile> --labels --efficient
# 检查 URL 和页面内容：
# - 如果看到邮箱列表 → 情况 A，继续 Step 10
# - 如果看到登录表单 → 情况 B，见下方降级处理
```

**情况 B 降级处理**:

当落在 Titan 登录页时，skill 无法获取具体的邮箱地址列表。处理策略：
1. 将 `adminPanelAccessible` 设为 `false`
2. 依据 Phase 4 从域名详情页获取的配额信息（如 `TOTAL EMAIL ACCOUNTS 1/1`）判断状态
3. 如果配额已满（`1/1`），返回 `quota_reached`（已知有 1 个邮箱但无法确认具体地址）
4. 如果配额未满，仍可尝试创建（Step 12），但无法做精确的幂等性检查

### Step 10: Read Existing Mailboxes

> 此步骤仅在情况 A（成功进入管理面板）时执行。

On the email accounts page, read the list of existing mailbox accounts. Note:

- The email address displayed (e.g., `contact@wavelengthpulsmk.com`).
- The total count indicator (e.g., `1/1`).

## Mailbox Creation

### Step 11: Idempotency Check

Before creating, compare `mailboxName@domain` against the existing mailbox list.

- If found: return `already_exists` immediately. No further action needed.
- If not found and quota available: proceed to creation.
- If not found and quota reached: return `quota_reached`.

### Step 12: Create Mailbox

1. Click `新建邮箱帐户` (Create New Email Account) button.
2. If an upgrade prompt appears instead of a creation form, quota is reached. Return `quota_reached`.
3. Fill in the creation form:
   - Email prefix: `mailboxName`
   - Password: generate or use a provided password (implementation-dependent)
   - Any other required fields
4. Submit the form.
5. Wait for confirmation.

### Step 13: Verify Creation

After form submission:

1. Check for a success message or confirmation dialog.
2. Verify the new mailbox appears in the email accounts list.
3. Take a screenshot for evidence:

```bash
openclaw browser snapshot --browser-profile <profile> --labels --efficient
```

## Domain Switching (Batch)

When processing multiple domains under the same account, switch domains without logging out:

1. From the current domain's order detail page on `cp.hostclub.org`.
2. 使用域名详情页上的 `跳转到域名` 搜索字段，或返回管理中心使用 `输入域名或订单号` 搜索字段。
3. Enter the next domain name and submit.
4. Navigate to the new domain's order detail page.
5. Continue from [Email Status Detection](#email-status-detection).

```bash
# 在域名详情页直接跳转到另一个域名
openclaw browser snapshot --browser-profile <profile> --labels --efficient
# 找到 "跳转到域名" 搜索框的 ref
openclaw browser type <jump-to-domain-ref> "next-domain.com" --browser-profile <profile> --submit
```

Before each domain switch, re-verify login state. If the session expired (no `欢迎` text visible, or redirect to login page), re-authenticate before continuing.

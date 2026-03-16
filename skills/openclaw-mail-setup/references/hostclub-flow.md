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
- [Tab Management](#tab-management)

## Login Flow

### Step 1: Open Hostclub Login Page

Navigate to `https://www.hostclub.org/login.php`（直接打开登录页，而非首页。首页未登录时只显示 `登录/注册` 链接，没有登录表单，会导致登录态检测失准）。

```bash
openclaw browser navigate "https://www.hostclub.org/login.php" --browser-profile <profile>
```

### Step 2: Detect Login State

Take a snapshot and check the page content:

```bash
openclaw browser snapshot --browser-profile <profile> --labels --efficient
```

- **Logged in**: page contains text matching pattern `欢迎 ` (e.g., `欢迎 Yuan Jian !`)。注意 `!` 前有空格。已登录用户即使打开 login.php 也会看到 `欢迎` 文本。
- **Not logged in**: page shows a login form（fields `txtUserName` / `txtPassword` visible）。
- **Neither**（既没有 `欢迎` 也没有登录表单，如被重定向到首页）: 重新导航到 `https://www.hostclub.org/login.php`，然后再次检查。**最多重试 3 次**。如果 3 次后仍无法识别页面状态，返回 `failed`，error: `Unable to detect login state after 3 navigation attempts`。

### Step 3: Login (if needed)

**重要**: 登录页面同时包含登录表单和注册表单，两者都有 text/password 类型的输入框。直接用 snapshot ref 匹配可能命中多个元素（ref 歧义）。

实际字段名：
- 用户名: `txtUserName` (type=text)
- 密码: `txtPassword` (type=password)

**推荐方式**: 使用 `openclaw browser fill` 通过字段 name 精确填写，或使用 `evaluate --fn` 方式：

```bash
# 方式 1: 使用 evaluate 精确定位字段并提交
openclaw browser evaluate --fn "document.querySelector('input[name=txtUserName]').value = 'user@example.com'" --browser-profile <profile>
openclaw browser evaluate --fn "document.querySelector('input[name=txtPassword]').value = 'password123'" --browser-profile <profile>
# 提交表单 — 不要用 form.submit()，因为表单内有 name="submit" 的按钮会覆盖该方法
openclaw browser evaluate --fn "HTMLFormElement.prototype.submit.call(document.querySelector('input[name=txtUserName]').form)" --browser-profile <profile>

# 方式 2: 使用 fill --fields-file (推荐)
# 创建 fields JSON 文件: [{"selector": "input[name=txtUserName]", "value": "..."}, {"selector": "input[name=txtPassword]", "value": "..."}]
openclaw browser fill --fields-file /tmp/login-fields.json --browser-profile <profile>
```

**不要**直接使用 `openclaw browser type <ref>` 来填写登录表单，因为 snapshot 中 text 和 password 类型的 ref 可能匹配到注册表单的同类型输入框。

**不要**通过匹配"登录"文字来寻找提交按钮。页面顶部有 `登录/注册` 导航链接，模糊匹配会点到导航而非表单提交按钮。提交表单应使用 `HTMLFormElement.prototype.submit.call(form)` 或精确定位表单内的 `input[type=submit]`。

#### 登录结果检测

登录表单提交后，**不要仅依赖 `snapshot --labels --efficient`** 判断结果。精简 snapshot 可能不包含错误横幅文本（实测确认）。

**检测流程**:

```bash
# 1. 等待页面加载（最多 5 秒）
openclaw browser wait --time 5000 --browser-profile <profile>

# 2. 用 evaluate 获取完整页面文本进行错误检测
openclaw browser evaluate --fn "document.body.innerText" --browser-profile <profile>
```

**按以下顺序检查返回的页面文本**:

| 匹配文本 | 判定 | 操作 |
|----------|------|------|
| `欢迎 ` | 登录成功 | 继续 Step 4 |
| `无效的用户名或密码` / `invalid` | 密码错误 | **立即停止**，返回 `failed` |
| `login attempts remaining` | 密码错误（含剩余次数警告） | **立即停止**，返回 `failed` |
| `locked` / `锁定` | 账号锁定 | 返回 `needs_human` |
| CAPTCHA 相关元素 / 验证码 | 需要人工验证 | 返回 `needs_human` |
| 2FA / 短信验证 / 二次验证 | 需要人工验证 | 返回 `needs_human` |

**绝对不要**在密码错误后重试登录 — 重复尝试会触发账号锁定（6 次失败后临时锁定）。

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

**SSO 跳转检测**（最多等待 15 秒，重试 2 次）：

```bash
# 1. 等待页面加载
openclaw browser wait --time 5000 --browser-profile <profile>

# 2. 检查当前 URL
openclaw browser evaluate --fn "location.href" --browser-profile <profile>
```

| URL 检查结果 | 判定 | 操作 |
|-------------|------|------|
| 包含 `cp.hostclub.org` | SSO 成功 | 继续 Step 6 |
| 仍是 `hostclub.org` | 跳转未发生 | 重试点击"我的账号"（最多 2 次） |
| 其他 URL | 异常 | 返回 `failed`，error: `SSO redirect failed` |
| 3 次尝试后仍未到 cp.hostclub.org | 超时 | 返回 `failed`，error: `SSO redirect to cp.hostclub.org timed out` |

确认 URL 正确后取 snapshot：

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

**多条搜索结果处理**:

搜索可能返回多条订单（如域名管理 + Titan Email 分开列出）。处理策略：

1. 优先点击包含 `Titan Email` 关键词的订单行
2. 如果没有明确的 Titan 标识，点击第一条结果进入详情页
3. 在详情页检查是否有 `Titan Email (Global)` 区块
4. 如果当前详情页没有 Titan 区块，返回搜索结果尝试下一条

如果所有结果都不包含 Titan 区块，或搜索返回"无法找到任何订单"，返回 `failed`，error: `Domain not found in account`。

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

**Action (create mode only)**: Click `Start Free Trial Now` to activate the free trial.

```bash
openclaw browser click <start-trial-ref> --browser-profile <profile>
```

**激活等待条件**:

```bash
# 等待页面刷新（最多 30 秒）
openclaw browser wait --time 10000 --browser-profile <profile>
openclaw browser snapshot --browser-profile <profile> --labels --efficient
```

验证激活成功的标志：
- `Business (Free Trial)` 文本出现
- `TOTAL EMAIL ACCOUNTS` 文本出现
- `Login to Webmail` 链接出现

如果 30 秒内未看到上述标志，再次 snapshot 检查。最多等待 3 次（共 30 秒）。仍未激活则返回 `failed`，error: `Free trial activation timed out`。

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

**⚠️ 重要: `Login to Webmail` 会在新标签页打开。必须切换标签页才能操作 Titan 面板。**

```bash
# 1. 记录当前标签页列表（保存 Hostclub 标签页的 targetId）
openclaw browser tabs --browser-profile <profile>

# 2. 点击 Login to Webmail
openclaw browser snapshot --browser-profile <profile> --labels --efficient
openclaw browser click <login-to-webmail-ref> --browser-profile <profile>

# 3. 等待新标签页打开
openclaw browser wait --time 3000 --browser-profile <profile>

# 4. 获取更新后的标签页列表
openclaw browser tabs --browser-profile <profile>
# 新标签页应该包含 mailhostbox.titan.email

# 5. 切换到 Titan 标签页
openclaw browser focus <titan-tab-targetId> --browser-profile <profile>
```

**不要**尝试点击 `Go to Admin Panel`（它是纯文本，不可交互）。

## Titan Admin Panel

### Step 9: Access Titan Panel

> **前提**: 已通过 Step 8 切换到 Titan 标签页。

在 Titan 标签页上执行 snapshot：

```bash
openclaw browser snapshot --browser-profile <profile> --labels --efficient
```

点击 `Login to Webmail` 后，浏览器跳转到 `mailhostbox.titan.email`（不是 `manage.titan.email`）。

**重要**: `Login to Webmail` 不一定直接进入管理员邮箱列表页。实测中存在两种结果：

- **情况 A — 直接进入管理面板**: URL 类似 `mailhostbox.titan.email/mail/...` 或直接显示 email accounts 列表。此时可以正常读取已有邮箱和执行创建操作。
- **情况 B — 落在终端用户登录页**: URL 为 `mailhostbox.titan.email/login/` 或类似登录页面。此时无法枚举已有邮箱地址。

```bash
# 检查 URL 和页面内容（确认已在 Titan 标签页上）：
openclaw browser evaluate --fn "location.href" --browser-profile <profile>
openclaw browser snapshot --browser-profile <profile> --labels --efficient
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
3. Before filling the form, generate a mailbox password:

```bash
./scripts/generate_mailbox_password.sh --json
```

4. Fill in the creation form:
   - Email prefix: `mailboxName`
   - Password: use the generated password
   - Any other required fields
5. Submit the form.
6. Wait for confirmation.

### Step 13: Verify Creation

After form submission:

1. Check for a success message or confirmation dialog.
2. Verify the new mailbox appears in the email accounts list.
3. Return the generated password in the structured result for the caller to store securely. Do not write it to `domains.json` and do not expose it in logs.

## Domain Switching (Batch)

When processing multiple domains under the same account, switch domains without logging out:

### Step 14: Clean Up Titan Tab

在切换到下一个域名之前，**必须先关闭当前域名的 Titan 标签页**（如果有），然后回到 Hostclub 标签页：

```bash
# 1. 获取标签页列表
openclaw browser tabs --browser-profile <profile>

# 2. 如果存在 Titan 标签页（URL 包含 mailhostbox.titan.email），关闭它
openclaw browser close <titan-tab-targetId> --browser-profile <profile>

# 3. 确认当前活跃标签页是 Hostclub（cp.hostclub.org）
openclaw browser tabs --browser-profile <profile>
# 如果不是，使用 focus 切回
openclaw browser focus <hostclub-tab-targetId> --browser-profile <profile>
```

### Step 15: Switch Domain

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

## Tab Management

整个 skill 执行过程中需要管理的标签页：

| 阶段 | 标签页 | 说明 |
|------|--------|------|
| Phase 2–3 | Hostclub 主标签页 | 登录、导航、域名搜索 |
| Phase 4 Step 8 | Titan 新标签页 | `Login to Webmail` 打开 |
| Phase 5 | Titan 标签页 | 邮箱列表、创建表单 |
| Phase 6 | 回到 Hostclub 标签页 | 域名切换（batch） |

**关键规则**:

1. **`Login to Webmail` 总是在新标签页打开** — 点击后必须 `tabs` → `focus` 切换
2. **操作完 Titan 面板后需要关闭该标签页** — 尤其在 batch 模式下，防止标签堆积
3. **每次 snapshot/click/type 前确认在正确的标签页上** — 错误的标签页会导致 snapshot 内容不匹配
4. **Hostclub 标签页的 targetId 在 Step 8 之前记录** — 方便后续切回

标签切换命令速查见 `references/browser-commands.md` 的 "标签页管理工作流" 章节。

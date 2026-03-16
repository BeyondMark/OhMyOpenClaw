# Hostclub / Titan Email Navigation Flow

This document describes the exact browser navigation path for creating an email account through the Hostclub control panel and Titan Email admin panel.

> **Important**: This flow is based on真实环境浏览器自动化测试验证（2026-03）。所有元素名、字段名、URL 路径均来自实际页面 snapshot。
>
> **浏览器引擎**: 所有浏览器操作通过 Playwright MCP 工具执行。详见 `references/browser-commands.md`。

## Table of Contents

- [Profile StorageState](#profile-storagestate)
- [Login Flow](#login-flow)
- [Navigate to Domain](#navigate-to-domain)
- [Email Status Detection](#email-status-detection)
- [Titan Admin Panel](#titan-admin-panel)
- [Mailbox Creation](#mailbox-creation)
- [Domain Switching (Batch)](#domain-switching-batch)
- [Tab Management](#tab-management)

## Profile StorageState

### 加载已保存的登录态

在导航到登录页之前，先尝试加载 profile 中保存的 storageState（cookie/localStorage）。

> **注意**: `browser_run_code` 中 `require('fs')` 不可用。需要分两步操作。

**步骤 A**: 用 bash 提取 cookie 数组:

```bash
cat <profile-path>/storage-state.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d['cookies']))"
```

**步骤 B**: 将提取的 cookie 数组传入 `browser_run_code`:

```
工具: browser_run_code
code: |
  async (page) => {
    const cookies = <步骤A输出的cookie数组>;
    await page.context().addCookies(cookies);
    return { loaded: true, cookieCount: cookies.length };
  }
```

`<profile-path>` 替换为 `~/.openclaw/mail/profiles/{profile-name}`（从 `manage_profile.sh --check` 输出中获取）。如果 `hasStorageState: false`，跳过加载步骤。

### 保存登录态

登录成功后保存 storageState，供下次会话复用:

```
工具: browser_run_code
code: |
  async (page) => {
    const state = await page.context().storageState({ path: '<profile-path>/storage-state.json' });
    return { saved: true, cookieCount: state.cookies.length };
  }
```

## Login Flow

### Step 1: Open Hostclub Login Page

导航到 `https://www.hostclub.org/login.php`（直接打开登录页，而非首页。首页未登录时只显示 `登录/注册` 链接，没有登录表单，会导致登录态检测失准）。

```
工具: browser_navigate
参数: { url: "https://www.hostclub.org/login.php" }
```

### Step 2: Detect Login State

取 snapshot 检查页面内容:

```
工具: browser_snapshot
参数: {}
```

- **Logged in**: snapshot 中包含 `欢迎` 文本（如 `欢迎 Yuan Jian !`）。注意 `!` 前有空格。已登录用户即使打开 login.php 也会看到 `欢迎` 文本。
- **Not logged in**: snapshot 中出现 `请先登录再下单！` 标题，以及邮件地址/密码输入框（显示为 `textbox` 和 `textbox "密码 *"`）和 `登录` 按钮。注意: Playwright snapshot 不会显示 HTML name 属性（如 `txtUserName`），但填写表单时需要通过 `browser_evaluate` 使用这些 name 属性精确定位字段。
- **Neither**（既没有 `欢迎` 也没有登录表单，如被重定向到首页）: 重新导航到登录页，然后再次检查。**最多重试 3 次**。如果 3 次后仍无法识别页面状态，返回 `failed`，error: `Unable to detect login state after 3 navigation attempts`。

### Step 3: Login (if needed)

**必须使用 `browser_run_code`** 一次性完成登录表单填写和提交。登录页面 HTML 中同时存在登录表单（2 个可见字段）和隐藏的注册表单（20 个隐藏字段）。使用 snapshot ref 或 `browser_fill_form` 可能匹配到隐藏的注册字段，导致登录失败。

```
工具: browser_run_code
code: |
  async (page) => {
    await page.locator('input[name=txtUserName]').fill('<username>');
    await page.locator('input[name=txtPassword]').fill('<password>');
    await page.locator('input[name=txtUserName]').evaluate(el =>
      HTMLFormElement.prototype.submit.call(el.form)
    );
  }
```

- `input[name=txtUserName]` — 登录表单邮箱字段（唯一）
- `input[name=txtPassword]` — 登录表单密码字段（唯一）
- `HTMLFormElement.prototype.submit.call(el.form)` — 绕过表单内 `name="submit"` 按钮对 `form.submit()` 的覆盖

**不要**使用以下方式:
- `browser_fill_form` — 可能匹配隐藏注册字段
- `browser_type` + snapshot ref — ref 可能歧义
- 匹配"登录"文字找按钮 — 页面顶部有 `登录/注册` 导航链接会被误匹配

#### 登录结果检测

登录表单提交后，**不要仅依赖 `browser_snapshot`** 判断结果。精简 snapshot 可能不包含错误横幅文本。

**检测流程**:

```
# 1. 等待页面加载（5 秒）
工具: browser_wait_for
参数: { time: 5 }

# 2. 用 evaluate 获取完整页面文本进行错误检测
工具: browser_evaluate
参数: { function: "() => document.body.innerText" }
```

**按以下顺序检查返回的页面文本**:

| 匹配文本 | 判定 | 操作 |
|----------|------|------|
| `欢迎 ` | 登录成功 | 保存 storageState，继续 Step 4 |
| `无效的用户名或密码` / `invalid` | 密码错误 | **立即停止**，返回 `failed` |
| `login attempts remaining` | 密码错误（含剩余次数警告） | **立即停止**，返回 `failed` |
| `locked` / `锁定` | 账号锁定 | 返回 `needs_human` |
| CAPTCHA 相关元素 / 验证码 | 需要人工验证 | 返回 `needs_human` |
| 2FA / 短信验证 / 二次验证 | 需要人工验证 | 返回 `needs_human` |

**登录成功后保存 storageState**:

```
工具: browser_run_code
code: |
  async (page) => {
    const state = await page.context().storageState({ path: '<profile-path>/storage-state.json' });
    return { saved: true, cookieCount: state.cookies.length };
  }
```

**绝对不要**在密码错误后重试登录 — 重复尝试会触发账号锁定（6 次失败后临时锁定）。

## Navigate to Domain

### Step 4: Enter Account Area

登录后页面右上角有 `欢迎 <用户名> !` 文本。该文本在 `<li>` 元素内，不可直接点击。其内部包含一个 `我的账号` 链接 (`href="javascript:void(0)"`)。

**必须使用 JS evaluate 方式点击**：

```
# 点击 "我的账号" 链接进入账号管理
工具: browser_evaluate
参数: { function: "() => { Array.from(document.querySelectorAll('a')).find(a => a.textContent.includes('我的账号')).click() }" }
```

不要尝试点击 `欢迎 * !` 文本本身，它不是可交互元素。

### Step 5: Redirect to Control Panel

系统通过 SSO token 跳转到 `cp.hostclub.org`。实际跳转路径：

```
hostclub.org → CustomerIndexServlet?redirectpage=null&userLoginId=...&... → cp.hostclub.org
```

**SSO 跳转检测**（最多等待 15 秒，重试 2 次）：

```
# 1. 等待页面加载
工具: browser_wait_for
参数: { time: 5 }

# 2. 检查当前 URL
工具: browser_evaluate
参数: { function: "() => location.href" }
```

| URL 检查结果 | 判定 | 操作 |
|-------------|------|------|
| 包含 `cp.hostclub.org` | SSO 成功 | 继续 Step 6 |
| 仍是 `hostclub.org` | 跳转未发生 | 重试点击"我的账号"（最多 2 次） |
| 其他 URL | 异常 | 返回 `failed`，error: `SSO redirect failed` |
| 3 次尝试后仍未到 cp.hostclub.org | 超时 | 返回 `failed`，error: `SSO redirect to cp.hostclub.org timed out` |

确认 URL 正确后取 snapshot：

```
工具: browser_snapshot
参数: {}
# 确认 URL 包含 cp.hostclub.org
```

### Step 6: Search for Domain

管理中心页面有搜索字段：

- **管理中心首页**: 搜索字段 placeholder 为 `输入域名或订单号`
- **域名详情页**: 有另一个搜索字段 `跳转到域名`

```
# 在管理中心搜索域名
# 先 snapshot 找到搜索框的 ref
工具: browser_snapshot
参数: {}

# 在搜索框中输入域名并提交
工具: browser_type
参数: { ref: "<search-ref>", text: "example.com", submit: true }
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

```
工具: browser_snapshot
参数: {}
```

Three possible states:

#### State A: Not Enabled

- No `Titan Email (Global)` section visible, OR
- A `Start Free Trial Now` button is present.

**Action (create mode only)**: Click `Start Free Trial Now` to activate the free trial.

**⚠️ 重要: 激活是异步操作，点击后页面不会立即更新。MUST 执行下方的完整轮询流程，绝对不要点击后直接跳到下一步。**

**实测行为（2026-03-16 验证）**:
- 点击后页面显示 `Activating free trial ...` 文本，按钮变为 disabled
- 同时弹出提示: `Your Order will be processed by our automatic provisioning system in the next 5-10 minutes`
- **实际激活通常在 15-30 秒内完成**，页面会自动刷新显示激活后的 Titan 区块（含 `Business (Free Trial)`、`Go to Admin Panel` 等）

**激活轮询流程（必须完整执行）**:

```
# ━━━━ 步骤 1: 点击激活按钮 ━━━━
工具: browser_click
参数: { ref: "<start-trial-ref>", element: "Start Free Trial Now button" }

# ━━━━ 步骤 2: 首次检查 — 确认点击生效 ━━━━
工具: browser_wait_for
参数: { time: 3 }

工具: browser_snapshot
参数: {}
# 检查: 是否出现 "Activating free trial ..." 文本？
# 按钮是否变为 disabled？
# 如果是 → 点击成功，进入轮询循环。

# ━━━━ 步骤 3–7: 轮询循环，最多执行 12 轮（约 120 秒）━━━━
# ────── 轮询第 N 轮开始 ──────

# 步骤 3: 等待 10 秒
工具: browser_wait_for
参数: { time: 10 }

# 步骤 4: 取 snapshot 检查页面
工具: browser_snapshot
参数: {}

# 步骤 5: 检查激活成功标志（以下标志必须同时出现）:
#   ✓ `Business (Free Trial)` 文本
#   ✓ `TOTAL EMAIL ACCOUNTS` 文本
#   ✓ `Go to Admin Panel` 按钮

# 步骤 6: 判断结果
#   - 标志全部出现 → ⚠️ 激活成功！立即退出轮询，继续 Step 8
#   - 页面显示 "Activating free trial ..." 或按钮为 disabled → 激活进行中，继续等待
#   - 页面无变化 → 继续等待
#
# ⚠️ 关键: 一旦 snapshot 中出现 Business (Free Trial) 和 Go to Admin Panel，
#    必须立即认定激活成功并退出轮询，不要继续等待。

# 步骤 7: 如果连续 4 轮无变化（约 40 秒），尝试刷新页面
工具: browser_evaluate
参数: { function: "() => { location.reload() }" }

工具: browser_wait_for
参数: { time: 5 }

# ────── 轮询第 N 轮结束 ──────

# ━━━━ 超时处理 ━━━━
# 12 轮轮询后（约 120 秒）仍未看到激活标志:
# 返回 failed，error: "Free trial activation timed out"
```

**轮询逻辑总结**:
1. 点击 `Start Free Trial Now`
2. 等 3 秒后首次 snapshot，确认点击生效
3. 循环: 每 10 秒 snapshot 一次，检查成功标志
4. 每 4 轮无变化时刷新页面（`location.reload()`）
5. 最多 12 轮（120 秒）后超时返回 `failed`

#### State B: Enabled (Trial Active)

页面元素:
- `Business (Free Trial)` 按钮（可点击）
- `TOTAL EMAIL ACCOUNTS X/Y` 纯文本
- `Go to Admin Panel` 按钮（`<span class="wp-btn-blue-hollow">`，可点击）— 进入 Titan 管理面板的入口
- `X/Y Account(s)` 按钮（显示当前配额，可点击）
- `buy more` 按钮
- `Delete Accounts` 按钮

**Playwright 优势**: 这些元素都在 closed shadow DOM 内，但 Playwright snapshot 可以直接获取其 ref，`browser_click` 可以直接点击。不需要特殊的 `getByText` 绕行。

#### State C: Quota 判断

- 从 `TOTAL EMAIL ACCOUNTS` 后的文本解析 `X/Y`（如 `0/2` 表示有空位，`2/2` 表示已满）。X 是已用数量，Y 是总配额。配额已满的判定条件：`X >= Y`。
- 也可以看 `Account(s)` 按钮上的数字

### Step 8: Enter Titan Panel

**实际入口**: 点击 `Go to Admin Panel` 按钮，跳转到 `https://manage.titan.email/partner/autoLogin?partnerId=...&jwt=...`。通过 JWT 自动认证，直接进入 Titan 管理面板，无需单独登录。

**⚠️ 重要: `Go to Admin Panel` 会在新标签页打开。必须切换标签页才能操作 Titan 面板。**

**Playwright 可以直接操作 shadow DOM 内的按钮**: 取 snapshot 后找到 `Go to Admin Panel` 的 ref，直接 `browser_click` 即可。

```
# 1. 记录当前标签页列表（Hostclub 标签页通常是 index 0）
工具: browser_tabs
参数: { action: "list" }

# 2. 获取 snapshot，找到 "Go to Admin Panel" 的 ref
工具: browser_snapshot
参数: {}

# 3. 点击 Go to Admin Panel
工具: browser_click
参数: { ref: "<go-to-admin-panel-ref>", element: "Go to Admin Panel button" }

# 4. 等待新标签页打开
工具: browser_wait_for
参数: { time: 3 }

# 5. 获取更新后的标签页列表
工具: browser_tabs
参数: { action: "list" }
# 新标签页应该包含 manage.titan.email，通常是 index 1

# 6. 切换到 Titan 标签页
工具: browser_tabs
参数: { action: "select", index: 1 }
```

### Titan 管理面板入口

进入 Titan 管理面板的入口是 `Go to Admin Panel` 按钮，目标 URL: `manage.titan.email/partner/autoLogin?...jwt=...`（JWT 自动认证，可创建/管理邮箱）。

## Titan Admin Panel

### Step 9: Access Titan Panel

> **前提**: 已通过 Step 8 切换到 Titan 标签页。

在 Titan 标签页上执行 snapshot：

```
工具: browser_snapshot
参数: {}
```

点击 `Go to Admin Panel` 后，浏览器通过 JWT 自动认证跳转到 `manage.titan.email/email-accounts`（管理面板）。

**正常情况**: 页面标题为 "邮箱控制面板"，显示邮箱帐户列表（可能为空）。页面包含 `新建邮箱帐户` 按钮。URL 包含 `manage.titan.email`。

**异常情况**: JWT 过期或网络异常时，可能无法正确认证。

```
# 检查 URL 和页面内容（确认已在 Titan 标签页上）：
工具: browser_evaluate
参数: { function: "() => location.href" }

工具: browser_snapshot
参数: {}
# - 如果看到邮箱列表或 "新建邮箱帐户" 按钮 → 管理面板可达，继续 Step 10
# - 如果 URL 不包含 manage.titan.email → 异常，见下方降级处理
```

**降级处理**:

当 JWT 认证失败无法进入管理面板时，处理策略：
1. 将 `adminPanelAccessible` 设为 `false`
2. 依据 Phase 4 从域名详情页获取的配额信息（如 `TOTAL EMAIL ACCOUNTS X/Y`）判断状态
3. 如果配额已满（X >= Y），返回 `quota_reached`
4. 如果配额未满，返回 `failed`，error: `Titan admin panel authentication failed`

### Step 10: Read Existing Mailboxes

> 此步骤仅在成功进入管理面板时执行。

On the email accounts page, read the list of existing mailbox accounts. Note:

- The email address displayed (e.g., `contact@wavelengthpulsmk.com`).
- The total count indicator (e.g., `1/2` or `2/2`).

## Mailbox Creation

### Step 11: Idempotency Check

Before creating, compare `mailboxName@domain` against the existing mailbox list.

- If found: return `already_exists` immediately. No further action needed.
- If not found and quota available (used < total): proceed to creation.
- If not found and quota reached (used >= total): return `quota_reached`.

### Step 12: Create Mailbox

1. Click `新建邮箱帐户` (Create New Email Account) button. A dialog will appear with title "创建新邮箱帐户".

```
工具: browser_click
参数: { ref: "<create-btn-ref>", element: "新建邮箱帐户 button" }
```

2. If an upgrade prompt appears instead of a creation form, quota is reached. Return `quota_reached`.

3. Before filling the form, generate a mailbox password:

```bash
./scripts/generate_mailbox_password.sh --json
```

4. Fill in the creation form (dialog 内的字段):

```
工具: browser_snapshot
参数: {}
# 找到表单字段的 ref

工具: browser_fill_form
参数: {
  fields: [
    { name: "邮箱", type: "textbox", ref: "<email-ref>", value: "<mailboxName>" },
    { name: "密码", type: "textbox", ref: "<password-ref>", value: "<generated-password>" }
  ]
}
```

   - **邮箱** (textbox, placeholder "e.g John"): 填入 `mailboxName`。域名后缀 `@domain` 会自动显示在输入框右侧。
   - **密码** (textbox, placeholder "最少8个字符。"): 填入生成的密码。
   - **密码恢复邮箱地址** (textbox, 可选): 可留空。
   - **注意**: 不勾选"自动生成密码"复选框，使用脚本生成的密码。

5. Click `创建新帐户` button to submit. Note: the button is disabled until both email and password fields are filled.

```
工具: browser_click
参数: { ref: "<submit-ref>", element: "创建新帐户 button" }
```

6. Wait for confirmation dialog showing `创建成功！` text.

```
工具: browser_wait_for
参数: { text: "创建成功" }
```

### Step 13: Verify Creation

After form submission:

1. Check for a success message or confirmation dialog.
2. Verify the new mailbox appears in the email accounts list.
3. Return the generated password in the structured result for the caller to store securely. Do not write it to `domains.json` and do not expose it in logs.

## Domain Switching (Batch)

When processing multiple domains under the same account, switch domains without logging out:

### Step 14: Clean Up Titan Tab

在切换到下一个域名之前，**必须先关闭当前域名的 Titan 标签页**（如果有），然后回到 Hostclub 标签页：

```
# 1. 获取标签页列表
工具: browser_tabs
参数: { action: "list" }

# 2. 如果存在 Titan 标签页（index 1），关闭它
工具: browser_tabs
参数: { action: "close", index: 1 }

# 3. 确认当前活跃标签页是 Hostclub（index 0）
工具: browser_tabs
参数: { action: "list" }
```

### Step 15: Switch Domain

1. From the current domain's order detail page on `cp.hostclub.org`.
2. 使用域名详情页上的 `跳转到域名` 搜索字段，或返回管理中心使用 `输入域名或订单号` 搜索字段。
3. Enter the next domain name and submit.
4. Navigate to the new domain's order detail page.
5. Continue from [Email Status Detection](#email-status-detection).

```
# 在域名详情页直接跳转到另一个域名
工具: browser_snapshot
参数: {}
# 找到 "跳转到域名" 搜索框的 ref

工具: browser_type
参数: { ref: "<jump-to-domain-ref>", text: "next-domain.com", submit: true }
```

Before each domain switch, re-verify login state. If the session expired (no `欢迎` text visible, or redirect to login page), re-authenticate before continuing.

## Tab Management

整个 skill 执行过程中需要管理的标签页：

| 阶段 | 标签页 | 说明 |
|------|--------|------|
| Phase 2–3 | Hostclub 主标签页 (index 0) | 登录、导航、域名搜索 |
| Phase 4 Step 8 | Titan 新标签页 (index 1) | `Go to Admin Panel` 打开 |
| Phase 5 | Titan 标签页 (index 1) | 邮箱列表、创建表单 |
| Phase 6 | 回到 Hostclub 标签页 (index 0) | 域名切换（batch） |

**关键规则**:

1. **`Go to Admin Panel` 总是在新标签页打开** — 点击后必须 `browser_tabs(list)` → `browser_tabs(select, index: 1)` 切换
2. **操作完 Titan 面板后需要关闭该标签页** — 尤其在 batch 模式下，防止标签堆积: `browser_tabs(close, index: 1)`
3. **每次 snapshot/click/type 前确认在正确的标签页** — 错误的标签页会导致 snapshot 内容不匹配
4. **Hostclub 标签页始终是 index 0** — Titan 标签页关闭后自动回到 index 0

标签操作详见 `references/browser-commands.md` 的 "标签页管理工作流" 章节。

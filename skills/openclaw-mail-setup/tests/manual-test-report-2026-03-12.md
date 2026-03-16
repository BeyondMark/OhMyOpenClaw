# openclaw-mail-setup 手工测试记录（2026-03-12）

## 测试目标

按 `skills/openclaw-mail-setup/SKILL.md` 的直接模式流程执行一次创建邮箱测试，并记录实际出现的问题。

测试场景采用 `tests/evals.json` 中的第 1 个用例：

- 账号：`monetize@visionate.net`
- 密码：`test123`
- 域名：`visionate.net`
- 邮箱前缀：`sales`

## 测试前处理

先删除 direct mode 默认测试 profile `hostclub-001`，再重新创建干净 profile：

```bash
openclaw browser stop --browser-profile hostclub-001
openclaw browser delete-profile --name hostclub-001
./skills/openclaw-mail-setup/scripts/manage_profile.sh --create hostclub-001 --json
```

结果：

- `hostclub-001` 已成功删除
- `hostclub-001` 已成功重新创建

## 实际执行过程

### 1. 预检查

执行：

```bash
./skills/openclaw-mail-setup/scripts/check_config.sh --json
```

结果：

- `~/.openclaw/mail/accounts.json` 和 `~/.openclaw/mail/domains.json` 不存在
- skill 按预期进入 direct mode

### 2. 打开登录页

执行：

```bash
openclaw browser navigate "https://www.hostclub.org/login.php" --browser-profile hostclub-001
openclaw browser snapshot --browser-profile hostclub-001 --labels --efficient
```

结果：

- 登录页可以正常打开
- 页面上同时存在登录表单和注册表单
- `input[name=txtUserName]` / `input[name=txtPassword]` 选择器在真实页面中有效

### 3. 提交登录表单

执行：

```bash
openclaw browser evaluate --fn "document.querySelector('input[name=txtUserName]').value = 'monetize@visionate.net'" --browser-profile hostclub-001
openclaw browser evaluate --fn "document.querySelector('input[name=txtPassword]').value = 'test123'" --browser-profile hostclub-001
openclaw browser evaluate --fn "HTMLFormElement.prototype.submit.call(document.querySelector('input[name=txtUserName]').form)" --browser-profile hostclub-001
openclaw browser wait --browser-profile hostclub-001 --time 5000
```

结果：

- 表单字段填写成功
- `HTMLFormElement.prototype.submit.call(...)` 在真实页面可用
- 页面跳转到：

```text
https://www.hostclub.org/login.php?fromsecurelogin=true&login=invalid
```

- 页面正文出现错误：

```text
无效的用户名或密码
You have 4/6 login attempts remaining.
Your account will be locked temporarily after 4 more incorrect attempts.
```

## 结论

本次测试在 Phase 2（登录）终止，未进入域名导航、Titan 状态检测或邮箱创建阶段。

已经确认可工作的部分：

- direct mode 判定正确
- 默认 profile 解析与重建流程正确
- Hostclub 登录页路径正确
- 登录表单字段名与文档一致
- 用 DOM selector 精确填写并提交表单的方法正确
- `generate_mailbox_password.sh --json` 可正常生成强密码

## 发现的问题

### 问题 1：测试用例中的账号密码当前无法通过真实登录

现象：

- 按 `tests/evals.json` 第 1 个用例执行时，返回 `login=invalid`
- 页面明确提示“无效的用户名或密码”

影响：

- 当前 eval 数据无法支撑完整的端到端验证
- 无法继续验证 Phase 3 到 Phase 6

建议：

- 使用真实可登录的测试账号
- 或者把这类 eval 明确标注为“示例数据 / 非可执行真实账号”

### 问题 2：继续重试当前测试数据有账号锁定风险

现象：

- 登录失败页提示 `You have 4/6 login attempts remaining.`
- 说明继续自动重试会触发临时锁定

影响：

- 如果把当前 eval 当成回归测试反复执行，可能导致账号被锁

建议：

- 测试框架里对 `login=invalid` 设为立即停止，不要重试
- 对真实站点回归测试增加“单次失败即中止”的保护

### 问题 3：`snapshot --labels --efficient` 看不到登录失败错误横幅

现象：

- `snapshot --labels --efficient` 输出里只看到了表单和导航链接
- 没有包含“无效的用户名或密码”错误文本
- `snapshot --format aria` 和 `evaluate(document.body.innerText)` 才能稳定拿到错误内容

影响：

- 如果 skill 仅依赖 `snapshot --labels --efficient` 来判断登录结果，可能误判为“只是还在登录页”
- 错误分类会不稳定，尤其是要区分“密码错误”和“需要人工介入”时

建议：

- 登录提交后优先用 `evaluate --fn "document.body.innerText"` 检查错误文案
- 或在失败分支使用 `snapshot --format aria`
- 不要只依赖 AI snapshot 的精简视图做失败判断

## 补充验证

执行：

```bash
./skills/openclaw-mail-setup/scripts/generate_mailbox_password.sh --json
```

结果：

- 正常返回长度 18 的强密码
- 包含大小写字母、数字和特殊字符

## 后续建议

如果要继续完成完整流程测试，下一步应优先准备：

1. 一个真实可登录的 Hostclub 测试账号
2. 一个可安全操作的测试域名
3. 明确该域名当前是否已开通 Titan、是否还有试用配额

---

## 第二轮测试（使用更新后的真实凭据）

### 测试输入

- 账号：`monetize@visionate.net`
- 密码：`[已验证可登录，未在记录中重复展开]`

### 测试前处理

再次执行删除并重建 `hostclub-001`。

实际观察到：

- `openclaw browser delete-profile --name hostclub-001` 成功
- 紧接着调用 `./scripts/manage_profile.sh --create hostclub-001 --json` 返回失败
- 直接调用 `openclaw browser create-profile --name hostclub-001` 随后成功

说明：

- profile 删除后立即重建存在时序窗口，`manage_profile.sh` 当前没有处理这类瞬时失败

### 1. 登录测试

结果：

- 成功登录 Hostclub 首页
- 页面可见 `欢迎 Yuan Jian !`
- 文档中关于 `我的账号` 需要用 `evaluate --fn` 点击的描述与真实页面一致

### 2. 进入管理中心

执行点击 `我的账号` 后，成功跳转：

```text
https://cp.hostclub.org/servlet/CustomerIndexServlet?...&fromsupersite=true
```

结果：

- 成功进入 `cp.hostclub.org`
- 管理中心存在 `jump-to-domain-input`

### 3. 搜索 `visionate.net`

结果：

- 搜索后进入 `ListAllOrdersServlet`
- 页面明确显示：`无法找到任何订单。`

结论：

- `tests/evals.json` 第 1 个用例中声明的 `visionate.net` 当前不在该账号下，或至少无法从当前账号的订单搜索中找到
- 因而第 1 个 eval 的前提条件已经不成立

### 4. 搜索 `wavelengthpulsmk.com`

结果：

- 搜索后能找到 2 条订单：
  - `wavelengthpulsmk.com` / `Titan Email (Global)`
  - `wavelengthpulsmk.com` / `域名管理`

- 点击后可进入域名详情页：

```text
https://cp.hostclub.org/servlet/ViewDomainServlet?orderid=124721379...
```

### 5. Titan Email 状态检查

在域名详情页的 `Titan Email (Global)` 区块观察到：

- `Business (Free Trial)`
- `1/1 Account(s)`
- `Login to Webmail`

这说明：

- Titan 已开通试用
- 当前免费额度已满

### 6. 进入 Titan 面板

点击 `Login to Webmail` 后，OpenClaw 新开了一个标签页，地址是：

```text
https://mailhostbox.titan.email/login/
```

页面内容是终端用户邮箱登录页，而不是管理员邮箱列表页。

结论：

- `adminPanelAccessible=false`
- 真实行为与 skill 文档中“可能落在终端用户登录页”的降级分支一致

## 第二轮新增问题

### 问题 4：`manage_profile.sh --create` 对“删除后立即重建”不稳

现象：

- 删除 profile 后立即创建，脚本返回失败
- 但随后直接调用 CLI 创建成功

影响：

- 按 skill 流程做“测试前清理 profile”时，可能随机失败
- 失败并不一定代表 profile 真创建不了

建议：

- `manage_profile.sh --create` 增加短暂重试
- 或在 delete 后等待 profile 真正从 `openclaw browser profiles` 消失再创建

### 问题 5：`openclaw browser wait --url` 在当前 CLI 版本下不可用

现象：

- 执行 `openclaw browser wait --url "..."` 报错：
  `gateway url override requires explicit credentials`

影响：

- skill 或测试脚本如果依赖 `wait --url`，在当前 OpenClaw 版本上会误失败

建议：

- 改用 `evaluate --fn "location.href"` 轮询
- 或者只用 `wait --time` / `wait --text` 组合判断

### 问题 6：第 1 个 eval 的域名前提失效

现象：

- 成功登录后搜索 `visionate.net`，返回“无法找到任何订单”

影响：

- `create-new-mailbox-direct-mode` 这个用例当前无法作为真实端到端测试样本

建议：

- 替换成当前账号下真实存在的测试域名

### 问题 7：第 2 个 eval 的 `already_exists` 结果在真实降级路径下不一定可达

现象：

- `wavelengthpulsmk.com` 的 Titan 区块显示 `1/1 Account(s)`
- 点击 `Login to Webmail` 后落在 `mailhostbox.titan.email/login/` 终端用户登录页
- 无法进入管理员邮箱列表，因此无法验证具体邮箱地址是否是 `contact@wavelengthpulsmk.com`

影响：

- 按 skill 当前定义，`adminPanelAccessible=false` 且配额已满时，应返回 `quota_reached`
- 这与 `tests/evals.json` 第 2 个用例期望的 `already_exists` 存在冲突

建议：

- 重新定义第 2 个 eval 的前提条件：
  必须保证能进入 Titan 管理面板并读取已有邮箱列表
- 或调整预期结果，承认在真实降级路径中只能稳定返回 `quota_reached`

## 第二轮测试结论

使用新的账号密码后，可以确认以下真实情况：

- 登录流程本身可用
- `我的账号` → `cp.hostclub.org` 跳转可用
- `visionate.net` 这个测试域名前提已失效
- `wavelengthpulsmk.com` 真实存在，Titan 试用已开通且额度已满
- `Login to Webmail` 落在终端用户登录页，无法稳定做幂等性枚举

---

## 第三轮测试（按更新后的 eval 重新验证）

### 说明

- 本轮按照更新后的 `tests/evals.json` 重新验证
- 测试前仍然删除并重建 `hostclub-001`，但这仅作为测试环境清理动作，不应视为生产流程要求

### 本轮结果摘要

- `check_config.sh --json` 仍返回 `not_found`，确认 direct mode
- 登录成功，出现 `欢迎 Yuan Jian !`
- 成功进入 `cp.hostclub.org`
- 成功进入 `wavelengthpulsmk.com` 域名详情页
- `Titan Email (Global)` 区块可见：
  - `Business (Free Trial)`
  - `1/1 Account(s)`
  - `Login to Webmail`
- 点击 `Login to Webmail` 后，新标签页落在：

```text
https://mailhostbox.titan.email/login/
```

- 该页面是终端用户邮箱登录页，不是管理员邮箱列表页

### 对更新后 eval 的验证结论

- 第 1 个 eval：
  更新后的 `quota_reached / mailboxPassword: null` 预期，与本轮真实结果一致

- 第 2 个 eval：
  当前真实环境下命中的是 `adminPanelAccessible=false` 的降级分支，因此结果应为 `quota_reached`，这与更新后的说明一致

- 第 3 个 eval：
  当前真实环境下也应返回 `quota_reached`，与更新后的说明一致

### 本轮新增问题

### 问题 8：域名跳转表单更适合真实点击提交，不适合直接 `form.submit()`

现象：

- 在管理中心对 `#jump-to-domain-input` 直接执行 `HTMLFormElement.prototype.submit.call(form)` 时，出现过请求参数异常，最终搜索结果不稳定
- 改为：
  1. 先设置 `#jump-to-domain-input` 的值
  2. 再点击 `#jump-to-domain-submit-button`
  即可稳定进入目标域名详情页

影响：

- 如果 skill 在 Phase 3 里对该表单使用裸 `form.submit()`，域名跳转可能偶发失败或产生异常查询参数

建议：

- `cp.hostclub.org` 的域名跳转优先使用“填写输入框 + 点击提交按钮”的方式
- 不要把登录页的提交策略直接复用到控制台里的域名跳转表单

### 本轮结构化结果（按真实页面推断）

```json
{
  "success": false,
  "mode": "create",
  "status": "quota_reached",
  "createdMailbox": null,
  "mailboxPassword": null,
  "emailEnabled": true,
  "trialStarted": true,
  "adminPanelAccessible": false,
  "existingMailboxes": [],
  "mailboxQuotaReached": true,
  "canCreateAnotherMailbox": false,
  "error": null
}
```

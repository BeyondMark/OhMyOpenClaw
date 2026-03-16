# Playwright MCP 浏览器工具速查

本文档列出 `openclaw-mail-setup` skill 执行过程中使用的所有 Playwright MCP 浏览器自动化工具。

> **架构说明**: 所有浏览器操作通过 Playwright MCP 工具执行。Agent 直接调用这些 MCP 工具进行页面交互。
>
> **环境兼容性**:
> - **Claude Code**: 使用内置 Playwright MCP 插件（`plugin:playwright:playwright`）
> - **OpenClaw**: 安装 `playwright-mcp` skill（来自 `openclaw/skills` 官方仓库），提供相同的工具接口
>
> 两个环境下工具名和参数完全一致，SKILL.md 无需区分。

## 页面导航与快照

### browser_navigate — 打开 URL

```
工具: browser_navigate
参数: { url: "https://www.hostclub.org/login.php" }
```

### browser_snapshot — 获取页面可访问性快照

```
工具: browser_snapshot
参数: {}
```

snapshot 返回页面的 accessibility tree，包含每个可交互元素的 `ref`（引用标识符）。后续的 click/type 操作使用这些 ref 定位元素。

**优势**: Playwright snapshot 可以穿透 closed shadow DOM，直接获取其中元素的 ref。OpenClaw 时代需要特殊处理的 `Go to Admin Panel` 等按钮，现在可以直接通过 ref 操作。

### browser_take_screenshot — 截图

```
工具: browser_take_screenshot
参数: { type: "png" }
# 或截取特定元素:
参数: { type: "png", ref: "E14", element: "Titan Email section" }
# 或全页截图:
参数: { type: "png", fullPage: true }
```

## 元素交互

### browser_click — 点击元素

```
工具: browser_click
参数: { ref: "E14", element: "Start Free Trial Now button" }
```

- `ref`: snapshot 中元素的引用标识符
- `element`: 人类可读的元素描述（用于权限确认）

### browser_type — 在输入框中输入文本

```
工具: browser_type
参数: { ref: "E7", text: "example.com", submit: true }
```

- `submit`: 输入后按 Enter 提交
- `slowly`: 逐字符输入（触发 key handler 时使用）

### browser_fill_form — 批量填写表单字段

```
工具: browser_fill_form
参数: {
  fields: [
    { name: "用户名", type: "textbox", ref: "E3", value: "user@example.com" },
    { name: "密码", type: "textbox", ref: "E5", value: "password123" }
  ]
}
```

字段类型: `textbox`, `checkbox`, `radio`, `combobox`, `slider`

适用场景: 一次填写多个表单字段，比逐个 type 更高效。

### browser_evaluate — 执行 JavaScript

```
工具: browser_evaluate
参数: { function: "() => document.body.innerText" }
```

带元素参数:

```
工具: browser_evaluate
参数: {
  function: "(element) => element.textContent",
  ref: "E14",
  element: "page title"
}
```

适用场景:
- 获取页面完整文本（用于登录结果检测等）
- 读取 `location.href` 检查当前 URL
- 操作 DOM 元素（精确定位特定字段）
- 执行表单提交（绕过 `name="submit"` 覆盖问题）

### browser_evaluate 最佳实践

**先最小脚本验证，再扩展**。不要一次性写长脚本，先用最简单的表达式确认选择器能命中目标元素。

常见示例:

```javascript
// 获取页面完整文本
() => document.body.innerText

// 检查当前 URL
() => location.href

// 精确填写带 name 属性的表单字段
() => { document.querySelector('input[name=txtUserName]').value = 'user@example.com' }

// 提交表单（绕过 name="submit" 覆盖）
() => { HTMLFormElement.prototype.submit.call(document.querySelector('input[name=txtUserName]').form) }

// 点击通过文本查找的链接
() => { Array.from(document.querySelectorAll('a')).find(a => a.textContent.includes('我的账号')).click() }

// 刷新页面
() => { location.reload() }
```

### browser_run_code — 运行 Playwright 代码片段

```
工具: browser_run_code
参数: {
  code: "async (page) => { await page.getByText('Go to Admin Panel').click(); return await page.title(); }"
}
```

适用场景:
- **storageState 操作**（加载/保存 cookie）
- 需要 Playwright 高级 API（`getByText`, `getByRole`, `waitForSelector` 等）
- 复杂的多步骤操作需要在一个调用中完成

**Profile storageState 加载模板**:

> **注意**: `browser_run_code` 中 `require('fs')` 不可用。需要先用 bash 读取 cookie，再通过 `browser_run_code` 注入。

```bash
# 步骤 1: 用 bash 提取 cookie 数组
cat <profile-path>/storage-state.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d['cookies']))"
```

```
# 步骤 2: 将 cookie 数组传入 browser_run_code
工具: browser_run_code
code: |
  async (page) => {
    const cookies = <paste-cookie-array-here>;
    await page.context().addCookies(cookies);
    return { loaded: true, cookieCount: cookies.length };
  }
```

**Profile storageState 保存模板**:

```
工具: browser_run_code
code: |
  async (page) => {
    const state = await page.context().storageState({ path: '<profile-path>/storage-state.json' });
    return { saved: true, cookieCount: state.cookies.length };
  }
```

## 标签页管理

### browser_tabs — 列出/创建/关闭/切换标签页

**列出所有标签页**:
```
工具: browser_tabs
参数: { action: "list" }
```

**切换到指定标签页**（使用 0-based index）:
```
工具: browser_tabs
参数: { action: "select", index: 1 }
```

**关闭标签页**:
```
工具: browser_tabs
参数: { action: "close", index: 1 }
# 省略 index 则关闭当前标签页:
参数: { action: "close" }
```

**创建新标签页**:
```
工具: browser_tabs
参数: { action: "new" }
```

> **注意**: Playwright MCP 使用 0-based index 标识标签页，不是 targetId。`list` 返回的标签页列表中，每个标签页的位置即为其 index。

### 标签页管理工作流

`Go to Admin Panel` 按钮会在新标签页打开 Titan Email 管理面板。必须主动切换标签页才能操作新页面。

**进入 Titan 面板**:

```
# 1. 记录当前标签页列表（Hostclub 标签页通常是 index 0）
工具: browser_tabs → { action: "list" }

# 2. 点击 "Go to Admin Panel"（Playwright 可以直接通过 snapshot ref 点击）
工具: browser_click → { ref: "<ref>", element: "Go to Admin Panel button" }

# 3. 等待新标签页打开
工具: browser_wait_for → { time: 3 }

# 4. 获取更新后的标签页列表
工具: browser_tabs → { action: "list" }
# 新标签页应该包含 manage.titan.email，通常是 index 1

# 5. 切换到 Titan 标签页
工具: browser_tabs → { action: "select", index: 1 }

# 6. 在 Titan 标签页上操作
工具: browser_snapshot → {}
```

**返回 Hostclub 页面**:

```
# 切回 Hostclub 标签页（index 0）
工具: browser_tabs → { action: "select", index: 0 }
```

**批量域名切换时清理旧标签**:

```
# 处理完当前域名后，关闭 Titan 标签页再切换到下一个域名
工具: browser_tabs → { action: "close", index: 1 }
# 关闭后自动回到 index 0 (Hostclub 标签页)
```

## 等待

### browser_wait_for — 等待条件满足

**等待固定时间**（单位: 秒）:
```
工具: browser_wait_for
参数: { time: 5 }
```

**等待文本出现**:
```
工具: browser_wait_for
参数: { text: "欢迎" }
```

**等待文本消失**:
```
工具: browser_wait_for
参数: { textGone: "Loading..." }
```

> **注意**: `time` 参数单位是**秒**，不是毫秒。

## 浏览器安装

### browser_install — 安装浏览器

```
工具: browser_install
参数: {}
```

在 Phase 1 预检阶段调用。如果后续浏览器操作报错提示浏览器未安装，也应调用此工具。

## 处理 Ref 歧义

当 snapshot 中的 ref 可能匹配多个元素时（常见于登录页面有注册+登录两个表单），采用以下策略：

1. **使用 `browser_evaluate`**: 通过 CSS selector 或 XPath 精确定位元素

```javascript
// ❌ 错误: ref 可能匹配注册表单的输入框
// browser_type ref="T3" text="username"

// ✅ 正确: 通过 name 属性精确定位
() => { document.querySelector('input[name=txtUserName]').value = 'username' }
```

2. **使用 `browser_fill_form`**: 如果 ref 已明确对应正确字段

```
fields: [
  { name: "用户名", type: "textbox", ref: "E3", value: "user@example.com" },
  { name: "密码", type: "textbox", ref: "E5", value: "password123" }
]
```

3. **使用 `browser_run_code`**: 对于复杂场景

```javascript
async (page) => {
  await page.locator('input[name=txtUserName]').fill('user@example.com');
  await page.locator('input[name=txtPassword]').fill('password123');
  await page.locator('input[name=txtUserName]').evaluate(el =>
    HTMLFormElement.prototype.submit.call(el.form)
  );
}
```

## Closed Shadow DOM

**Playwright 原生支持 closed shadow DOM**。与 OpenClaw 不同，Playwright 的 snapshot（accessibility tree）和 locator API 可以直接穿透 shadow DOM 边界：

- `browser_snapshot` 可以获取 shadow DOM 内元素的 ref
- `browser_click` 可以直接点击 shadow DOM 内的元素
- `browser_run_code` 中 `page.getByText()` / `page.getByRole()` 也可以定位 shadow DOM 内元素

**不再需要特殊处理**的元素:
- `Go to Admin Panel` (`<span class="wp-btn-blue-hollow">`)
- `MANAGE EMAIL ACCOUNTS` 标题
- `TOTAL EMAIL ACCOUNTS` 配额显示
- `Business (Free Trial)` 标签

这些元素在 snapshot 中都会有 ref，可以直接操作。

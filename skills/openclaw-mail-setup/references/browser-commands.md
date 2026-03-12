# OpenClaw Browser CLI 命令速查

本文档列出 `openclaw-mail-setup` skill 执行过程中常用的所有浏览器自动化命令。

## 页面导航与快照

### navigate — 打开 URL

```bash
openclaw browser navigate <url> --browser-profile <profile>
```

示例:
```bash
openclaw browser navigate "https://www.hostclub.org/" --browser-profile hostclub-001
```

### snapshot — 获取页面可访问性快照

```bash
openclaw browser snapshot --browser-profile <profile> --labels --efficient
```

- `--labels`: 包含元素标签，用于识别表单字段
- `--efficient`: 精简输出，减少 ref 歧义

snapshot 输出包含每个可交互元素的 `ref`（引用标识符），用于后续的 click/type 操作。

## 元素交互

### click — 点击元素

```bash
openclaw browser click <ref> --browser-profile <profile>
```

示例:
```bash
openclaw browser click "E14" --browser-profile hostclub-001
```

### type — 在输入框中输入文本

```bash
openclaw browser type <ref> "<text>" --browser-profile <profile> [--submit]
```

- `--submit`: 输入后自动提交（按 Enter）

示例:
```bash
openclaw browser type "E7" "example.com" --browser-profile hostclub-001 --submit
```

### fill — 批量填写表单字段

```bash
openclaw browser fill --fields-file <path> --browser-profile <profile>
```

fields-file 格式 (JSON):
```json
[
  {"selector": "input[name=txtUserName]", "value": "user@example.com"},
  {"selector": "input[name=txtPassword]", "value": "password123"}
]
```

适用场景: 页面有多个同类型输入框导致 ref 歧义时，使用 CSS selector 精确定位。

### evaluate — 执行 JavaScript

```bash
openclaw browser evaluate --fn '<javascript>' --browser-profile <profile>
```

示例:
```bash
# 点击隐藏链接
openclaw browser evaluate --fn "Array.from(document.querySelectorAll('a')).find(a => a.textContent.includes('我的账号')).click()" --browser-profile hostclub-001

# 读取页面文本
openclaw browser evaluate --fn "document.body.innerText" --browser-profile hostclub-001

# 精确填写表单字段（避免 ref 歧义）
openclaw browser evaluate --fn "document.querySelector('input[name=txtUserName]').value = 'user@example.com'" --browser-profile hostclub-001
```

适用场景:
- 元素没有 ref（如纯文本标签、隐藏链接）
- snapshot ref 匹配多个元素（歧义）
- 需要执行复杂的 DOM 操作

### evaluate 最佳实践

**先最小脚本验证，再扩展**。不要一次性写长脚本，先用最简单的表达式确认选择器能命中目标元素，再逐步添加操作。

常见坑：

```bash
# ❌ form.submit is not a function
# 如果表单内有 name="submit" 的元素，form.submit 会被覆盖为该元素的引用
openclaw browser evaluate --fn "document.querySelector('input[name=txtUserName]').form.submit()" --browser-profile <profile>

# ✅ 使用 HTMLFormElement.prototype.submit.call() 绕过
openclaw browser evaluate --fn "HTMLFormElement.prototype.submit.call(document.querySelector('input[name=txtUserName]').form)" --browser-profile <profile>

# ✅ 或者找到表单提交按钮直接 click
openclaw browser evaluate --fn "document.querySelector('form input[type=submit]').click()" --browser-profile <profile>
```

```bash
# ❌ 语法错误: 引号嵌套、括号不匹配
openclaw browser evaluate --fn "document.querySelector('a[href="javascript:void(0)"]').click()" --browser-profile <profile>

# ✅ 内层用转义引号或不同引号类型
openclaw browser evaluate --fn "document.querySelector('a[href=\"javascript:void(0)\"]').click()" --browser-profile <profile>
```

**验证流程**:
1. 先运行选择器确认能选中元素: `document.querySelector('...')` — 应返回非 null
2. 确认元素属性: `document.querySelector('...').tagName` / `.textContent`
3. 最后执行操作: `.click()` / `.value = '...'` / `form.submit()`

## 标签页管理

### tabs — 列出所有标签页

```bash
openclaw browser tabs --browser-profile <profile>
```

### focus — 切换到指定标签页

```bash
openclaw browser focus <targetId> --browser-profile <profile>
```

`targetId` 从 `tabs` 命令的输出中获取。

**注意**: 不存在 `select-tab` 命令，切换标签页必须使用 `focus`。

### close — 关闭标签页

```bash
openclaw browser close <targetId> --browser-profile <profile>
```

## Profile 管理

### profiles — 列出所有浏览器 profile

```bash
openclaw browser profiles
```

### create-profile — 创建新 profile

```bash
openclaw browser create-profile --name <name>
```

Profile 命名规范: 仅允许小写字母、数字和连字符，推荐格式 `{provider}-{sequence}`（如 `hostclub-001`）。

## 处理 Ref 歧义

当 snapshot 中的 ref 可能匹配多个元素时（常见于登录页面有注册+登录两个表单），采用以下策略：

1. **使用 `--efficient` 模式**: 减少 snapshot 输出中的冗余元素
2. **使用 `evaluate --fn`**: 通过 CSS selector 或 XPath 精确定位元素
3. **使用 `fill --fields-file`**: 通过字段 name 属性批量填写

示例 — 登录页面 ref 歧义处理:

```bash
# ❌ 错误: ref 可能匹配注册表单的输入框
openclaw browser type "T3" "username" --browser-profile hostclub-001

# ✅ 正确: 通过 name 属性精确定位
openclaw browser evaluate --fn "document.querySelector('input[name=txtUserName]').value = 'username'" --browser-profile hostclub-001
```

示例 — 登录按钮误点:

```bash
# ❌ 错误: 匹配文字含"登录"的元素会点到页面顶部的 登录/注册 导航链接
openclaw browser click <含"登录"文字的ref> --browser-profile hostclub-001

# ✅ 正确: 提交登录表单本身，或精确定位表单内的提交按钮
openclaw browser evaluate --fn "HTMLFormElement.prototype.submit.call(document.querySelector('input[name=txtUserName]').form)" --browser-profile hostclub-001
```

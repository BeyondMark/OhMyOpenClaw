# Hostclub / Titan Email Navigation Flow

This document describes the exact browser navigation path for creating an email account through the Hostclub control panel and Titan Email admin panel.

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

### Step 2: Detect Login State

Check the page for a welcome element:

- **Logged in**: page contains text like `欢迎 Yuan Jian!` in the top-right area.
- **Not logged in**: page shows a login form, or URL contains `login`.

### Step 3: Login (if needed)

1. Locate the login form fields (username/email and password).
2. Fill in credentials.
3. Submit the form.
4. Wait for page reload and verify the `欢迎` text appears.

Watch for:
- CAPTCHA challenges (image, slider, etc.) — cannot be automated, return `needs_human`.
- 2FA prompts — cannot be automated, return `needs_human`.
- "Account locked" or "Too many attempts" messages — return `failed`.

## Navigate to Domain

### Step 4: Enter Account Area

1. Click the welcome text/menu element (`欢迎 *!`) in the top-right corner.
2. Select `我的账号` from the dropdown menu.

### Step 5: Redirect to Control Panel

The system will redirect through `content.php?action=cp_login` to `cp.hostclub.org`.

Wait for the `cp.hostclub.org` management center to fully load.

### Step 6: Search for Domain

1. Locate the `跳转到订单` search field on the management center page.
2. Type the target domain name.
3. Press Enter or click the search/go button.
4. The page navigates to the domain's order detail page.

If the domain is not found, the search may return an empty result or an error message. Check for this and report failure.

## Email Status Detection

### Step 7: Check Titan Email Section

On the domain order detail page, look for the `Titan Email (Global)` section.

Three possible states:

#### State A: Not Enabled

- No `Titan Email (Global)` section visible, OR
- A `Start Free Trial Now` button is present.

**Action**: Click `Start Free Trial Now` to activate the free trial.

#### State B: Enabled (Trial Active, Quota Available)

- `Business (Free Trial)` label visible.
- `TOTAL EMAIL ACCOUNTS` shows `0/1` or similar (not at max).
- `Go to Admin Panel` button present.

**Action**: Click `Go to Admin Panel`.

#### State C: Enabled (Quota Reached)

- `TOTAL EMAIL ACCOUNTS` shows `1/1` (at max).
- `Go to Admin Panel` button may still be present.

**Action**: Click `Go to Admin Panel` to check if the target mailbox is the existing one (idempotency). If it is, return `already_exists`. If not, return `quota_reached`.

## Titan Admin Panel

### Step 8: Access Titan Panel

Clicking `Go to Admin Panel` navigates to `manage.titan.email`.

The exact URL pattern is: `https://manage.titan.email/email-accounts`.

Wait for the email accounts list to load.

### Step 9: Read Existing Mailboxes

On the email accounts page, read the list of existing mailbox accounts. Note:

- The email address displayed (e.g., `contact@wavelengthpulsmk.com`).
- The total count indicator (e.g., `1/1`).

## Mailbox Creation

### Step 10: Idempotency Check

Before creating, compare `mailboxName@domain` against the existing mailbox list.

- If found: return `already_exists` immediately. No further action needed.
- If not found and quota available: proceed to creation.
- If not found and quota reached: return `quota_reached`.

### Step 11: Create Mailbox

1. Click `新建邮箱帐户` (Create New Email Account) button.
2. If an upgrade prompt appears instead of a creation form, quota is reached. Return `quota_reached`.
3. Fill in the creation form:
   - Email prefix: `mailboxName`
   - Password: generate or use a provided password (implementation-dependent)
   - Any other required fields
4. Submit the form.
5. Wait for confirmation.

### Step 12: Verify Creation

After form submission:

1. Check for a success message or confirmation dialog.
2. Verify the new mailbox appears in the email accounts list.
3. Take a screenshot for evidence.

## Domain Switching (Batch)

When processing multiple domains under the same account, switch domains without logging out:

1. From the current domain's order detail page on `cp.hostclub.org`.
2. Navigate back to the management center (use browser back or direct URL).
3. In the `跳转到订单` search field, enter the next domain.
4. Navigate to the new domain's order detail page.
5. Continue from [Email Status Detection](#email-status-detection).

Before each domain switch, re-verify login state. If the session expired (no `欢迎` text visible, or redirect to login page), re-authenticate before continuing.

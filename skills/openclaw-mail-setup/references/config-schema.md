# Configuration File Schemas

This document defines the JSON schemas for the account table and domain table used by `openclaw-mail-setup` in config mode.

## File Locations

- Account table: `~/.openclaw/mail/accounts.json`
- Domain table: `~/.openclaw/mail/domains.json`

Override with the `OPENCLAW_MAIL_CONFIG_DIR` environment variable.

## Account Table Schema

```json
{
  "accounts": {
    "<account-id>": {
      "provider": "<platform-identifier>",
      "loginUrl": "<backend-login-url>",
      "username": "<login-username>",
      "passwordEncrypted": "<AES-256-CBC-encrypted-base64>",
      "browserProfile": "<openclaw-profile-name>"
    }
  }
}
```

### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `provider` | string | yes | Platform identifier (e.g., `hostclub`) |
| `loginUrl` | string | yes | Login page URL |
| `username` | string | yes | Login username/email |
| `passwordEncrypted` | string | yes | AES-256-CBC encrypted password, Base64 encoded |
| `browserProfile` | string | yes | Browser profile name, 对应 `~/.openclaw/mail/profiles/{name}/` 目录，用于 Playwright storageState 持久化 (lowercase, digits, hyphens) |

### Account ID Format

Recommended: `acct_{provider}_{sequence}` (e.g., `acct_hostclub_001`).

### Example

```json
{
  "accounts": {
    "acct_hostclub_001": {
      "provider": "hostclub",
      "loginUrl": "https://www.hostclub.org/login.php",
      "username": "monetize@visionate.net",
      "passwordEncrypted": "U2FsdGVkX1+abc123...",
      "browserProfile": "hostclub-001"
    },
    "acct_hostclub_002": {
      "provider": "hostclub",
      "loginUrl": "https://www.hostclub.org/login.php",
      "username": "admin@example.com",
      "passwordEncrypted": "U2FsdGVkX1+def456...",
      "browserProfile": "hostclub-002"
    }
  }
}
```

## Domain Table Schema

```json
{
  "domains": {
    "<domain-name>": {
      "accountId": "<account-id>",
      "mailboxes": ["<email-address>"],
      "lastMailboxCreatedAt": "<iso8601-or-null>",
      "lastStatus": "<status-string-or-null>",
      "lastUpdatedAt": "<iso8601-or-null>"
    }
  }
}
```

### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `accountId` | string | yes | Reference to account table entry |
| `mailboxes` | string[] | yes | Array of created mailbox addresses (empty array `[]` if none created yet) |
| `lastMailboxCreatedAt` | string\|null | yes | ISO 8601 timestamp of the most recent mailbox creation, or null |
| `lastStatus` | string\|null | no | Last operation status (created, already_exists, quota_reached, failed, needs_human) |
| `lastUpdatedAt` | string\|null | no | ISO 8601 timestamp of last status update |

### Notes

- The free trial quota varies by domain (currently 2 accounts for new trials; some legacy domains may still have 1). Do not hardcode the quota — always parse `TOTAL EMAIL ACCOUNTS X/Y` from the page.
- `mailboxes` is an array to support multi-mailbox quotas. `update_domain_status.sh` appends new addresses and deduplicates.
- After successful creation, `update_domain_status.sh` writes back `mailboxes`, `lastMailboxCreatedAt`, `lastStatus`, and `lastUpdatedAt`.
- Generated mailbox passwords are not persisted in `domains.json`. The caller must store the returned password securely if it needs to be reused later.
- The scheduler can skip a domain for a given `mailboxName` if `mailboxes` already contains `mailboxName@domain`. To determine whether the domain has remaining quota, the scheduler must either check `lastStatus == "quota_reached"` or invoke the skill in query mode.

### Example

```json
{
  "domains": {
    "visionate.net": {
      "accountId": "acct_hostclub_001",
      "mailboxes": ["sales@visionate.net"],
      "lastMailboxCreatedAt": "2026-02-15T10:30:00Z",
      "lastStatus": "created",
      "lastUpdatedAt": "2026-02-15T10:30:00Z"
    },
    "abc.com": {
      "accountId": "acct_hostclub_001",
      "mailboxes": [],
      "lastMailboxCreatedAt": null,
      "lastStatus": null,
      "lastUpdatedAt": null
    },
    "wavelengthpulsmk.com": {
      "accountId": "acct_hostclub_001",
      "mailboxes": ["contact@wavelengthpulsmk.com", "sales@wavelengthpulsmk.com"],
      "lastMailboxCreatedAt": "2026-03-01T14:22:00Z",
      "lastStatus": "quota_reached",
      "lastUpdatedAt": "2026-03-10T09:00:00Z"
    }
  }
}
```

## Password Encryption

### Encrypt a password

```bash
echo -n "your-password" | openssl enc -aes-256-cbc -a -pass "pass:$OPENCLAW_SECRET_KEY"
```

### Decrypt a password

```bash
echo "U2FsdGVkX1+abc123..." | openssl enc -aes-256-cbc -d -a -pass "pass:$OPENCLAW_SECRET_KEY"
```

The `OPENCLAW_SECRET_KEY` must be set as an environment variable. It should never appear in config files, code, or logs.

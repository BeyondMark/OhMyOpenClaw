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
| `browserProfile` | string | yes | OpenClaw browser profile name (lowercase, digits, hyphens) |

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
      "mailbox": "<email-address-or-null>",
      "mailboxCreatedAt": "<iso8601-or-null>",
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
| `mailbox` | string\|null | yes | Created mailbox address, or null if not yet created |
| `mailboxCreatedAt` | string\|null | yes | ISO 8601 creation timestamp, or null |
| `lastStatus` | string\|null | no | Last operation status (created, already_exists, quota_reached, failed, needs_human) |
| `lastUpdatedAt` | string\|null | no | ISO 8601 timestamp of last status update |

### Notes

- During free trial, each domain supports only 1 mailbox, so `mailbox` is a single value, not an array.
- After successful creation, `update_domain_status.sh` writes back `mailbox`, `mailboxCreatedAt`, `lastStatus`, and `lastUpdatedAt`.
- Generated mailbox passwords are not persisted in `domains.json`. The caller must store the returned password securely if it needs to be reused later.
- The scheduler can skip domains where `mailbox` is not null and `lastStatus` is `created` or `already_exists`.

### Example

```json
{
  "domains": {
    "visionate.net": {
      "accountId": "acct_hostclub_001",
      "mailbox": "sales@visionate.net",
      "mailboxCreatedAt": "2026-02-15T10:30:00Z",
      "lastStatus": "created",
      "lastUpdatedAt": "2026-02-15T10:30:00Z"
    },
    "abc.com": {
      "accountId": "acct_hostclub_001",
      "mailbox": null,
      "mailboxCreatedAt": null,
      "lastStatus": null,
      "lastUpdatedAt": null
    },
    "wavelengthpulsmk.com": {
      "accountId": "acct_hostclub_001",
      "mailbox": "contact@wavelengthpulsmk.com",
      "mailboxCreatedAt": "2026-02-10T08:00:00Z",
      "lastStatus": "already_exists",
      "lastUpdatedAt": "2026-03-01T14:22:00Z"
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

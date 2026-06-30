# [zsh-secret-guard](https://social.cavebatsoftware.com/articles/c645bbbe-0a92-45a0-b220-328d984ce414)

Prevents secrets from entering your zsh history, and cleans them out if they do.

## How it works

A `zshaddhistory` hook intercepts every command before it is written to `~/.zsh_history`. If the command matches a known secret pattern, the secret value is replaced with `<REDACTED>` and that sanitized form is saved to history instead. The command still executes, your history retains a record of what you ran, and the secret never touches disk.

## Installation

```zsh
git clone https://github.com/gdefayette/zsh-secret-guard.git
cd zsh-secret-guard
chmod +x install.zsh
./install.zsh
source ~/.zshrc
```

Verify it's running:

```zsh
zsg_status
```

**Requirements:** zsh, perl (5.10+)

## What it detects

| Category | Examples |
|---|---|
| Env var assignments | `export API_KEY=...`, `TOKEN=...`, `MY_PASSWORD=...` |
| AWS | `AKIA...` key IDs, `AWS_SECRET_ACCESS_KEY=` |
| Cloud credentials | GCP, Azure, Vault, Terraform `TF_VAR_*` |
| CLI flags | `--password`, `--token`, `--api-key`, `-p` |
| Auth headers | `curl -H "Authorization: Bearer ..."` |
| Database connection strings | `postgres://user:pass@host` |
| URLs with embedded credentials | `https://user:token@github.com` |
| Platform tokens | GitHub (`ghp_`), Stripe (`sk_live_`), Slack (`xoxb-`), Twilio |
| Long high-entropy strings | Hex ≥ 40 chars, base64 ≥ 32 chars after `=` |
| SSH private key headers | `-----BEGIN RSA PRIVATE KEY-----` |

## Commands

```zsh
history_audit        # preview how secret-matching lines would be redacted
history_scrub        # redact them in place (backs up ~/.zsh_history first)
zsg_status           # show configuration
```

## Configuration

Set these before sourcing the plugin in your `.zshrc`:

```zsh
ZSH_SECRET_GUARD_WARN=0                        # silence the "not saved" warning
ZSH_SECRET_GUARD_LOG=1                         # log blocked commands (redacted)
ZSH_SECRET_GUARD_LOG_FILE=~/.zsg.log           # log destination
```

## License

MIT © 2026 Grant DeFayette

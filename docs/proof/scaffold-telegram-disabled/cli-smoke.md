# Scaffold telegram disabled until token

## Bug (2026-07-25 Reflect E2E)

`new-agent` cloned Neo with `telegram.enabled: true` and claimed "telegram cleared" while only blanking `TELEGRAM_HOME_CHANNEL`. Gateway then exited:

`telegram: No bot token configured` (non-retryable startup conflict).

`boot-agent` reported: agent started but did not satisfy the Fleet runtime contract.

## Fix

After model block write, SuperHermes forces top-level `telegram.enabled: false`. Operator enables Telegram only after vault `SLUG__TELEGRAM_BOT_TOKEN` + grant.

## Verify

```bash
# dry-run or live scaffold
rg -n "enabled: false" /path/to/profile/config.yaml   # under telegram:
# gateway starts with platforms {} and no missing_credentials fatal
```

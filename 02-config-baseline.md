# Config Baseline

This page defines the redacted settings a serious Hermes profile should document. It is not a raw config dump.

## Runtime

Record Hermes version, active profile name, profile path, provider/model, gateway status, working directory, and runtime version where relevant.

## Agent loop

Recommended shape for high-agency executive/operator profiles:

- High enough `max_turns` for multi-step tasks.
- Long enough gateway timeout for complex work.
- Tool-use enforcement enabled or automatic.
- Compression enabled with conservative protection for recent context.

## Terminal

Document backend, cwd, default timeout, and persistent shell setting.

## Memory

Document provider, whether memory/user profile are enabled, and character limits for bootstrap memory.

## Voice

Document STT provider, TTS provider, output format expectation, and platform-specific delivery rules. For the operator-facing Telegram briefings, MP3 is the standard. OGG is not acceptable for final delivery.

## Approvals and security

Document approval mode, cron approval mode, private URL policy, secret redaction policy, PII redaction policy, and destructive-action policy.

Profile config is never the whole safety story. Some assistants, such as Jeeves, have domain-specific iron laws stricter than Hermes config.

## Redaction standard

Before putting config into docs, replace API keys, tokens, OAuth refresh material, cookies, private keys, passwords, and connection strings with `[REDACTED]`. Keep non-secret architecture values such as provider names, model names, paths, timeouts, and booleans where useful.

# Cron and Guardrails

Cron jobs make a Hermes profile durable. They also make mistakes durable. Treat them accordingly.

## Cron classes

- Briefing crons.
- Memory crons.
- Promise/action crons.
- Watchdog crons.
- Script-only deterministic crons.

## Required metadata

Each cron should document name, schedule, profile, workdir, skills, script, delivery target, approval boundary, expected output, and failure behavior.

## Approval boundaries

Cron jobs must not autonomously send real-world email/messages, post publicly, buy anything, change credentials/security/permissions, delete important work, or mutate calendar/Drive/docs unless explicitly approved.

They may draft, summarize, inspect, prepare, and recommend.

## Prompt shape

Good cron prompts are self-contained. Future runs do not inherit the original chat context.

Include agent role, source systems, exact allowed actions, forbidden actions, output format, and verification requirements.

## Verification

Do not assume a cron works because it exists. Verify job status, schedule, workdir, scripts, last run output, and side effects.

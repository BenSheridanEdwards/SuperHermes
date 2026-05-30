# Executive Summary

SuperHermes is the fleet template for building serious Hermes agents: executive operators, engineering operators, research operators, and specialist assistants that need memory, tools, scheduled action, and approval discipline.

## Design principle

Do not clone a personality. Clone an operating system.

A mature Hermes profile is made of separable layers:

1. **Runtime** — Hermes version, provider/model, gateway, terminal, toolsets.
2. **Profile isolation** — config, env, sessions, memories, skills, scripts, crons.
3. **Memory** — bootstrap context, Honcho, GBrain, consolidation, hygiene.
4. **Procedure** — skills and reference docs.
5. **Durable automation** — cron jobs, scripts, Kanban/watchdogs.
6. **Delivery** — Telegram, voice, documents, Google Workspace, etc.
7. **Safety** — explicit approval gates and no-secret handling.
8. **Maintenance** — curator, profile housekeeping, health checks.

## Non-negotiables

- Never copy credentials, tokens, refresh tokens, cookies, OAuth files, private keys, or connection strings into this template.
- Never treat a live profile's accumulated workspace folders as template material.
- Never claim GBrain is working because markdown files exist. Verify runtime, stats, search/query, embeddings, and MCP.
- Never bulk-import deprecated memory stores such as LocalMem. Use them only as evidence for curated migration.
- Never let scheduled jobs bypass human approval for real-world sends, posts, purchases, credential/security changes, or destructive changes.

## Jeeves reference state

Jeeves is the first worked example:

- Hermes Agent `0.15.0`.
- Profile `jeeves`.
- Model `gpt-5.5` via `openai-codex`.
- Honcho active.
- GBrain active as semantic/wiki brain (v0.41 pglite, profile-isolated).
- GBrain MCP registered via the agent's **own** `<agent>/.local/bin/gbrain`
  wrapper — never a shared one (see non-negotiables and `05-gbrain-setup`). A
  cross-agent shared wrapper was the original split-brain/dependency failure the
  template exists to prevent.
- GBrain stats at an early capture: 14 pages, 19 chunks, 19 embedded, 100% embedding coverage.
- Daily memory hygiene and GBrain consolidation crons active.
- Google Workspace, meeting, Kanban, voice, and delivery modules present.

Jeeves is powerful, but not minimal. This template extracts the architecture, not the clutter.

# Building agents — layout, config, tools, scaffolding

How an agent is structured on disk, the config posture it ships with, how its
toolsets are scoped by risk, and how `bin/new-agent` renders the whole thing in
one command. For the *why* behind these choices see
[ARCHITECTURE.md](../ARCHITECTURE.md); for the narrative overview see the
[README](../README.md).

---

## Profile layout

A strong agent is understandable at a glance:

```text
$AGENTS_ROOT/<Agent>/                  ← the agent's own git repo root
├── .hermes/profiles/<profile>/
│   ├── config.yaml                    settings (redact before sharing)
│   ├── .env                           secret KEYS (never templated raw)
│   ├── auth.json                      auth/OAuth (never templated raw)
│   ├── memories/{MEMORY,USER}.md      bootstrap memory
│   ├── skills/  scripts/  cron/  sessions/  logs/
│   └── home/.gbrain/                  canonical GBrain store
├── .home/                            profile/sandbox home
├── workspace/                        work products, repos, scratch
└── vault/brain/                      curated markdown indexed by GBrain
```

**Separation rules**

- `config.yaml` holds settings; redact before sharing. `.env`, `auth.json`,
  browser profiles, cookies, tokens, and keychains are **never** template material.
- `workspace/` is work artifacts and can grow huge — template the *policy*, not the
  contents.
- `vault/brain/` is curated long-term knowledge; raw transcripts and large evidence
  dumps live outside `brain/` unless intentionally indexed.
- `scripts/` splits into core template scripts and optional module scripts.
- Every `cron/` job carries a stated approval boundary.

**Profile-safe paths.** Use profile-local or explicit agent paths; never depend on
the default Hermes profile. Prefer
`$AGENTS_ROOT/<Agent>/.hermes/profiles/<profile>/…` over `~/.hermes/…`.

**Shared components** live under `$AGENTS_ROOT/Shared/` (shared skills, CLI
wrappers, architecture references, CI). Never make a profile depend on an
undocumented shared binary — document the command, version, and verification output.

---

## Config baseline

The redacted settings a serious profile should document — not a raw config dump.
Exact starting values ship in [`templates/config.redacted.yaml`](../templates/config.redacted.yaml).

- **Runtime** — Hermes version, active profile name + path, provider/model, gateway
  status, working directory.
- **Agent loop** — high enough `max_turns` for multi-step work, a long gateway
  timeout, tool-use enforcement on/auto, and compression enabled with conservative
  protection for recent context.
- **Terminal** — backend, cwd, default timeout, persistent-shell setting.
- **Memory** — provider, whether memory/user-profile are enabled, bootstrap char
  limits.
- **Voice** — STT/TTS providers and output format. For operator-facing Telegram
  briefings, **MP3 is the standard; OGG is not acceptable for final delivery.**
- **Approvals & security** — approval mode, cron approval mode, private-URL policy,
  secret/PII redaction policy, destructive-action policy. Config is never the whole
  safety story — some agents (e.g. Jeeves) carry domain-specific iron laws stricter
  than Hermes config.

**Redaction standard.** Before config goes into any doc, replace API keys, tokens,
OAuth refresh material, cookies, private keys, passwords, and connection strings
with `[REDACTED]`. Keep non-secret architecture values (provider/model names, paths,
timeouts, booleans).

---

## Toolsets and permissions

Document toolsets by **risk category**, not just availability.

- **Common core** — terminal, file, code execution, web, browser, vision, skills,
  memory, session search, todo, delegation, cronjob, messaging, TTS.
- **Optional** (enable only on real need) — image/video generation, Home Assistant,
  Spotify, social media, platform admin.
- **MCP** — document each server: name, command/URL, transport, auth mode, enabled
  tool selection, test result, reload caveat. For GBrain the done-bar is: MCP
  connects, tools discovered, stats/search/query work **against the intended brain**.

**Risk model**

| Tier | Examples | Gate |
|------|----------|------|
| Read-only | search, read, inspect state | none |
| Local write | write docs, patch files, create artifacts | none |
| External side effects | send messages/email, post, change calendar/Drive/Docs, open PRs | **explicit approval** |
| Sensitive/destructive | credentials, permissions, purchases, deletion, security posture | **explicit approval** |

**Messaging boundary.** Even with messaging enabled, the agent must not send
real-world messages without explicit approval. Drafts and recommendations are safe;
sending is not.

---

## The `new-agent` scaffolder

`bin/new-agent` spins up a complete agent from one command, rendering the full
anatomy above — correct from day one.

```sh
bin/new-agent                                  # fully interactive
bin/new-agent --name Sky --camp codewalnut
bin/new-agent --name Sky --no-start            # scaffold files only
bin/new-agent --name Sky --dry-run             # render to temp, zero side effects
```

Prompts: **name** (PascalCase) · **camp** (`personal`|`codewalnut` → workspace
suffix) · **model** (primary provider/model, up to two fallbacks, round-robin) ·
proceed confirm.

**The 6 phases**

1. **Directory skeleton** — profile, sandbox, `.home`/`.gbrain`, caches,
   `vault/brain`.
2. **Sandbox** — rendered from `templates/sandbox.sb.template` (town-square model),
   compile-checked.
3. **Hermes profile** — `config.yaml` (bundled generic template, or cloned from
   `REF_AGENT`; paths repointed, Telegram channel cleared, skills → `Shared/skills`,
   gbrain → the agent's own `.local/bin/gbrain`), SOUL stub,
   MEMORY/USER, the two baseline crons (**memory-maintenance** and **identity
   git-sync**) + scripts, and the **normalised default-deny `.gitignore`**.
4. **GBrain** — own profile-isolated **v0.41** runtime + wrapper + **Postgres**
   `config.json` (768-dim, `/v1` Ollama); vault skeleton (start phase installs +
   imports + embeds).
5. **launchd plists** — gateway (sandbox-wrapped), lint-checked.
6. **Permissions + git** — dirs `750`, then `git init` the agent's **own repo** at
   its root + initial commit. Default-deny ignore means only durable identity is
   versioned. Then **services** (unless `--no-start`) — GBrain install + vault
   import + embed, health-gate, register + kickstart launchd.
   The run finishes by calling [`verify-agents`](../README.md#verify--test) on the new
   agent.

**Still manual by design** (scaffolded, then paused for values): **credentials**
(`auth.json`) and the **SOUL/persona** (only a stub is written). `REF_AGENT` env
var picks the reference agent for `config.yaml`/`.env` (default: bundled
templates).

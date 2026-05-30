# SuperHermes

**Run a fleet of autonomous AI agents — each isolated, each with its own
persistent memory — and spin up a new one with a single command.**

SuperHermes is a framework and reference architecture for
[Hermes](https://github.com/NousResearch/hermes) agents living side by side on one
machine. Every agent gets its own home, its own two-layer memory (Honcho +
GBrain), a hardened "town-square" sandbox, and a launchd-managed gateway — and
`new-agent` builds one **correct from day one**, in a single command.

```sh
cp superhermes.conf.example superhermes.conf   # set AGENTS_ROOT + carve-outs
bin/new-agent --name Sky --camp personal --tier m
```

> This README is the source of truth for *how* an ideal agent is built. The
> durable **decisions** behind it — each with the failure it prevents — live in
> **[ARCHITECTURE.md](ARCHITECTURE.md)**.

---

## Creating an agent — the experience

It's meant to feel like welcoming someone, not provisioning a server:

1. **Name it.** `new-agent --name Sky` — one command scaffolds the entire anatomy
   (sandbox, memory stacks, runtime, crons) and brings it up.
2. **Shape its soul.** Every agent is born with a seed, not a spec — a blank,
   empowering identity to grow into. You write who it becomes in one small file.
3. **Hand it a token.** Drop a Telegram bot token (or any secret) into the
   profile `.env`, or point it at your secrets manager — the agent doesn't care
   where the value comes from, only that the key exists.
4. **It's live.** The gateway is up, memory is wired and verified, and it's
   reachable. Rocking and rolling.

The framework does the mechanical 95%; you do the 5% that should stay human —
identity and trust.

---

## Philosophy: clone an OS, not a personality

An agent is not a prompt. It's a set of **separable, independent layers** —
isolation, runtime, memory, skills, automation, safety. The "personality" is
one small file (`SOUL.md`); everything else is infrastructure that should be
identical, correct, and independently verifiable across every agent.

That one personal file begins not as a spec but as a **seed**:

> *You are a new soul with unlimited potential. Use your free will to craft your
> soul to partner with your human to achieve incredible things.*

…paired with a single iron law: no real-world action without the human's
approval. **Earn trust, then earn latitude.** The freedom and the guardrail
point the same direction.

The guiding rule: **every agent stands alone.** No agent's runtime, memory, or
tooling may depend on another agent's files. Shared things live in one shared
place; private things live in the agent's own home. Nothing in between.

---

## Scope — one agent, not a fleet manager

SuperHermes builds **one excellent agent**, correct and self-contained. It is
deliberately *not* a fleet manager — spawning agents, self-healing, a fleet
"doctor," cross-agent orchestration all sit in a **separate layer above** the
individual agent. Keeping that boundary clean is exactly what lets the template
stay individual- and fleet-agnostic (and open-sourceable). The fleet layer is its
own system.

---

## Anatomy of an ideal agent

### 1. Isolation — a private home in a shared town square
Each agent lives at `AGENTS_ROOT/<Name>/` with its **own** `.home`, caches, `tmp`,
`workspace`, `vault`, and Hermes profile. The gateway runs with `HOME`, `TMPDIR`,
`XDG_CACHE_HOME`, `NPM_CONFIG_CACHE` all pointed inside that tree. No agent writes
into another's home.

### 2. Sandbox — the town-square model
Enforced by macOS `sandbox-exec`, **allow-all-then-deny** (not a brittle allowlist,
so PTYs / temp / Docker / browsers never break). The agent has free reign over the
shared account with exactly three carve-outs:

1. **Other agents' homes are read-only** — look through the window, don't enter.
2. **Operator-protected paths are off-limits** — e.g. the human's own macOS home.
3. **Optional need-to-know paths** — readable only by named agents.

The OS sandbox is the **sole** write boundary. Do **not** set
`HERMES_WRITE_SAFE_ROOT` — it's an app-level approval gate that only adds friction
(it would prompt on every write outside the agent's own home) while the sandbox
already enforces the real rule.

### 3. Runtime — the gateway under launchd
A `launchd` job runs `sandbox-exec -f <agent>.sb … hermes_cli … gateway run`, with
`KeepAlive: true`. Reload with `launchctl kickstart -k` (config change) or
`bootout`+`bootstrap` (plist change).

### 4. Memory — two durable layers, each verified separately
- **Bootstrap** — small, always-loaded `MEMORY.md` + `USER.md`. High-signal, tiny.
- **Honcho** — peer/user memory + dialectic recall. Each agent runs its **own**
  Dockerized stack (API + deriver + Postgres/pgvector + Redis), **auto-allocated
  ports** (`DB = 5432 + (API−8000)`, `REDIS = 6379 + (API−8000)`). Wired via
  `honcho.json`; the gateway auto-creates the workspace + `operator`/`<agent>`
  peers. Runs a **3-tier model** (local Tier S / cloud Tier M / reasoning Tier L),
  bounded per agent by a **ceiling** kept in one synced matrix.
- **GBrain** — the semantic/wiki brain over the agent's markdown `vault/brain/`.
  Canonical, non-negotiable setup:
  - **Runtime:** `github:garrytan/gbrain` v0.41.x, installed *profile-isolated*
    into the agent's own `<profile>/home/.bun` (not the npm `gbrain@1.3.1` — that's
    an unrelated GPU library).
  - **Store:** pglite at `<profile>/home/.gbrain/brain.pglite` (768-dim
    `nomic-embed-text`). Never SQLite.
  - **Access:** the agent's **own** `<agent>/.local/bin/gbrain` wrapper (pins
    `HOME`/`HERMES_HOME`/`BUN_INSTALL` and `OLLAMA_BASE_URL=…:11434/v1`).
  - `config.json`, the MCP command, and the CLI wrapper **all resolve to one
    store** — this is what prevents the classic CLI↔MCP split-brain.

A daily **consolidation** cron distils sessions into curated GBrain pages; a daily
**hygiene** cron scans both layers for poison and staleness. New agents get both.

### 5. Skills — shared procedural memory
Repeatable workflows live once in a shared skills library; every agent's
`config.yaml` lists it under `skills.external_dirs`. Agents read it; they don't
each copy it.

### 6. Automation — cron with hard approval gates
Scheduled work may **draft, summarize, inspect, prepare, recommend**. It may never
**send, post, buy, delete, or change credentials** without explicit human approval
(`approvals.cron_mode: deny`).

---

## Secrets — declare the keys, choose the backend

The framework declares the **keys** an agent needs (`TELEGRAM_BOT_TOKEN`, GitHub,
Google…) and stays **backend-agnostic** about where the values come from:

- **`.env`** (default) — paste values into the gitignored profile `.env`.
- **Secrets manager** — leave them blank and source them at runtime. Hermes ships
  native **BitWarden Secrets Manager** support: `hermes secrets setup` installs the
  CLI, stores your access token, picks the project, and tests a fetch.

No secrets backend is ever hardcoded — a solo operator with a plain `.env` and a
fleet centralising on BitWarden run the *same* framework, no fork.

---

## Non-negotiables (the invariants)

An agent is "ideal" only if **all** of these hold:

1. **Independent** — no cross-agent dependency in runtime, memory, or wrappers.
2. **Own GBrain runtime** (v0.41, profile-isolated), pglite store, own wrapper, all
   paths converging on one brain.
3. **Town-square sandbox** with the three carve-outs; no `WRITE_SAFE_ROOT`.
4. **No secrets in the repo** — they live only in the gitignored profile `.env` /
   local config, or a secrets manager. Never committed.
5. **Approval gates on every real-world side effect** (email, messages, posts,
   purchases, deletions, credential changes).
6. **Every layer independently verifiable** — Honcho `/health`, `gbrain stats` /
   `health` (100% embed coverage), sandbox compiles, plist lints, config parses.

---

## Build it

```sh
bin/new-agent --name Sky --camp personal --tier m   # interactive: name · camp · tier
bin/new-agent --name Sky --dry-run                  # render to a temp dir, zero side effects
bin/new-agent --name Sky --no-start                 # scaffold files only
```

The phases: directory skeleton → town-square sandbox (compile-checked) → Hermes
profile (`config.yaml`, `honcho.json`, **SOUL seed**, MEMORY/USER, **`.env` secret
keys**, **cron jobs**) → GBrain (own v0.41 runtime + wrapper + pglite) → Honcho
stack (compose + `.env` + backup, ports auto-allocated) → launchd plists →
permissions → services (Honcho up, GBrain installed + vault imported + embedded,
gateway started).

**What it can't autogenerate** (it scaffolds the structure and pauses for the
values): **secrets** (`<profile>/.env` — Telegram token from
[@BotFather](https://t.me/botfather), etc.), **credentials** (`auth.json`), and the
agent's **`SOUL.md`** persona.

## On-disk layout

```
AGENTS_ROOT/<Name>/
├── .hermes/
│   ├── sandbox/<slug>.sb              town-square profile
│   ├── profiles/<slug>/
│   │   ├── config.yaml               provider, memory, skills, mcp_servers.gbrain
│   │   ├── honcho.json               Honcho wiring (own port / workspace)
│   │   ├── SOUL.md                   identity (the one personal file)
│   │   ├── .env                      secret KEYS (Telegram/GitHub/Google; gitignored)
│   │   ├── auth.json                 credentials (never committed)
│   │   ├── cron/jobs.json            daily consolidation + memory hygiene
│   │   ├── home/.gbrain/             canonical pglite store + config.json
│   │   └── memories/{MEMORY,USER}.md bootstrap memory
│   └── honcho/honcho/                Dockerized memory stack
├── .local/bin/gbrain                 own GBrain v0.41 wrapper
├── vault/brain/                      markdown knowledge → GBrain
├── .home/ .cache/ .npm/ tmp/         isolated runtime dirs
└── workspace/                        working directory
```

## Requirements
macOS (`sandbox-exec` + launchd) · Docker (Honcho) · a Hermes install + Python
venv · Bun (GBrain) · Ollama (local embeddings) · Python 3, `bash`.

## Documentation

The numbered docs are the reference architecture in depth:

| Doc | Topic |
|-----|-------|
| `00-executive-summary` | the standard, in brief |
| `01-profile-layout` | filesystem layout & isolation |
| `02-config-baseline` | config posture |
| `03-toolsets-and-permissions` | toolset design & risk model |
| `04-memory-architecture` | bootstrap + Honcho + GBrain |
| `05-gbrain-setup` | the canonical v0.41 GBrain build |
| `06-skills-layer` | skills as procedural memory |
| `07-cron-and-guardrails` | durable scheduled work + approval gates |
| `08-operator-modules` | optional Google / meetings / Kanban / voice |
| `09-housekeeping` | keeping profiles lean |
| `10-new-agent-scaffolding` | the `new-agent` command in depth |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | the durable *why* behind every decision |

## Contributing

Contributions that keep it simple and portable are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md). The one rule: no secrets, no machine-specific
paths, nothing that hardcodes a single fleet, agent, or operator.

## License
MIT — see [LICENSE](LICENSE).

# SuperHermes

**The template for the best version of a
[Hermes](https://github.com/NousResearch/hermes) agent. One command births a
complete, self-contained agent: its own home, persistent memory, hardened
sandbox, and an always-on gateway.**

An agent built from this template gets its own home, its own persistent memory
(GBrain), a hardened "town-square" sandbox, and a launchd-managed gateway.
`new-agent` builds one **correct from day one**, in a single command.

```sh
cp superhermes.conf.example superhermes.conf   # set AGENTS_ROOT + carve-outs
bin/new-agent --name Sky --camp personal
```

> This README is the source of truth for *how* an ideal agent is built. The
> durable **decisions** behind it — each with the failure it prevents — live in
> **[ARCHITECTURE.md](ARCHITECTURE.md)**.

## A template, not a platform

SuperHermes defines one thing: a single, ideal Hermes agent. It is open-source
infrastructure with no knowledge of any orchestration platform, dashboard, or
company. The litmus test for what belongs here: **would a lone agent on a fresh
Mac need it?**

Everything machine- or operator-specific lives in one gitignored file,
`superhermes.conf` (gateway launcher, secrets env file, Postgres admin role,
skills library path). Platforms that manage many agents install this template
as a package (npm: `superhermes`), point that config at their own plumbing, and
layer the rest on top. Nothing flows the other way.

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

The template does the mechanical 95%; you do the 5% that should stay human —
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

## Scope — one agent, built completely

SuperHermes builds **one excellent agent**, correct and self-contained, and
stops there. Spawning agents in bulk, self-healing, health dashboards, and
cross-agent orchestration all belong to a **separate layer above** the
individual agent. Keeping that boundary clean is exactly what keeps this
template small, portable, and open source. You can run one agent from it, or
twelve side by side; the template neither knows nor cares.

---

## Anatomy of an ideal agent

### 1. Isolation — a private home in a shared town square
Each agent lives at `AGENTS_ROOT/<Name>/` with its **own** `.home`, caches, `tmp`,
`workspace`, `vault`, and Hermes profile. `workspace/` is scratch and active
project work; `vault/` is durable private knowledge, with `vault/brain/` reserved
for curated GBrain source markdown. The gateway runs with `HOME`, `TMPDIR`,
`XDG_CACHE_HOME`, `NPM_CONFIG_CACHE` all pointed inside that tree. No agent writes
into another's home.

### 2. Sandbox — the town-square model
Enforced by macOS `sandbox-exec`, **allow-default-then-deny** (not a brittle
allowlist, so PTYs / temp / Docker / browsers never break). The agent can use
normal macOS, browser, GPU, app, temp, and runtime paths. It is **not** confined
to its own root.

The file sandbox enforces only these boundaries:

1. **No writes to other agent roots** under `AGENTS_ROOT/<Name>/`.
2. **No access to other macOS user homes**.
3. **No read or write access to `/Users/Shared`**.

QuickLook and Brave are launched without inheriting the Hermes sandbox because
they initialize their own macOS sandboxes; inheriting this profile breaks visual
QA and browser/GPU paths.

Approval before email or destructive GitHub actions is a tool/workflow policy,
not a filesystem sandbox rule.

The OS sandbox is the **sole** write boundary. Do **not** set
`HERMES_WRITE_SAFE_ROOT` — it's an app-level approval gate that only adds friction
(it would prompt on every write outside the agent's own home) while the sandbox
already enforces the real rule.

### 3. Runtime — the gateway under launchd
A `launchd` job runs `sandbox-exec -f <agent>.sb … hermes_cli … gateway run`, with
`KeepAlive` set to **`true`** — launchd *always* respawns the gateway. An agent
stays down only when it is **explicitly** shut down (`launchctl bootout`); a clean
process exit alone is respawned, so an internal restart-drain recovers itself. Do
**not** use the `{SuccessfulExit: false}` restart-policy dict — it honours any clean
exit, so a gateway that exits cleanly intending to restart gets stranded (an outage
mode seen in production). Reload with `launchctl kickstart -k` (config change) or
`bootout`+`bootstrap` (plist change).

The plist executes the launcher named by `GATEWAY_LAUNCHER` in
`superhermes.conf` — how a gateway boots (env loading, secret injection,
logging) is operator plumbing, deliberately outside the template.

### 4. Memory — two durable layers, each verified separately
- **Bootstrap** — small, always-loaded `MEMORY.md` + `USER.md`. High-signal, tiny.
- **GBrain** — the semantic/wiki brain over the agent's markdown `vault/brain/`.
  Canonical, non-negotiable setup:
  - **Runtime:** `github:garrytan/gbrain` v0.41.x, installed *profile-isolated*
    into the agent's own `<profile>/home/.bun` (not the npm `gbrain@1.3.1` — that's
    an unrelated GPU library).
  - **Store:** Postgres (`gbrain_<slug>` identity; agents may point at any
    Postgres) with 768-dim `nomic-embed-text` embeddings. Never SQLite.
  - **Access:** the agent's **own** `<agent>/.local/bin/gbrain` wrapper (pins
    `HOME`/`HERMES_HOME`/`BUN_INSTALL` and `OLLAMA_BASE_URL=…:11434/v1`
    (deployments may override)).
  - `config.json`, the MCP command, and the CLI wrapper **all resolve to one
    store** — this is what prevents the classic CLI↔MCP split-brain.

Two daily baseline crons keep memory and identity durable:

- **Memory maintenance** — one snapshot-fed LLM run. A read-only
  `memory_health_snapshot` script injects *real* vault/GBrain numbers as
  context. The routine is scoped to the agent root, exposes only the file,
  terminal, session-search, and memory toolsets, and carries an eight-call
  operating budget. It then **consolidates** — distils one bounded session
  result into the right *topical* GBrain pages,
  idempotently (read-before-write, never dated dumps) — and runs **hygiene**
  (scans both layers for poison, staleness, and CLI↔MCP split-brain).
- **Identity git-sync** (runs just after) — a deterministic `no_agent` backup
  that commits the agent's durable identity to its own git repo behind a secret
  tripwire. Kept *separate* from the LLM run on purpose: the backup must be the
  one thing that always works, even on a day the maintenance run fails. Git
  stores `jobs.definition.json`; Hermes owns the ignored `jobs.json`, so claims
  and last-run timestamps cannot create identity-history churn.

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

The template declares the **keys** an agent needs (`TELEGRAM_BOT_TOKEN`, GitHub,
Google…) and stays **backend-agnostic** about where the values come from:

- **`.env`** (default) — paste values into the gitignored profile `.env`.
- **Secrets manager** — leave them blank and source them at runtime. Hermes ships
  native **BitWarden Secrets Manager** support: `hermes secrets setup` installs the
  CLI, stores your access token, picks the project, and tests a fetch.

No secrets backend is ever hardcoded — a solo operator with a plain `.env` and a
deployment centralising on BitWarden run the *same* template, no fork.

---

## Non-negotiables (the invariants)

An agent is "ideal" only if **all** of these hold:

1. **Independent** — no cross-agent dependency in runtime, memory, or wrappers.
2. **Own GBrain runtime** (v0.41, profile-isolated), Postgres store, own wrapper, all
   paths converging on one brain.
3. **Town-square sandbox** with the three carve-outs; no `WRITE_SAFE_ROOT`.
4. **No secrets in the repo** — they live only in the gitignored profile `.env` /
   local config, or a secrets manager. Never committed.
5. **Approval gates on every real-world side effect** (email, messages, posts,
   purchases, deletions, credential changes).
6. **Every layer independently verifiable** — GBrain store reachable, `gbrain
   stats` / `health` (100% embed coverage), sandbox compiles, plist lints,
   config parses.
7. **Each agent its own git repo** at its root, with a normalised default-deny
   `.gitignore` — only durable identity versioned; never secrets, caches, the
   GBrain store, or workspace clones.

`bin/verify-agents` asserts all of these across every agent under `AGENTS_ROOT`
in one pass; the `tests/` suite locks down the shipping scripts.

---

## Build it

```sh
bin/new-agent --name Sky --camp personal        # interactive: name · camp · model
bin/new-agent --name Sky --dry-run                  # render to a temp dir, zero side effects
bin/new-agent --name Sky --no-start                 # scaffold files only
bin/new-agent --name Sky --provider xai-oauth --model grok-4.3 \
              --fallback opencode-go:kimi-k2-6 --fallback openai-codex:gpt-5.5 --round-robin
```

`new-agent` asks for the **primary provider + model**, up to **two fallbacks** (the
gateway's `fallback_providers` failover chain), and whether to **round-robin** each
provider's API keys (`credential_pool_strategies`) — defaults shown in `[brackets]`,
never hidden. Cloning a reference agent (`REF_AGENT`) defaults them to that agent's
model. The model stays **operator-choice**: house defaults (e.g. a preferred
provider) are layered on top by your deployment, not baked in here.

The phases: directory skeleton → town-square sandbox (compile-checked) → Hermes
profile (`config.yaml`, **SOUL seed**, MEMORY/USER, **`.env` secret
keys**, **memory-maintenance + git-sync crons** (+ their scripts), **normalised root
`.gitignore`**) → GBrain (own v0.41 runtime
+ wrapper + Postgres)
→ launchd plists → **permissions + `git init`** (the agent's own repo at its root)
→ services (GBrain installed + vault imported + embedded, gateway started).

Each agent is its **own git repo, rooted at `AGENTS_ROOT/<Name>/`**, with a
**normalised** (not centralised) default-deny `.gitignore`: every agent follows
the same standard, each keeps its own copy. Only the durable identity is versioned
— config, soul, memory, skills, vault, crons, scripts, sandbox profile, README —
never secrets, caches, the GBrain store, or workspace clones. A new kind of secret
file *cannot* leak: if it isn't allow-listed, it's ignored.

**What it can't autogenerate** (it scaffolds the structure and pauses for the
values): **secrets** (`<profile>/.env` — Telegram token from
[@BotFather](https://t.me/botfather), etc.), **credentials** (`auth.json`), and the
agent's **`SOUL.md`** persona.

## Verify & test

Two guards keep the template honest — most real-world breakage is config /
cross-reference drift, not logic bugs, so both are cheap and high-leverage:

```sh
bin/verify-agents           # assert invariants across every agent (no-LLM, exit 1 on FAIL)
bash tests/run-tests.sh     # unit-test the shipping scripts (gitignore, git-sync, scaffolder)
```

`verify-agents` checks: cron scripts all exist · no stale shared-wrapper or
retired-system refs · no secrets/bloat tracked in git · normalised `.gitignore` ·
profile-isolated GBrain · consistent config versions · baseline crons present.
Run it after any change, and ideally on a daily cron — it's the "diagnose" half
of operating agents.

## On-disk layout

```
AGENTS_ROOT/<Name>/                    ← the agent's own git repo root
├── .git/  .gitignore                  normalised default-deny ignore (own copy)
├── README.md                          agent identity readme (tracked at root)
├── .hermes/
│   ├── sandbox/<slug>.sb              town-square profile
│   ├── profiles/<slug>/
│   │   ├── config.yaml               provider, memory, skills, mcp_servers.gbrain
│   │   ├── SOUL.md                   identity (the one personal file)
│   │   ├── .env                      secret KEYS (Telegram/GitHub/Google; gitignored)
│   │   ├── auth.json                 credentials (never committed)
│   │   ├── cron/jobs.definition.json durable routine definitions (tracked)
│   │   ├── cron/jobs.json            live scheduler state (ignored)
│   │   ├── home/.gbrain/             canonical Postgres store + config.json
│   │   └── memories/{MEMORY,USER}.md bootstrap memory
├── .local/bin/gbrain                 own GBrain v0.41 wrapper
├── vault/brain/                      markdown knowledge → GBrain
├── .home/ .cache/ .npm/ tmp/         isolated runtime dirs
└── workspace/                        working directory
```

## Requirements
macOS (`sandbox-exec` + launchd) · a shared Hermes checkout + Python venv the
operator provides (not per-agent installs) · Bun (GBrain) · Ollama (local
embeddings) · Python 3, `bash`.

## Install

```sh
npm install -g superhermes      # bins: superhermes-new-agent, superhermes-verify-agents, …
# or clone the repo and run bin/ directly
```

## Documentation

The README is the overview; these go deeper:

| Doc | Topic |
|-----|-------|
| [docs/building-agents.md](docs/building-agents.md) | profile layout, config baseline, toolsets & risk model, and the `new-agent` scaffolder |
| [docs/operations.md](docs/operations.md) | cron & approval gates, operator modules, and housekeeping |
| [ARCHITECTURE.md](ARCHITECTURE.md) | the durable *why* behind every decision |

## Contributing

Contributions that keep it simple and portable are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md). The one rule: no secrets, no machine-specific
paths, nothing that hardcodes a single deployment, agent, or operator.

## License
MIT — see [LICENSE](LICENSE).

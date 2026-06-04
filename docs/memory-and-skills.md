# Memory and skills

The layered memory system every agent runs, the canonical GBrain build, and how
skills work as shared procedural memory. For the *why* see
[ARCHITECTURE.md](../ARCHITECTURE.md) (decisions 4–6).

---

## Memory architecture

Four layers, each with one job — don't duplicate facts across them.

### Layer 1 — Bootstrap (`MEMORY.md` + `USER.md`)
Small, high-signal, always loaded. Declarative facts only. Do **not** store task
progress, PR numbers, commit SHAs, temporary TODOs, or anything likely stale within
a week.

### Layer 2 — Honcho
The peer/user learning layer: user preferences, communication style, stable identity
facts, raw observations, dialectic reasoning about the user. Don't blindly duplicate
Honcho into GBrain — it can hold dream/candidate material that needs consolidation.

Each agent runs its **own** Dockerized stack — four services: `api`, `deriver`
(Deriver + Summarizer + Dreamer), `database` (Postgres/pgvector), `redis`. Ports are
**auto-allocated** so stacks never clash: `DB = 5432 + (API−8000)`,
`REDIS = 6379 + (API−8000)`. Embedding dimension is locked identical fleet-wide
(e.g. 768). The gateway wires in via `honcho.json` (`baseUrl`, `workspace`, `aiPeer`,
`peerName`) and auto-creates the workspace + `operator`/`<agent>` peers on first
connect; only identity-grounding messages are seeded manually.

**Three-tier model** (cost/latency by workload):

| Tier | Workloads | Where |
|------|-----------|-------|
| **S** always-on | Deriver, Summary, Dialectic minimal/low | local (small model) |
| **M** on-demand | Dialectic medium/high | cloud, fast |
| **L** on-demand + nightly | Dialectic max + Dreams | cloud, deepest reasoning |

Each agent has a **ceiling** bounding how far it climbs (High → `max`/dreams on
Tier-L; Medium → dialectic clamps to Tier-M; Low → dialectic stays local). Ceilings
live in **one matrix** synced to every stack's `.env` — never hand-edited per agent.
Dream cadence is per agent.

### Layer 3 — GBrain
The semantic/wiki brain over curated markdown in `vault/brain/`: project context,
people/company pages, technical notes, reusable guides, consolidation notes,
source-linked facts and decisions. It's not just a folder — it has a runtime store,
index, embeddings, and MCP tools (see below).

### Layer 4 — Maintenance (consolidation + hygiene)
A mature profile runs **one daily memory-maintenance cron** doing both jobs in a
single snapshot-fed LLM run. A small read-only `memory_health_snapshot` script
gathers *real* vault/GBrain/Honcho numbers via the agent's **own** wrapper and
injects them as context, so the run works from ground truth. It then **consolidates**
(distils recent sessions + Honcho's durable distillate into the right topical GBrain
pages, idempotently — read-before-write, never dated dumps) and runs **hygiene**
(scans both layers for poison, staleness, identity drift, broken retrieval,
duplicate/conflicting memory, CLI↔MCP split-brain). One job, not two, shares the
snapshot and halves token cost. It's scheduled just before the nightly identity
git-sync so the backup captures the new pages — and the deterministic git-sync stays
a **separate** `no_agent` job so the backup runs even if the LLM run fails.

> LocalMem is deprecated/rescue-only. Treat old exports as evidence for curated
> migration, not active memory.

---

## GBrain setup (canonical v0.41, profile-isolated)

What `bin/new-agent` builds. Each agent runs its **own** runtime — no shared wrapper,
no cross-agent dependency.

- **Runtime** — `github:garrytan/gbrain` (v0.41.x), installed into the agent's own
  profile-home Bun (`bun add -g github:garrytan/gbrain` with `HOME=<profile>/home`,
  `BUN_INSTALL=<profile>/home/.bun`). **Not** npm `gbrain@1.3.1` (an unrelated GPU
  library).
- **Store** — pglite at `<profile>/home/.gbrain/brain.pglite` (768-dim
  `nomic-embed-text`). Never SQLite.
- **Wrapper** — `<agent>/.local/bin/gbrain` pins `HERMES_HOME`, `HOME`,
  `BUN_INSTALL`, `XDG_CACHE_HOME`, and `OLLAMA_BASE_URL=http://127.0.0.1:11434/v1`.
- **config.json** — `{ "engine": "pglite", "database_path": ".../brain.pglite",
  "embedding_base_url": ".../v1" }`.
- **MCP** — `mcp_servers.gbrain.command` → the agent's own wrapper, never a shared one.
- **Seed** — `gbrain import <agent>/vault/brain` then `gbrain embed --stale`.

**Required surfaces — verify each separately:** vault path, store path, CLI wrapper,
engine type, embedding provider/model/dimensions, MCP registration, import/index
status, search/query smoke tests, health/doctor output, lock/concurrency caveats.

**Recommended vault shape:** `vault/brain/{HOME.md, people/, projects/, guides/,
tech/, daily/, companies/, concepts/, meetings/, sources/}`.

**Embeddings.** Prefer local — `ollama:nomic-embed-text:latest`, 768-dim. GBrain
v0.41's Ollama recipe needs an **OpenAI-compatible base URL**
(`http://127.0.0.1:11434/v1`); plain `…:11434` can return `Not Found` on embed even
when Ollama's native `/api/embeddings` works.

**Split-brain** (CLI and MCP pointing at different stores) is the classic failure.
Repair: baseline every surface read-only → choose the canonical brain → back up
alternates → converge all launch paths → import curated vault → embed → verify CLI
*and* MCP → document reload caveats.

**PGLite lock caveat.** PGLite behaves like a single-process store; a persistent MCP
process can hold the lock and block CLI ops. Prefer lock-aware scripts; avoid
concurrent blind CLI/MCP operations.

---

## Skills layer

Skills are procedural memory — how a profile improves over time without bloating
bootstrap memory.

**Belongs in a skill:** repeatable workflows, tool-specific commands, known
pitfalls, verification steps, user/project quality bars, templates, references.
**Does not:** one-off outcomes, PR numbers, commit SHAs, secrets, temporary task
state, raw transcripts.

**Categories for a strong operator profile**

- **Core** — Hermes configuration, memory architecture, profile housekeeping,
  verified delivery.
- **Operator modules** — Google Workspace, client email drafting, executive
  briefings, document/resource publishing, Kanban orchestration, voice delivery.
- **Engineering modules** — GitHub workflow, debugging, TDD, subagent-driven
  development, local CI/CD.

**Maintenance.** Load relevant skills before acting; patch them the moment they're
stale. Prefer **shared** skills for fleet-wide patterns (one copy under
`Shared/skills`, listed in each `config.yaml` under `skills.external_dirs` — agents
read it, they don't each copy it) and **profile-local** skills for persona/client
specifics.

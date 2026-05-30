# Memory Architecture

The fleet standard is a layered memory system.

## Layer 1 — Bootstrap memory

Files: `MEMORY.md` and `USER.md`.

Rules:

- Keep small and high-signal.
- Do not store task progress, PR numbers, commit SHAs, temporary TODOs, or facts likely stale in a week.
- Write declarative facts, not imperative instructions.

## Layer 2 — Honcho

Honcho is the peer/user learning layer. Use it for user preferences, communication style, stable identity facts, raw remembered observations, and dialectic reasoning about the user.

Do not blindly duplicate Honcho into GBrain. Honcho can contain dream/candidate material that needs consolidation and sanity checks.

### Stack (one per agent)

Each agent runs its **own** Dockerized Honcho stack — four services: `api`,
`deriver` (queue worker: Deriver + Summarizer + Dreamer), `database`
(Postgres/pgvector), `redis`. Ports are **auto-allocated** so stacks never clash:
`API` increments from a base; `DB = 5432 + (API−8000)`, `REDIS = 6379 + (API−8000)`.
Embedding dimension is locked identical across the fleet (e.g. 768). The gateway
wires to it via `honcho.json` (`baseUrl`, `workspace`, `aiPeer`, `peerName`); the
gateway auto-creates the workspace + the `operator`/`<agent>` peers on first
connect. Only the **identity grounding messages** are seeded manually.

### Three-tier model (cost/latency by workload)

| Tier | Workloads | Where |
|------|-----------|-------|
| **S** always-on | Deriver, Summary, Dialectic minimal/low | local (small model) |
| **M** on-demand | Dialectic medium/high | cloud, fast |
| **L** on-demand + nightly | Dialectic max + Dreams | cloud, deepest reasoning |

Each agent has a **ceiling** that bounds how far it climbs:

- **High** — `max` + dreams use the Tier-L reasoning model.
- **Medium** — dialectic clamps to Tier-M; dreams still Tier-L.
- **Low** — dialectic stays local (Tier-S); dreams on Tier-M.

Keep the per-agent ceilings in **one matrix** and sync it to every stack's `.env`
(don't hand-edit per agent). Dream cadence is per agent (e.g. 6–24h). The `.env`
template (`templates/honcho/env.tmpl`) carries the tier slots; the matrix lives
in your fleet ops, not in this public repo.

## Layer 3 — GBrain

GBrain is the semantic/wiki brain. Use it for curated long-term knowledge, project context, people/company pages, technical notes, reusable guides, daily/consolidation notes, and source-linked facts and decisions.

GBrain indexes markdown under `vault/brain/`. It is not merely a folder; it has a runtime store, index, embeddings, and optionally MCP tools.

## Layer 4 — Hygiene and consolidation

A mature profile has recurring jobs:

1. **Consolidation** — review recent sessions and write durable facts into GBrain.
2. **Hygiene** — scan for poison, stale facts, identity drift, broken retrieval, and duplicate/conflicting memory.

## Deprecated memory stores

LocalMem is deprecated/rescue-only in the current fleet architecture. Treat old LocalMem exports as evidence for curated migration, not as active memory.

## Verification checklist

Before saying memory is healthy, verify bootstrap memory, Honcho provider, GBrain stats, search/query, embedding coverage, MCP/CLI alignment, consolidation jobs, hygiene jobs, and known poison classes.

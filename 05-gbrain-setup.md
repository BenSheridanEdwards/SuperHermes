# GBrain Setup

GBrain is the fleet semantic/wiki memory layer.

## Required surfaces

Document and verify all of these separately: markdown vault path, runtime store path, CLI wrapper, engine type, embedding provider/model/dimensions, MCP registration, import/index status, search/query smoke tests, health/doctor output, and lock/concurrency caveats.

## Canonical setup (v0.41, profile-isolated) — what `bin/new-agent` builds

Each agent runs its **own** GBrain runtime — no shared wrapper, no cross-agent dependency (one agent's brain must never depend on another agent's files):

- **Runtime:** `github:garrytan/gbrain` (v0.41.x), installed into the agent's own profile-home Bun — `bun add -g github:garrytan/gbrain` with `HOME=<profile>/home`, `BUN_INSTALL=<profile>/home/.bun`. (NOT the npm `gbrain@1.3.1` package — that's an unrelated GPU JS library.)
- **Store:** pglite at `<profile>/home/.gbrain/brain.pglite` (768-dim `nomic-embed-text`). Not SQLite.
- **Wrapper:** `<agent>/.local/bin/gbrain` pins `HERMES_HOME`, `HOME`, `BUN_INSTALL`, `XDG_CACHE_HOME`, and `OLLAMA_BASE_URL=http://127.0.0.1:11434/v1`.
- **config.json:** `{ "engine": "pglite", "database_path": ".../brain.pglite", "embedding_base_url": ".../v1" }`.
- **MCP:** `mcp_servers.gbrain.command` → the agent's own wrapper (never a shared one).
- **Seed:** `gbrain import <agent>/vault/brain` then `gbrain embed --stale`.

## Recommended vault shape

```text
vault/brain/
├── HOME.md
├── people/
├── projects/
├── guides/
├── tech/
├── daily/
├── companies/
├── concepts/
├── meetings/
└── sources/
```

## Split-brain warning

A common failure mode is CLI and MCP pointing at different GBrain stores.

Repair pattern:

1. Baseline every surface read-only.
2. Choose the canonical brain.
3. Back up alternate stores.
4. Make all launch paths converge.
5. Import curated vault.
6. Embed after wiring is fixed.
7. Verify CLI and MCP.
8. Document reload/restart caveats.

## Embeddings

Prefer local embeddings where available — `ollama:nomic-embed-text:latest`, 768 dimensions, via local Ollama. **GBrain v0.41's Ollama recipe needs an OpenAI-compatible base URL** (`http://127.0.0.1:11434/v1`); plain `…:11434` can return `Not Found` on embed even when Ollama's native `/api/embeddings` works. Do not assume OpenAI credentials are required until checking the active GBrain config.

## PGLite lock caveat

PGLite can behave like a single-process store. A persistent MCP process may hold the DB lock and block CLI operations. Prefer lock-aware scripts and avoid concurrent blind CLI/MCP operations.

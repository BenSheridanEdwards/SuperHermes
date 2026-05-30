# GBrain Setup

GBrain is the fleet semantic/wiki memory layer.

## Required surfaces

Document and verify all of these separately: markdown vault path, runtime store path, CLI wrapper, engine type, embedding provider/model/dimensions, MCP registration, import/index status, search/query smoke tests, health/doctor output, and lock/concurrency caveats.

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

Prefer local embeddings where available. The Jeeves reference uses `ollama:nomic-embed-text:latest`, 768 dimensions, via local Ollama. Do not assume OpenAI credentials are required until checking the active GBrain config.

## PGLite lock caveat

PGLite can behave like a single-process store. A persistent MCP process may hold the DB lock and block CLI operations. Prefer lock-aware scripts and avoid concurrent blind CLI/MCP operations.

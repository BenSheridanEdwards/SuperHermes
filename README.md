# SuperHermes

Spin up a sandboxed, memory-equipped AI agent on macOS with one command.

SuperHermes is a small framework + reference architecture for running a fleet of
[Hermes](https://github.com/NousResearch/hermes) agents side by side on a single
machine — each isolated in its own home, each with its own persistent memory,
all under a shared "town-square" security model.

```sh
cp superhermes.conf.example superhermes.conf   # set AGENTS_ROOT and carve-outs
bin/new-agent --name Sky --camp personal --tier m
```

That one command provisions the full anatomy: directory skeleton, a compiled
sandbox profile, launchd services, the Hermes profile, a Honcho memory stack
(Postgres + Redis in Docker, ports auto-allocated), a GBrain knowledge vault,
and shared-skills wiring — then boots it.

## The town-square model

Every agent lives in its own home under `AGENTS_ROOT/<Name>` and has free reign
over the shared account, with three carve-outs enforced by `sandbox-exec`:

1. **Other agents' homes are read-only** — look through the window, don't enter.
2. **Operator-protected paths are off-limits** — e.g. the human's own home.
3. **Optional need-to-know paths** — readable only by named agents.

It's allow-all-then-deny (not a brittle allowlist), so normal tooling — PTYs,
temp dirs, Docker, browsers — never breaks. All carve-outs come from your local
`superhermes.conf`; the templates ship with none baked in.

## Memory

- **Honcho** — per-agent peer/user memory + dialectic recall (its own Postgres +
  Redis stack, one per agent, ports auto-allocated).
- **GBrain** — a semantic/wiki brain over each agent's markdown `vault/`.
- **Bootstrap** — small, always-loaded `MEMORY.md` + `USER.md`.

## Requirements

- macOS (uses `sandbox-exec` + launchd)
- Docker (for the Honcho memory stacks)
- A Hermes install + Python venv
- Python 3, `bash`

## Quickstart

1. `cp superhermes.conf.example superhermes.conf` and set `AGENTS_ROOT` (the
   folder that holds one directory per agent) plus any sandbox carve-outs.
2. `bin/new-agent --name Sky --camp personal --tier m`
   (add `--dry-run` to render to a temp dir with zero side effects first).
3. Fill the two things the tool can't generate: credentials (`auth.json`) and
   the agent's `SOUL.md` persona.

`bin/new-agent --help` lists all flags.

## Documentation

The numbered docs are the reference architecture behind the tool:

| Doc | Topic |
|-----|-------|
| `00-executive-summary` | the standard, in brief |
| `01-profile-layout` | filesystem layout & isolation |
| `02-config-baseline` | config posture |
| `03-toolsets-and-permissions` | toolset design & risk model |
| `04-memory-architecture` | Honcho + GBrain + bootstrap memory |
| `05-gbrain-setup` | GBrain runtime, MCP, embeddings |
| `06-skills-layer` | skills as procedural memory |
| `07-cron-and-guardrails` | durable scheduled work |
| `08-operator-modules` | optional Google/meetings/Kanban/voice |
| `09-housekeeping` | keeping profiles lean |
| `10-new-agent-scaffolding` | the `new-agent` command in depth |

## License

MIT — see [LICENSE](LICENSE).

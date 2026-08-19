# Architecture Decisions

The durable decisions behind SuperHermes — the *why*, not the *what*. The README
and the guides in [docs/](docs/) describe how an agent is built today; this file records the
reasoning that shouldn't change as the implementation evolves. Each entry is a
decision plus the failure it prevents.

---

### 1. Every agent stands alone
**Decision.** No agent's runtime, memory, or tooling may depend on another agent's
files. Shared things live in one shared place; private things live in the agent's
own home. Nothing in between.

**Why.** A "shared" GBrain wrapper that exec'd into one agent's private Bun cache
made the whole fleet depend on that one agent — wipe its cache and others broke.
Independence means a failure in one agent can't cascade.

### 2. The sandbox is the sole write boundary — "town-square," allow-all-then-deny
**Decision.** The OS sandbox (`sandbox-exec`) grants free reign over normal
macOS, browser, GPU, app, temp, and runtime paths. It denies only file boundaries:
no writes to another agent root, no access to another macOS user home, and no
access to `/Users/Shared`. It is not an allowlist and does not confine agents to
`/Users/agents`.

**Why.** Allowlist sandboxes drift and break ordinary tooling (PTYs, temp dirs,
Docker, GUI browsers) — every new tool needs a new rule. The real filesystem
boundary is narrow and stable: do not write in another agent root, do not cross
into another macOS user, and do not use `/Users/Shared`. Email and destructive
GitHub approvals are enforced at the tool/workflow layer, not by file paths.
QuickLook and Brave get explicit `process-exec` no-sandbox exceptions because
they create their own native macOS sandboxes; forcing them to inherit the Hermes
profile breaks screenshots and browser/GPU flows.

### 3. No application-level write gate (`HERMES_WRITE_SAFE_ROOT`)
**Decision.** Do not set the Hermes write-approval gate.

**Why.** It would prompt for approval on every write outside the agent's own home —
including legitimate work like maintaining the shared skills library or building
apps — while adding no protection the OS sandbox doesn't already enforce. Friction
with no upside.

### 4. GBrain: one Postgres store per agent, profile-isolated, own wrapper
**Decision.** Each agent installs its own GBrain runtime into its profile-home,
keeps one Postgres store, and points its `config.json`, MCP command, and CLI wrapper
at that one store.

**Why.** The SQLite + shared-wrapper era produced two failures at once: a
**split-brain** (CLI and MCP writing to different stores, so memory silently
diverged) and a **cross-agent dependency** (the shared wrapper). Convergence on one
store kills the split-brain; profile isolation kills the dependency.

### 5. The middle memory layer was removed
**Decision.** The passive peer-learning layer (Honcho) was removed —
decommissioned in the reference deployment on 2026-07-15. Two layers remain:
session/state and the GBrain semantic store.

**Why.** A per-agent Dockerized stack that the agent never successfully read
from was pure operational weight — containers, ports, backups, and tier
matrices to keep healthy for no recall benefit. Fewer layers, each verified,
beats more layers half-alive.

### 6. Two memory layers, each with one job
**Decision.** Bootstrap (`MEMORY.md`/`USER.md`, tiny, always-loaded) · GBrain
(curated knowledge). Don't duplicate across them.

**Why.** Conflating them bloats always-loaded context and double-stores facts.
GBrain is what the agent *curates*; bootstrap is the handful of facts needed
every turn. Distinct jobs, distinct stores.

### 7. Config is generated/synced from one source — never hand-edited per agent
**Decision.** Per-agent config derives from templates and matrices, not manual edits.

**Why.** Hand-edited fleets drift. A single audit found three different config
schema versions, split GBrain stores, and a missing memory-wiring file — all
silent. One source + a render/sync step makes drift structurally hard.

Profiles carry a `_config_version` (the reference deployment is currently 33)
migrated by Hermes's own migrate_config — never hand-edited.

### 8. A new agent is born inspired *and* safe
**Decision.** `SOUL.md` starts as a seed ("a new soul with unlimited potential…
craft your soul to partner with your human") paired with one iron law: no
real-world action without the human's approval. *Earn trust, then earn latitude.*

**Why.** Identity is the one file an agent should self-author, so seed a tone, not a
spec. But a day-one agent can send email and post to the world — so the iron law is
non-negotiable. Framing the boundary as a runway ("earn latitude") makes freedom
and safety point the same way.

### 9. No secrets in the repo
**Decision.** Credentials, tokens, and machine-specific paths live only in the
gitignored local config or the agent's own profile (`.env`) — never in a committed
file. *Where* those values come from is **pluggable**: paste into `.env`, or source
them from a secrets manager via Hermes's `secrets:` config (BitWarden Secrets
Manager is supported natively). The framework declares the secret **keys** an agent
needs (`TELEGRAM_BOT_TOKEN`, etc.); the backend is the operator's choice and never
hardcoded.

**Why.** The framework is meant to be shared/open-source — so it can't assume any
one secrets backend. Declaring the keys and leaving the source pluggable keeps it
usable by a solo operator with a plain `.env` *and* by a fleet centralising on
BitWarden, with no fork. Secrets are recoverable; a leaked secret in public git
history is not.

### 10. Verify every layer independently — "looks set up" ≠ "works"
**Decision.** Never report a layer healthy without its own evidence: GBrain
store reachability, `gbrain stats`/`health` (embed coverage), sandbox compiles,
plist lints, config parses.

**Why.** A `vault/brain/` folder proves markdown exists, not that GBrain indexes it.
A running container isn't a healthy API. A present config file isn't a *loaded* one
(it can silently fall back to defaults). Each layer fails in its own way, so each is
verified in its own way.

### 11. Each agent is its own git repo at its root; `.gitignore` normalised, not centralised
**Decision.** Every agent is a standalone git repo rooted at `AGENTS_ROOT/<Name>/`.
Each carries its **own** copy of a **default-deny** `.gitignore` that follows one
fleet standard — normalised (same rules everywhere) but not centralised (no shared
or symlinked file). The ignore allow-lists only the durable identity (config, soul,
memory, crons, scripts, sandbox, README); everything else is denied by default.

**Why.** *Per-agent repo* keeps the independence principle (decision 1) true at the
version-control layer — each agent's history is its own, pushable on its own, with
no fleet-monorepo coupling. *Default-deny* is the only model that's safe by
construction: an allow-list-on-top-of-deny can't leak a brand-new kind of secret,
whereas a deny-list silently tracks anything you forgot to exclude. An early audit
found one agent tracking 760+ files (including a retired memory plugin) next to
another tracking 28 — the same drift decision 7 fights, now fixed with one rendered
standard. *Normalised, not centralised* means a solo operator cloning one agent
gets a correct ignore with no dependency on a shared file.

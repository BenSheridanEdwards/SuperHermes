# Operations — automation, modules, housekeeping

Durable scheduled work and its approval gates, the optional operator modules, and
how to keep a profile lean over time. For the *why* see
[ARCHITECTURE.md](../ARCHITECTURE.md).

---

## Cron and guardrails

Cron jobs make a profile durable — and make mistakes durable too. Treat them
accordingly.

**Cron classes:** briefing · memory · promise/action · watchdog · script-only
deterministic.

**Required metadata** (per job): name, schedule, profile, workdir, skills, script,
delivery target, approval boundary, expected output, failure behaviour.

**Approval boundaries.** Cron jobs may **draft, summarize, inspect, prepare, and
recommend**. They must **never** autonomously send real-world email/messages, post
publicly, buy anything, change credentials/security/permissions, delete important
work, or mutate calendar/Drive/Docs without explicit approval
(`approvals.cron_mode: deny`).

**Prompt shape.** Future runs don't inherit the original chat context, so good cron
prompts are self-contained: agent role, source systems, exact allowed actions,
forbidden actions, output format, verification requirements.

**Verification.** Don't assume a cron works because it exists — verify job status,
schedule, workdir, scripts, last-run output, and side effects.

Every agent ships with two baseline crons: the daily **memory-maintenance** run
(a snapshot-fed GBrain pass — vault import + embed, consolidation into topical
pages, and hygiene over the bootstrap + GBrain layers) and the deterministic
**identity git-sync**.

---

## Operator modules

A profile should be modular — not every agent needs every subsystem.

- **Google Workspace** — read full thread context before email recommendations;
  draft only unless send is explicitly approved; for Gmail replies, a true
  Reply/Reply-all composer with the prior thread visible underneath is the standard
  (same thread ID alone may be insufficient); calendar/Drive/Docs/sharing changes
  require approval.
- **Meeting** — calendar-aware detection, transcript collection, action extraction,
  post-meeting briefing, recurring-meeting watch jobs. Document whether it uses
  captions, direct audio capture, or a real inviteable bot account — don't blur those
  architectures.
- **Kanban / no-lost-promises** — converts meeting notes, emails, and commitments
  into durable action tracking. Memory cleanup comes **first**, or the board
  operationalises bad facts.
- **Voice / Telegram** — document delivery platform, TTS provider, output format, max
  briefing length, text-backup requirement. **MP3 is preferred; OGG should not be the
  primary final format.**
- **Document publishing** — done-bar: render the artifact, visually inspect it,
  verify links/files/side effects, and include evidence before reporting success.
  File checks alone aren't enough for client-facing visuals.

---

## Housekeeping and archive policy

Powerful profiles accumulate debris: rendered PDFs, browser profiles, caches,
experimental repos, local runners, audio files, one-off evidence bundles.

**Audit first.** Inventory profile/workspace/home surfaces, sort by size and age,
check git state before archiving folders, classify candidates by risk, and report
recommendations **before** any mutation.

**Archive, don't delete.** Default to a reversible archive with a manifest: original
path, size, file count, mtime range, reason, git state, destination. Deletion
requires explicit approval and strong confidence the material is reproducible or
valueless.

**Keep by default:** active profile config, `.env`/auth files (without exposing
them), session/state databases, current skills, active scripts, active cron
definitions, the GBrain vault/store, current repos, and dirty worktrees.

**Often archivable after review:** old render folders, evidence bundles, stale
browser profiles, paused experiment outputs, duplicate dependency folders, one-off
test workspaces, old audio cache beyond retention.

> **Template lesson.** Don't let a live agent's accumulated workspace become the
> template. Encode the clean architecture and the maintenance policy — not the mess.

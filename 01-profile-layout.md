# Profile Layout

## Canonical structure

A strong fleet profile should be understandable at a glance:

```text
$AGENTS_ROOT/<Agent>/
├── .hermes/profiles/<profile>/
│   ├── config.yaml
│   ├── .env                      # secrets; never template raw
│   ├── auth.json                  # auth/OAuth; never template raw
│   ├── memories/
│   │   ├── MEMORY.md
│   │   └── USER.md
│   ├── skills/
│   ├── scripts/
│   ├── cron/
│   ├── sessions/
│   ├── logs/
│   └── home/
│       └── .gbrain/               # canonical GBrain store where used
├── .home/                         # profile home/sandbox home
├── workspace/                     # work products, repos, evidence, temp outputs
└── vault/
    └── brain/                     # curated markdown indexed by GBrain
```

## Separation rules

- `config.yaml` contains settings. Redact before sharing.
- `.env`, `auth.json`, browser profiles, cookies, tokens, keychains, and credentials are never template material.
- `workspace/` contains work artifacts and can become huge. Template only the policy, not the contents.
- `vault/brain/` is curated long-term knowledge. Raw transcripts and large evidence dumps should live outside `brain/` unless intentionally indexed.
- `scripts/` contains operational helpers. Split scripts into core template scripts and optional module scripts.
- `cron/` contains durable automation. Every cron must have a stated approval boundary.

## Profile-safe path rule

Use profile-local paths or explicit agent paths. Avoid hidden dependencies on the default Hermes profile.

Bad:

```text
~/.hermes/skills
~/.hermes/.env
```

Better:

```text
$AGENTS_ROOT/<Agent>/.hermes/profiles/<profile>/skills
$AGENTS_ROOT/<Agent>/.hermes/profiles/<profile>/.env
```

## Shared components

Fleet-wide components belong under `$AGENTS_ROOT/Shared/`, for example:

- Shared skills.
- Shared CLI wrappers.
- Shared architecture references.
- Shared CI/CD infrastructure.

Do not make a profile depend on an undocumented shared binary. If a shared wrapper is required, document the command, version, and verification output.

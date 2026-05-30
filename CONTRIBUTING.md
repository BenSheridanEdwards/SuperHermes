# Contributing to SuperHermes

Thanks for your interest! SuperHermes is a small, focused framework — contributions
that keep it simple and portable are very welcome.

## Ground rules

- **No secrets, ever.** Credentials, tokens, OAuth, cookies, and private paths
  belong in your local `superhermes.conf` (gitignored), never in committed files.
- **No machine-specific paths in templates or docs.** Use `AGENTS_ROOT` / config
  variables. The repo must clone-and-run on any machine.
- **Keep the sandbox allow-all-then-deny.** Carve-outs are config-driven, not
  hardcoded.

## Dev workflow

1. Fork and branch.
2. Make changes. For the scaffolder, always test with a dry run first:
   ```sh
   bin/new-agent --name Probe --dry-run
   ```
   This renders the full tree to a temp dir with no side effects and compiles the
   sandbox profile — confirm it passes before opening a PR.
3. `bash -n bin/new-agent` to syntax-check.
4. Open a PR describing what changed and how you verified it.

## Scope

Good fits: portability fixes, new template options, better health checks, docs.
Out of scope: anything that hardcodes a specific fleet, agent, or operator.

## Reporting issues

Open a GitHub issue with your OS, Docker version, and the output of a
`--dry-run` reproduction where possible.

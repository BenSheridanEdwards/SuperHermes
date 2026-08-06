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
4. **Run the tests** — they lock down the shipping scripts (gitignore default-deny,
   git-sync silence + secret tripwire + no-force, scaffolder dry-run):
   ```sh
   bash tests/run-tests.sh        # must be green
   ```
5. Open a PR describing what changed and how you verified it.

## Verifying a live fleet

`bin/verify-fleet` asserts the framework's invariants across every agent under
`AGENTS_ROOT` — fast, no-LLM, stdlib-only. It's the "diagnose" half of fleet
ops: cron scripts all exist, no stale shared-wrapper or retired-system refs, no
secrets/bloat tracked in git, normalised `.gitignore`, profile-isolated GBrain,
consistent config versions, baseline crons present.

```sh
bin/verify-fleet               # all agents · exit 1 on any FAIL
bin/verify-fleet --agent Sky   # one agent
bin/verify-fleet --quiet       # only WARN/FAIL + summary
```

Run it after any change to a live fleet (and ideally on a daily cron) — most
real-world drift is config / cross-reference, exactly what it catches.

## Scope

Good fits: portability fixes, new template options, better health checks, docs.
Out of scope: anything that hardcodes a specific fleet, agent, or operator.

## Reporting issues

Open a GitHub issue with your OS and the output of a
`--dry-run` reproduction where possible.

## Licensing of contributions

Unless you explicitly state otherwise, any contribution you intentionally
submit for inclusion in this project shall be licensed under the MIT
License (see the LICENSE file), without any additional terms or
conditions, and you confirm that you have the right to submit it under
that license.

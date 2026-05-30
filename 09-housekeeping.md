# Housekeeping and Archive Policy

Powerful profiles accumulate debris: rendered PDFs, browser profiles, caches, experimental repos, local runners, audio files, and one-off evidence bundles.

## Audit first

Before cleanup, inventory profile/workspace/home surfaces, sort by size and age, check git state before archiving folders, classify candidates by risk, and report recommendations before mutation.

## Archive, don't delete

Default action should be reversible archive with a manifest: original path, size, file count, mtime range, reason, git state, and destination path.

Deletion requires explicit approval and strong confidence that the material is reproducible or valueless.

## Keep by default

Preserve active profile config, `.env` and auth files without exposing them, session/state databases, current skills, active scripts, active cron definitions, GBrain vault/store, current repos, and dirty worktrees.

## Candidate classes

Often archivable after review: old render folders, evidence bundles, stale browser profiles, paused experiment outputs, duplicate dependency folders, one-off test workspaces, and old audio cache beyond retention needs.

## Template lesson

Do not let a live agent's accumulated workspace become the template. The template should encode the clean architecture and the maintenance policy, not the mess.

# git-sync HTTPS BWS push — CLI smoke

Date: 2026-07-25

## What was proven on host

1. Unattended `git push` to HTTPS identity remotes failed with:
   `fatal: could not read Username for 'https://github.com': Device not configured`
2. With `GH_TOKEN` from BWS (EU vault) and:
   `git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')" push origin main`
   push succeeded for Doc, Wukong, Sky, Neo, Iris, Lexi, DiVinci, Jarvis, Formula, Archivist, Workflows, Hunter, Maverick.
3. Live agent `scripts/git-sync.sh` copies updated the same day; this PR locks the SuperHermes template so new agents inherit it.
4. `bash -n` on the rendered template (placeholders substituted) exits 0.

## Verify after merge

```bash
# New agent scaffold should emit HTTPS-aware git-sync
rg -n "extraheader|BWS_SERVER_URL|GH_TOKEN" templates/git-sync.sh.tmpl
bash -n <(sed 's/__AGENT_ROOT__/\/tmp/;s/__AGENT_NAME__/T/;s/__AGENT_SLUG__/t/' templates/git-sync.sh.tmpl)
```

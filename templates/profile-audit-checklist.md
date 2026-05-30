# Profile Audit Checklist

## Runtime

- [ ] Hermes version captured
- [ ] profile path captured
- [ ] model/provider captured
- [ ] gateway status checked
- [ ] config path and env path known

## Config and safety

- [ ] config summarized with secrets redacted
- [ ] approval mode checked
- [ ] external side-effect rules documented
- [ ] no raw `.env`, `auth.json`, cookies, or tokens copied

## Tools and MCP

- [ ] enabled/disabled toolsets listed
- [ ] MCP servers listed
- [ ] MCP test run for critical servers
- [ ] tool reload/restart caveats documented

## Memory

- [ ] `MEMORY.md` and `USER.md` exist
- [ ] provider checked
- [ ] Honcho/profile state checked where available
- [ ] GBrain vault path checked
- [ ] GBrain runtime stats checked
- [ ] embeddings checked
- [ ] semantic search/query smoke test run
- [ ] hygiene and consolidation jobs checked

## Skills

- [ ] skill count captured
- [ ] profile-local vs shared skills separated
- [ ] core skills identified
- [ ] stale/archived skills not treated as template core

## Cron

- [ ] active jobs listed
- [ ] paused jobs classified
- [ ] scripts checked
- [ ] approval boundary documented per job

## Housekeeping

- [ ] profile/workspace/home inventory captured
- [ ] large folders classified
- [ ] git state checked before archive recommendations
- [ ] no deletion without approval

#!/usr/bin/env bash
# ============================================================================
# SuperHermes script tests — lock down the behaviour of the shipping artifacts
# (gitignore.tmpl, git-sync.sh.tmpl, new-agent --dry-run). No external deps.
#
#   bash tests/run-tests.sh            # run all
# Exit non-zero on any failure (CI-friendly).
#
# NOTE: sections run in the MAIN shell (no subshells) so PASS/FAIL counters
# aggregate correctly — a subshell would swallow failures into a false green.
# ============================================================================
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok(){  printf '    \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad(){ printf '    \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
have(){ printf '%s\n' "$1" | grep -qF -- "$2"; }
assert_has(){   have "$1" "$2" && ok "$3" || bad "$3 — expected to contain: $2"; }
assert_hasnt(){ have "$1" "$2" && bad "$3 — should NOT contain: $2" || ok "$3"; }
assert_eq(){ [ "$1" = "$2" ] && ok "$3" || bad "$3 — got '$1' want '$2'"; }
section(){ printf '\n\033[36m▸ %s\033[0m\n' "$1"; }
render(){ AGENT_NAME="${A_NAME:-Test}" AGENT_SLUG="${A_SLUG:-test}" AGENT_ROOT="${A_ROOT:-/tmp/x}" \
  python3 -c "import os,re,sys;print(re.sub(r'__([A-Z_]+)__',lambda m:os.environ.get(m.group(1),m.group(0)),open(sys.argv[1]).read()),end='')" "$1"; }

# ---------------------------------------------------------------------------
section "gitignore.tmpl — default-deny scopes to identity only"
T="$(mktemp -d)"; cd "$T"
A_SLUG=test render "$REPO/templates/gitignore.tmpl" > .gitignore
mkdir -p .hermes/profiles/test/{memories,cron,scripts,skills/x} .hermes/sandbox \
         .hermes/honcho/honcho .home/.gbrain vault/brain workspace/clone
for f in .hermes/profiles/test/config.yaml .hermes/profiles/test/honcho.json \
         .hermes/profiles/test/SOUL.md .hermes/profiles/test/memories/MEMORY.md \
         .hermes/profiles/test/cron/jobs.json .hermes/profiles/test/scripts/s.sh \
         .hermes/sandbox/test.sb README.md; do echo x > "$f"; done
for f in .hermes/profiles/test/.env .hermes/profiles/test/auth.json \
         .hermes/profiles/test/google_token.json .hermes/profiles/test/skills/x/SKILL.md \
         .hermes/honcho/honcho/compose.yml .home/.gbrain/brain.pglite \
         vault/brain/n.md workspace/clone/c.js; do echo SECRET > "$f"; done
git init -q && git add -A 2>/dev/null
TR="$(git ls-files)"
for want in .hermes/profiles/test/config.yaml .hermes/profiles/test/SOUL.md \
            .hermes/profiles/test/honcho.json .hermes/profiles/test/memories/MEMORY.md \
            .hermes/sandbox/test.sb README.md; do assert_has "$TR" "$want" "tracks $want"; done
for deny in .env auth.json google_token.json vault/ workspace/ honcho/honcho .pglite skills/; do
  assert_hasnt "$TR" "$deny" "excludes $deny"; done
cd "$REPO"; rm -rf "$T"

# ---------------------------------------------------------------------------
section "git-sync.sh — silent success, secret tripwire, no force-push"
T="$(mktemp -d)"; cd "$T"
A_ROOT="$T/repo" A_SLUG=test A_NAME=Test render "$REPO/templates/git-sync.sh.tmpl" > sync.sh; chmod +x sync.sh
if grep -qE 'push .*(--force|-f)\b' sync.sh; then bad "rendered script never force-pushes"; else ok "rendered script never force-pushes"; fi
mkdir repo; cd repo; git init -q; echo a > f; git add -A; git -c user.name=t -c user.email=t@t commit -qm init
run(){ AGENT_GIT_ROOT="$T/repo" bash "$T/sync.sh" 2>&1; }
out="$(run)"; rc=$?; assert_eq "$rc" "0" "noop exits 0"; assert_eq "$out" "" "noop is silent"
# An orphaned lock (no live holder) self-heals regardless of age — old...
: > .git/index.lock; touch -t 200001010000 .git/index.lock
out="$(run)"; rc=$?; assert_eq "$rc" "0" "old orphaned index.lock self-heals"; assert_eq "$out" "" "lock heal is silent"
[ -e .git/index.lock ] && bad "old orphaned index.lock is removed" || ok "old orphaned index.lock is removed"
# ...AND fresh: a lock orphaned by a reboot seconds ago has a fresh mtime but no
# owner. This is the Doc/Probe 2026-06-20 regression — it MUST heal, not block.
: > .git/index.lock
out="$(run)"; rc=$?; assert_eq "$rc" "0" "fresh orphaned index.lock self-heals (reboot regression)"
[ -e .git/index.lock ] && bad "fresh orphaned index.lock is removed" || ok "fresh orphaned index.lock is removed"
# A lock a LIVE process holds open must NOT be touched — don't race a running git.
: > .git/index.lock
exec 9<>.git/index.lock                      # this shell now holds the lock open
out="$(run)"; rc=$?
exec 9>&-                                     # release
[ "$rc" != "0" ] && ok "live-held index.lock is not removed" || bad "live-held index.lock should stop git"
[ -e .git/index.lock ] && ok "live-held index.lock remains for the owner" || bad "live-held index.lock remains for the owner"
rm -f .git/index.lock
echo b >> f; n0=$(git rev-list --count HEAD); out="$(run)"; rc=$?; n1=$(git rev-list --count HEAD)
assert_eq "$rc" "0" "change exits 0"; assert_eq "$out" "" "successful commit is silent"
assert_eq "$n1" "$((n0+1))" "change creates exactly one commit"
printf 'tok=ghp_%s\n' "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" >> f
n0=$(git rev-list --count HEAD); out="$(run)"; rc=$?; n1=$(git rev-list --count HEAD)
assert_eq "$rc" "2" "secret aborts with exit 2"
assert_has "$out" "ABORTED" "secret abort is reported"
assert_eq "$n1" "$n0" "secret abort creates no commit"
assert_eq "$(git diff --cached --name-only)" "" "secret abort resets the index"
cd "$REPO"; rm -rf "$T"

# ---------------------------------------------------------------------------
section "new-agent --dry-run — renders the full anatomy, zero side effects"
out="$(bash "$REPO/bin/new-agent" --name TestUnit --camp test --tier m --dry-run 2>&1)"; rc=$?
assert_eq "$rc" "0" "dry-run exits 0"
assert_has "$out" "testunit.sb (compiles)"  "sandbox compiles"
assert_has "$out" "root .gitignore"          "renders normalised root .gitignore"
assert_has "$out" "git initialised at root"  "initialises git at root"
assert_has "$out" "memory-maintenance"        "renders memory-maintenance cron"
assert_has "$out" "DRY-RUN complete"         "completes cleanly"
td="$(printf '%s' "$out" | python3 -c "import sys,re;t=re.sub(r'\x1b\[[0-9;]*m','',sys.stdin.read());m=re.search(r'dry-run . (\S+)',t);print(m.group(1) if m else '')")"
pl="$(cat "$td/LaunchAgents/ai.hermes.gateway-testunit.plist" 2>/dev/null)"
assert_has "$pl" "Shared/bin/hermes-gateway-launch" "gateway plist uses shared launcher"
assert_hasnt "$pl" "hermes_cli.main"                "gateway plist does not bypass shared launcher"
assert_has "$pl" "<string>testunit</string>"        "gateway plist passes slug to launcher"
python3 -m json.tool "$REPO/templates/agent-template.json" >/dev/null 2>&1 \
  && ok "agent template manifest parses" || bad "agent template manifest parses"
AGENTS_ROOT=""; [ -f "$REPO/superhermes.conf" ] && . "$REPO/superhermes.conf" || . "$REPO/superhermes.conf.example"
[ -d "${AGENTS_ROOT:-/nonexistent}/TestUnit" ] && bad "dry-run left a real agent dir!" || ok "dry-run leaves no real agent dir"

# ---------------------------------------------------------------------------
section "set-model-block — read round-trips; write replaces ONLY the model section"
T="$(mktemp -d)"
printf 'model:\n  provider: openai-codex\n  default: gpt-5.5\n\ntoolsets:\n- hermes-cli\n\nagent:\n  max_turns: 150\n' > "$T/c.yaml"
printf 'model:\n  provider: xai-oauth\n  default: grok-4.3\nfallback_providers:\n- provider: opencode-go\n  model: kimi-k2-6\n- provider: anthropic\n  model: claude\ncredential_pool_strategies:\n  xai-oauth: round_robin\n' \
  | python3 "$REPO/bin/set-model-block" write "$T/c.yaml"
w="$(cat "$T/c.yaml")"
assert_has   "$w" "provider: xai-oauth"         "write sets the new primary"
assert_has   "$w" "provider: opencode-go"       "write sets the fallback chain"
assert_has   "$w" "credential_pool_strategies:" "write sets round-robin"
assert_hasnt "$w" "openai-codex"                "write drops the old model"
assert_has   "$w" "max_turns: 150"              "write preserves non-model keys"
assert_has   "$w" "- hermes-cli"                "write preserves toolsets"
assert_eq "$(python3 "$REPO/bin/set-model-block" read "$T/c.yaml")" \
  "xai-oauth|grok-4.3|opencode-go|kimi-k2-6|anthropic|claude|Y" "read round-trips the model"
rm -rf "$T"

# ---------------------------------------------------------------------------
section "new-agent — model flags render the chosen primary + fallbacks + round-robin"
out="$(bash "$REPO/bin/new-agent" --name TestModel --camp test --tier m --dry-run \
  --provider anthropic --model claude-x --fallback xai-oauth:grok-4.3 --fallback opencode-go:kimi-k2-6 --round-robin 2>&1)"; rc=$?
assert_eq "$rc" "0" "model dry-run exits 0"
td="$(printf '%s' "$out" | python3 -c "import sys,re;t=re.sub(r'\x1b\[[0-9;]*m','',sys.stdin.read());m=re.search(r'dry-run . (\S+)',t);print(m.group(1) if m else '')")"
mc="$(cat "$td/TestModel/.hermes/profiles/testmodel/config.yaml" 2>/dev/null)"
assert_has "$mc" "provider: anthropic"   "primary provider from --provider"
assert_has "$mc" "default: claude-x"     "primary model from --model"
assert_has "$mc" "provider: xai-oauth"   "fallback #1 from --fallback"
assert_has "$mc" "provider: opencode-go" "fallback #2 from --fallback"
assert_has "$mc" "round_robin"           "round-robin from --round-robin"

# ---------------------------------------------------------------------------
section "memory-health-snapshot.py.tmpl — parses + uses the OWN gbrain wrapper"
T="$(mktemp -d)"
A_NAME=Probe A_SLUG=probe A_ROOT="$T/Probe" render "$REPO/templates/memory-health-snapshot.py.tmpl" > "$T/snap.py"
if python3 -c "import ast,sys;ast.parse(open(sys.argv[1]).read())" "$T/snap.py" 2>/dev/null; then ok "snapshot parses"; else bad "snapshot parses"; fi
snap="$(cat "$T/snap.py")"
assert_has   "$snap" '".local" / "bin" / "gbrain"'  "snapshot uses own .local/bin/gbrain wrapper"
assert_hasnt "$snap" "Shared/bin/gbrain"            "snapshot does NOT use the shared wrapper"
rm -rf "$T"

# ---------------------------------------------------------------------------
section "cron-jobs.json.tmpl — renders valid, maintenance is snapshot-fed, git-sync standalone"
T="$(mktemp -d)"
AGENT_NAME=Probe AGENT_ROOT=/tmp/Probe MAINT_ID=m SYNC_ID=s NOW=n \
  python3 -c "import os,re,sys;print(re.sub(r'__([A-Z_]+)__',lambda m:os.environ.get(m.group(1),m.group(0)),open(sys.argv[1]).read()),end='')" \
  "$REPO/templates/cron-jobs.json.tmpl" > "$T/jobs.json"
chk="$(python3 - "$T/jobs.json" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))["jobs"]
m=next((x for x in j if x["name"]=="Daily memory maintenance"),{})
g=next((x for x in j if x.get("script")=="git-sync.sh"),{})
print("VALID" if len(j)==2 else "BADCOUNT")
print("MAINT_OK" if m.get("script")=="memory_health_snapshot.py" and m.get("skill")=="memory-architecture" and not m.get("no_agent") else "MAINT_BAD")
print("SYNC_OK" if g.get("no_agent") is True else "SYNC_BAD")
PY
)"
assert_has "$chk" "VALID"     "renders exactly 2 jobs"
assert_has "$chk" "MAINT_OK"  "maintenance = script(snapshot)+skill, LLM job"
assert_has "$chk" "SYNC_OK"   "git-sync = standalone no_agent job"
rm -rf "$T"

# ---------------------------------------------------------------------------
section "boot-services — a restart re-renders stale normalised scripts (drift self-heal)"
T="$(mktemp -d)"; PR="$T/Probe"; PROF="$PR/.hermes/profiles/probe"
mkdir -p "$PROF/scripts"
# A restart inherits whatever stale rendered copies the agent already has on disk.
echo "STALE git-sync" > "$PROF/scripts/git-sync.sh"
echo "STALE snapshot" > "$PROF/scripts/memory_health_snapshot.py"
# Run the boot's first step. Subshell: boot-services.sh redefines say/ok/warn, so
# keep its sourcing out of this harness's ok() PASS counter.
( source "$REPO/lib/boot-services.sh"
  NAME=Probe SLUG=probe AGENT_ROOT="$PR" PROFILE="$PROF" render_normalised_scripts ) >/dev/null 2>&1
want_gs="$(A_NAME=Probe A_SLUG=probe A_ROOT="$PR" render "$REPO/templates/git-sync.sh.tmpl")"
want_ms="$(A_NAME=Probe A_SLUG=probe A_ROOT="$PR" render "$REPO/templates/memory-health-snapshot.py.tmpl")"
assert_eq "$(cat "$PROF/scripts/git-sync.sh")"               "$want_gs" "boot re-renders stale git-sync.sh to match template"
assert_eq "$(cat "$PROF/scripts/memory_health_snapshot.py")" "$want_ms" "boot re-renders stale snapshot to match template"
[ -x "$PROF/scripts/git-sync.sh" ] && ok "re-rendered git-sync.sh stays executable" || bad "re-rendered git-sync.sh stays executable"
# Guard: a missing template (partial checkout) must NOT wipe the working script.
echo "KEEP" > "$PROF/scripts/git-sync.sh"
( source "$REPO/lib/boot-services.sh"
  NAME=Probe SLUG=probe AGENT_ROOT="$PR" PROFILE="$PROF" REPO="$T/no-templates" render_normalised_scripts ) >/dev/null 2>&1
assert_eq "$(cat "$PROF/scripts/git-sync.sh")" "KEEP" "missing template leaves the existing script untouched"
cd "$REPO"; rm -rf "$T"

# ---------------------------------------------------------------------------
printf '\n\033[36mSummary\033[0m  \033[32m%d pass\033[0m  \033[31m%d fail\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

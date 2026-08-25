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
         .hermes/profiles/test/cron/jobs.json \
         .hermes/profiles/test/cron/jobs.definition.json \
         .hermes/profiles/test/scripts/s.sh \
         .hermes/sandbox/test.sb README.md; do echo x > "$f"; done
for f in .hermes/profiles/test/.env .hermes/profiles/test/auth.json \
         .hermes/profiles/test/google_token.json .hermes/profiles/test/skills/x/SKILL.md \
         .hermes/honcho/honcho/compose.yml .home/.gbrain/brain.pglite \
         vault/brain/n.md workspace/clone/c.js; do echo SECRET > "$f"; done
git init -q && git add -A 2>/dev/null
TR="$(git ls-files)"
for want in .hermes/profiles/test/config.yaml .hermes/profiles/test/SOUL.md \
            .hermes/profiles/test/memories/MEMORY.md \
            .hermes/profiles/test/cron/jobs.definition.json \
            .hermes/profiles/test/skills/x/SKILL.md \
            vault/brain/n.md \
            .hermes/sandbox/test.sb README.md; do assert_has "$TR" "$want" "tracks $want"; done
assert_hasnt "$TR" "honcho.json" "excludes retired honcho.json (Honcho decommissioned)"
assert_hasnt "$TR" ".hermes/profiles/test/cron/jobs.json" "excludes volatile cron runtime registry"
# Entire-vault canon (Chief decision 2026-08-06): vault/ and profile skills/ are
# tracked identity; secrets, runtime homes, and workspace clones stay out.
for deny in .env auth.json google_token.json workspace/ honcho/honcho .pglite; do
  assert_hasnt "$TR" "$deny" "excludes $deny"; done
cd "$REPO"; rm -rf "$T"

# ---------------------------------------------------------------------------
section "git-sync.sh — silent success, secret tripwire, no force-push"
T="$(mktemp -d)"; cd "$T"
A_ROOT="$T/repo" A_SLUG=test A_NAME=Test render "$REPO/templates/git-sync.sh.tmpl" > sync.sh; chmod +x sync.sh
if grep -qE 'push .*(--force|-f)\b' sync.sh; then bad "rendered script never force-pushes"; else ok "rendered script never force-pushes"; fi
# Scar 2026-08-06: bare git push hangs non-interactively — template must header-push only.
if grep -qE 'if (! )?git push -q origin' sync.sh; then bad "rendered script never bare-pushes first"; else ok "rendered script never bare-pushes first"; fi
assert_has "$(cat sync.sh)" 'extraheader=AUTHORIZATION' "rendered script uses HTTPS auth header push"
assert_has "$(cat sync.sh)" 'GH_TOKEN' "rendered script accepts GH_TOKEN from the environment"
# Push-on default: Chief standing approval 2026-07-17, shipped 2026-08-25.
# Without a token it still only commits locally and says so — never hangs.
assert_has "$(cat sync.sh)" 'AGENT_GIT_SYNC_PUSH_APPROVED:-1' "SuperHermes default pushes when a token is available"
assert_hasnt "$(cat sync.sh)" 'AGENT_GIT_SYNC_PUSH_APPROVED:-0' "withhold-by-default is gone (opt out via =0)"
assert_hasnt "$(cat sync.sh)" '/Users/agents/' "SuperHermes template stays free of machine-specific home paths"
assert_has "$(cat sync.sh)" 'Camp-specific secret plumbing' "template documents deployment overlay boundary"
if bash -n sync.sh; then ok "rendered script bash -n clean"; else bad "rendered script bash -n clean"; fi
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
out="$(bash "$REPO/bin/new-agent" --name TestUnit --camp test --dry-run 2>&1)"; rc=$?
assert_eq "$rc" "0" "dry-run exits 0"
assert_has "$out" "testunit.sb (compiles)"  "sandbox compiles"
assert_has "$out" "root .gitignore"          "renders normalised root .gitignore"
assert_has "$out" "git initialised at root"  "initialises git at root"
assert_has "$out" "memory-maintenance"        "renders memory-maintenance cron"
assert_has "$out" "DRY-RUN complete"         "completes cleanly"
td="$(printf '%s' "$out" | python3 -c "import sys,re;t=re.sub(r'\x1b\[[0-9;]*m','',sys.stdin.read());m=re.search(r'dry-run . (\S+)',t);print(m.group(1) if m else '')")"
# Production-proven anatomy: brain taxonomy + identity docs + operational scripts.
TU="$td/TestUnit"
for want in vault/brain/HOME.md vault/brain/README.md vault/brain/continuity \
            vault/brain/architecture vault/brain/conversations \
            workspace/repos workspace/worktrees \
            .hermes/profiles/testunit/EVOLUTION.md .hermes/profiles/testunit/DIARY.md; do
  [ -e "$TU/$want" ] && ok "scaffolds $want" || bad "scaffolds $want"
done
assert_has "$(cat "$TU/vault/brain/HOME.md")" "PRIMARY SUBJECT" "brain HOME carries the filing rule"
for scr in gbrain-autosync.sh full-backup.sh; do
  s="$TU/.hermes/profiles/testunit/scripts/$scr"
  [ -x "$s" ] && bash -n "$s" && ok "renders executable $scr (bash -n clean)" || bad "renders executable $scr (bash -n clean)"
done
assert_has "$(cat "$TU/.hermes/profiles/testunit/scripts/full-backup.sh")" 'unzip -t' "full-backup is integrity-gated"
assert_hasnt "$(cat "$TU/.hermes/profiles/testunit/cron/jobs.json")" '__BACKUP_MINUTE__' "backup cron minute is substituted (staggered)"
cfgchk="$(python3 - "$TU/.hermes/profiles/testunit/config.yaml" <<'PY'
import sys
text = open(sys.argv[1]).read()
print("AUX_OK" if "__AUX_PROVIDER__" not in text and "auxiliary:" in text else "AUX_BAD")
print("BWS_OK" if "__BWS_" not in text else "BWS_BAD")
print("DENY_OK" if "csrutil disable" in text else "DENY_BAD")
PY
)"
assert_has "$cfgchk" "AUX_OK" "config renders auxiliary routing with substituted models"
assert_has "$cfgchk" "BWS_OK" "secrets manager stays disabled without an operator project id"
assert_has "$cfgchk" "DENY_OK" "config carries the hardline deny floor"
pl="$(cat "$td/LaunchAgents/ai.hermes.gateway-testunit.plist" 2>/dev/null)"
assert_has "$pl" "hermes-gateway-launch" "gateway plist launches via the operator's gateway launcher"
assert_hasnt "$pl" "hermes_cli.main"                "gateway plist does not bypass shared launcher"
assert_has "$pl" "<string>testunit</string>"        "gateway plist passes slug to launcher"
configured_soft_file_limit="$(python3 - "$td/LaunchAgents/ai.hermes.gateway-testunit.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as property_list_file:
    property_list = plistlib.load(property_list_file)
print(property_list.get("SoftResourceLimits", {}).get("NumberOfFiles", 0))
PY
)"
[ "$configured_soft_file_limit" -ge 4096 ] \
  && ok "new gateway jobs have file-descriptor headroom" \
  || bad "new gateway jobs must allow at least 4096 open files"
configured_max_turns="$(python3 - "$td/TestUnit/.hermes/profiles/testunit/config.yaml" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"(?m)^agent:\s*\n(?:^[ \t]+.*\n)*?^[ \t]+max_turns:\s*([0-9]+)", text)
print(match.group(1) if match else "")
PY
)"
[ "$configured_max_turns" = "200" ] && ok "new agents get the long-run 200-turn budget" || bad "new agents get the long-run 200-turn budget — got $configured_max_turns"
configured_busy_input_mode="$(python3 - "$td/TestUnit/.hermes/profiles/testunit/config.yaml" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"(?m)^display:\s*\n(?:^[ \t]+.*\n)*?^[ \t]+busy_input_mode:\s*([^\s#]+)", text)
print(match.group(1) if match else "")
PY
)"
assert_eq "$configured_busy_input_mode" "steer" "new agents steer busy Telegram follow-ups by default"
python3 -m json.tool "$REPO/templates/agent-template.json" >/dev/null 2>&1 \
  && ok "agent template manifest parses" || bad "agent template manifest parses"
AGENTS_ROOT=""; [ -f "$REPO/superhermes.conf" ] && . "$REPO/superhermes.conf" || . "$REPO/superhermes.conf.example"
[ -d "${AGENTS_ROOT:-/nonexistent}/TestUnit" ] && bad "dry-run left a real agent dir!" || ok "dry-run leaves no real agent dir"
# GBrain at birth is Postgres standard (never PGLite / never stale :11534).
gcfg="$(cat "$td/TestUnit/.hermes/profiles/testunit/home/.gbrain/config.json" 2>/dev/null)"
assert_has   "$gcfg" '"engine": "postgres"'              "gbrain config engine is postgres"
assert_has   "$gcfg" 'postgres://gbrain_testunit@'       "gbrain config database_url uses gbrain_<slug>"
assert_has   "$gcfg" '127.0.0.1:11434/v1'                "gbrain config embed URL is Ollama :11434/v1"
assert_has   "$gcfg" 'gbrain-base-v2'                    "gbrain config sets schema_pack"
assert_hasnt "$gcfg" 'pglite'                            "gbrain config has no pglite"
assert_hasnt "$gcfg" '11534'                             "gbrain config does not use stale :11534"
wrap="$(cat "$td/TestUnit/.local/bin/gbrain" 2>/dev/null)"
assert_has   "$wrap" '11434/v1'                          "gbrain wrapper defaults OLLAMA to :11434/v1"
assert_hasnt "$wrap" '11534'                             "gbrain wrapper does not default stale :11534"
mcg="$(python3 - "$td/TestUnit/.hermes/profiles/testunit/config.yaml" <<'PY'
import sys
text = open(sys.argv[1]).read().splitlines()
out = []
grab = False
for line in text:
    if line.rstrip() == "  gbrain:":
        grab = True
        out.append(line)
        continue
    if grab:
        if line.startswith("    "):
            out.append(line)
        else:
            break
print("\n".join(out))
PY
)"
assert_has "$mcg" "args:" "gbrain MCP has args"
assert_has "$mcg" "- serve" "gbrain MCP serves"
assert_has "$mcg" "enabled: true" "gbrain MCP enabled"
assert_has "$mcg" "HOME:" "gbrain MCP pins HOME"
assert_has "$mcg" "HERMES_HOME:" "gbrain MCP pins HERMES_HOME"

# ---------------------------------------------------------------------------
section "set-busy-input-mode — clone configs normalize to steer without collateral edits"
T="$(mktemp -d)"
cat > "$T/config.yaml" <<'YAML'
model:
  provider: openai-codex
  default: gpt-5.5

display:
  busy_input_mode: interrupt
  busy_ack_enabled: false

telegram:
  enabled: true
YAML
before_model="$(python3 -c 'import sys; text=open(sys.argv[1]).read(); print(text.split("display:", 1)[0], end="")' "$T/config.yaml")"
python3 "$REPO/bin/set-busy-input-mode" "$T/config.yaml" steer; rc=$?
normalized="$(cat "$T/config.yaml")"
after_model="$(python3 -c 'import sys; text=open(sys.argv[1]).read(); print(text.split("display:", 1)[0], end="")' "$T/config.yaml")"
assert_eq "$rc" "0" "clone normalizer exits 0"
assert_has "$normalized" "busy_input_mode: steer" "clone interrupt mode becomes steer"
assert_has "$normalized" "busy_ack_enabled: false" "clone normalizer preserves sibling display settings"
assert_eq "$before_model" "$after_model" "clone normalizer preserves preceding config"
assert_eq "$(printf '%s\n' "$normalized" | grep -c 'busy_input_mode:')" "1" "clone normalizer leaves one busy-input key"

printf 'display:\r\n  busy_input_mode: interrupt\r\n' > "$T/crlf.yaml"
cp "$T/crlf.yaml" "$T/crlf.before"
python3 "$REPO/bin/set-busy-input-mode" "$T/crlf.yaml" steer >/dev/null 2>&1; rc=$?
assert_eq "$rc" "2" "normalizer rejects CRLF instead of rewriting unrelated bytes"
cmp -s "$T/crlf.before" "$T/crlf.yaml"; rc=$?
assert_eq "$rc" "0" "CRLF rejection leaves config byte-identical"

cat > "$T/inline.yaml" <<'YAML'
display: {busy_input_mode: interrupt}
YAML
cp "$T/inline.yaml" "$T/inline.before"
python3 "$REPO/bin/set-busy-input-mode" "$T/inline.yaml" steer >/dev/null 2>&1; rc=$?
assert_eq "$rc" "2" "normalizer rejects unsupported inline display mappings"
cmp -s "$T/inline.before" "$T/inline.yaml"; rc=$?
assert_eq "$rc" "0" "inline display rejection leaves config byte-identical"

cat > "$T/blank.yaml" <<'YAML'
display:
  busy_input_mode:
YAML
cp "$T/blank.yaml" "$T/blank.before"
python3 "$REPO/bin/set-busy-input-mode" "$T/blank.yaml" steer >/dev/null 2>&1; rc=$?
assert_eq "$rc" "2" "normalizer rejects blank busy-input values"
cmp -s "$T/blank.before" "$T/blank.yaml"; rc=$?
assert_eq "$rc" "0" "blank-value rejection leaves config byte-identical"

cat > "$T/non-scalar.yaml" <<'YAML'
display:
  busy_input_mode: {interrupt}
telegram:
  bot_token: SECRET_REFERENCE
YAML
cp "$T/non-scalar.yaml" "$T/non-scalar.before"
python3 "$REPO/bin/set-busy-input-mode" "$T/non-scalar.yaml" steer >/dev/null 2>&1; rc=$?
assert_eq "$rc" "2" "normalizer rejects non-scalar busy-input values"
cmp -s "$T/non-scalar.before" "$T/non-scalar.yaml"; rc=$?
assert_eq "$rc" "0" "non-scalar rejection leaves config byte-identical"
rm -rf "$T"

# ---------------------------------------------------------------------------
section "ensure-gbrain-postgres — config-only writes standard shape"
T="$(mktemp -d)"
python3 "$REPO/bin/ensure-gbrain-postgres" --slug probeagent --agent-root "$T/Probe" \
  --profile-home "$T/Probe/.hermes/profiles/probeagent/home" --config-only >/dev/null
gcfg="$(cat "$T/Probe/.hermes/profiles/probeagent/home/.gbrain/config.json")"
assert_has "$gcfg" '"engine": "postgres"' "ensure-gbrain-postgres writes postgres engine"
assert_has "$gcfg" 'gbrain_probeagent' "ensure-gbrain-postgres db id is gbrain_<slug>"
assert_has "$gcfg" '11434/v1' "ensure-gbrain-postgres embed :11434/v1"
assert_hasnt "$gcfg" 'pglite' "ensure-gbrain-postgres never pglite"
rm -rf "$T"
# Client-scoped identity must match gbrain_<client>_<slug>
T="$(mktemp -d)"
python3 "$REPO/bin/ensure-gbrain-postgres" --slug hunter --client-id jake \
  --agent-root "$T/Clients/Jake/Hunter" \
  --profile-home "$T/Clients/Jake/Hunter/.hermes/profiles/hunter/home" --config-only >/dev/null
gcfg="$(cat "$T/Clients/Jake/Hunter/.hermes/profiles/hunter/home/.gbrain/config.json")"
assert_has "$gcfg" 'gbrain_jake_hunter' "client gbrain identity is gbrain_<client>_<slug>"
assert_hasnt "$gcfg" 'gbrain_hunter@' "client identity is not bare gbrain_<slug>"
rm -rf "$T"

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
out="$(bash "$REPO/bin/new-agent" --name TestModel --camp test --dry-run \
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
section "gbrain-wrapper.tmpl — derives its agent root after a profile move"
T="$(mktemp -d)"; ROOT="$T/Agents/Clients/Jake/Hunter"; MOVED="$T/Agents/Clients/Moved/Hunter"
mkdir -p "$ROOT/.local/bin"
A_NAME="Jake's Hunter" A_SLUG=hunter A_ROOT="$ROOT" render "$REPO/templates/gbrain-wrapper.tmpl" > "$ROOT/.local/bin/gbrain"
wrapper="$(cat "$ROOT/.local/bin/gbrain")"
assert_hasnt "$wrapper" "$ROOT" "wrapper does not bake the original agent root"
assert_hasnt "$wrapper" '__AGENT_ROOT__' "wrapper does not leave the root placeholder"
mkdir -p "$(dirname "$MOVED")"
mv "$ROOT" "$MOVED"
# Observe ROOT after a move. Stub exec so the wrapper does not need bun/gbrain.
sed -i.bak 's|^exec .*|printf %s "$ROOT"; exit 0|' "$MOVED/.local/bin/gbrain"
chmod +x "$MOVED/.local/bin/gbrain"
resolved="$("$MOVED/.local/bin/gbrain")"
assert_eq "$resolved" "$MOVED" "moved wrapper resolves ROOT to the new agent tree"
rm -rf "$T"

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
section "cron registry snapshot — durable definitions exclude runtime state"
T="$(mktemp -d)"
PROFILE="$T/Test/.hermes/profiles/test"
mkdir -p "$PROFILE/cron" "$PROFILE/scripts"
A_NAME=Test A_SLUG=test A_ROOT="$T/Test" render "$REPO/templates/cron-registry-snapshot.py.tmpl" > "$PROFILE/scripts/cron_registry_snapshot.py"
cat > "$PROFILE/cron/jobs.json" <<'JSON'
{
  "jobs": [{
    "id": "daily",
    "name": "Daily identity git-sync",
    "script": "git-sync.sh",
    "no_agent": true,
    "schedule": {"kind": "cron", "expr": "0 0 * * *"},
    "enabled": true,
    "state": "scheduled",
    "created_at": "2026-07-11T00:00:00Z",
    "next_run_at": "2026-07-12T00:00:00Z",
    "last_run_at": "2026-07-11T00:00:00Z",
    "last_status": "ok",
    "last_error": null,
    "fire_claim": {"at": "2026-07-11T00:00:00Z", "by": "host:1"},
    "repeat": {"times": 10, "completed": 3}
  }],
  "updated_at": "2026-07-11T00:00:01Z"
}
JSON
out="$(python3 "$PROFILE/scripts/cron_registry_snapshot.py" 2>&1)"; rc=$?
assert_eq "$rc" "0" "snapshot exits 0"
assert_eq "$out" "" "snapshot is silent"
definition="$(cat "$PROFILE/cron/jobs.definition.json" 2>/dev/null)"
assert_has "$definition" '"name": "Daily identity git-sync"' "snapshot keeps routine definition"
assert_has "$definition" '"expr": "0 0 * * *"' "snapshot keeps routine schedule"
assert_hasnt "$definition" 'last_run_at' "snapshot removes last_run_at"
assert_hasnt "$definition" 'fire_claim' "snapshot removes fire_claim"
assert_hasnt "$definition" 'updated_at' "snapshot removes registry updated_at"
assert_hasnt "$definition" '"completed"' "snapshot removes repeat progress"
rm "$PROFILE/cron/jobs.json"
python3 "$PROFILE/scripts/cron_registry_snapshot.py" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "0" "missing runtime registry restores from durable definition"
assert_has "$(cat "$PROFILE/cron/jobs.json")" '"name": "Daily identity git-sync"' "restored runtime registry keeps job definition"
assert_hasnt "$(cat "$PROFILE/cron/jobs.json")" 'last_run_at' "restored runtime registry starts without stale execution state"
cp "$PROFILE/cron/jobs.definition.json" "$T/before.json" 2>/dev/null || true
printf '{broken' > "$PROFILE/cron/jobs.json"
python3 "$PROFILE/scripts/cron_registry_snapshot.py" >/dev/null 2>&1; rc=$?
[ "$rc" != "0" ] && ok "malformed registry fails closed" || bad "malformed registry must fail closed"
cmp -s "$T/before.json" "$PROFILE/cron/jobs.definition.json" \
  && ok "malformed registry preserves last good definition" \
  || bad "malformed registry overwrote last good definition"
rm -rf "$T"

# ---------------------------------------------------------------------------
section "identity git-sync — scheduler metadata never dirties the identity repo"
T="$(mktemp -d)"; ROOT="$T/Test"; PROFILE="$ROOT/.hermes/profiles/test"
mkdir -p "$PROFILE/cron" "$PROFILE/scripts"
A_NAME=Test A_SLUG=test A_ROOT="$ROOT" render "$REPO/templates/gitignore.tmpl" > "$ROOT/.gitignore"
A_NAME=Test A_SLUG=test A_ROOT="$ROOT" render "$REPO/templates/cron-registry-snapshot.py.tmpl" > "$PROFILE/scripts/cron_registry_snapshot.py"
A_NAME=Test A_SLUG=test A_ROOT="$ROOT" render "$REPO/templates/git-sync.sh.tmpl" > "$PROFILE/scripts/git-sync.sh"
chmod +x "$PROFILE/scripts/cron_registry_snapshot.py" "$PROFILE/scripts/git-sync.sh"
cat > "$PROFILE/cron/jobs.json" <<'JSON'
{"jobs":[{"id":"daily","name":"Daily identity git-sync","script":"git-sync.sh","no_agent":true,"schedule":{"kind":"cron","expr":"0 0 * * *"},"enabled":true,"last_run_at":null,"last_status":null}],"updated_at":"one"}
JSON
python3 "$PROFILE/scripts/cron_registry_snapshot.py"
git -C "$ROOT" init -q
git -C "$ROOT" add -A
git -C "$ROOT" -c user.name=t -c user.email=t@t commit -qm init
python3 - "$PROFILE/cron/jobs.json" <<'PY'
import json,sys
p=sys.argv[1]; data=json.load(open(p)); data["jobs"][0]["last_run_at"]="2026-07-11T00:00:00Z"; data["jobs"][0]["last_status"]="ok"; data["updated_at"]="two"; open(p,"w").write(json.dumps(data))
PY
n0="$(git -C "$ROOT" rev-list --count HEAD)"
AGENT_GIT_ROOT="$ROOT" bash "$PROFILE/scripts/git-sync.sh" >/dev/null 2>&1; rc=$?
n1="$(git -C "$ROOT" rev-list --count HEAD)"
assert_eq "$rc" "0" "metadata-only sync exits 0"
assert_eq "$n1" "$n0" "metadata-only sync creates no commit"
assert_eq "$(git -C "$ROOT" status --porcelain)" "" "metadata-only scheduler write leaves repo clean"
python3 - "$PROFILE/cron/jobs.json" <<'PY'
import json,sys
p=sys.argv[1]; data=json.load(open(p)); data["jobs"][0]["schedule"]["expr"]="30 0 * * *"; data["updated_at"]="three"; open(p,"w").write(json.dumps(data))
PY
AGENT_GIT_ROOT="$ROOT" bash "$PROFILE/scripts/git-sync.sh" >/dev/null 2>&1; rc=$?
n2="$(git -C "$ROOT" rev-list --count HEAD)"
assert_eq "$rc" "0" "definition change sync exits 0"
assert_eq "$n2" "$((n1+1))" "definition change creates one commit"
assert_eq "$(git -C "$ROOT" status --porcelain)" "" "definition change leaves repo clean"
assert_has "$(git -C "$ROOT" show HEAD:.hermes/profiles/test/cron/jobs.definition.json)" '30 0 * * *' "commit stores updated routine definition"
rm -rf "$T"

# ---------------------------------------------------------------------------
section "migrate-cron-registry-git — upgrades an existing agent without a roster"
T="$(mktemp -d)"; ROOT="$T/Agents/Test"; PROFILE="$ROOT/.hermes/profiles/test"
mkdir -p "$PROFILE/cron" "$PROFILE/scripts"
A_NAME=Test A_SLUG=test A_ROOT="$ROOT" render "$REPO/templates/gitignore.tmpl" \
  | sed 's#jobs.definition.json#jobs.json#' > "$ROOT/.gitignore"
printf '{"jobs":[{"id":"memory","name":"Daily memory maintenance","prompt":"unbounded","skill":"memory-architecture","script":"memory_health_snapshot.py","schedule":{"kind":"cron","expr":"0 23 * * *"},"enabled":true},{"id":"daily","name":"Daily identity git-sync","script":"git-sync.sh","no_agent":true,"schedule":{"kind":"cron","expr":"0 0 * * *"},"enabled":true,"last_run_at":"2026-07-11T00:00:00Z","last_status":"ok"}],"updated_at":"runtime"}\n' > "$PROFILE/cron/jobs.json"
printf 'agent:\n  max_turns: 500\n' > "$PROFILE/config.yaml"
printf 'legacy sync\n' > "$PROFILE/scripts/git-sync.sh"
git -C "$ROOT" init -q
git -C "$ROOT" add -A
git -C "$ROOT" -c user.name=t -c user.email=t@t commit -qm init
AGENTS_ROOT="$T/Agents" bash "$REPO/bin/migrate-cron-registry-git" --name Test >/dev/null 2>&1; rc=$?
assert_eq "$rc" "0" "migration exits 0"
tracked="$(git -C "$ROOT" ls-files)"
assert_has "$tracked" ".hermes/profiles/test/cron/jobs.definition.json" "migration tracks durable definition"
assert_hasnt "$tracked" ".hermes/profiles/test/cron/jobs.json" "migration untracks live registry"
assert_has "$(cat "$ROOT/.gitignore")" "jobs.definition.json" "migration updates gitignore"
assert_has "$(cat "$PROFILE/scripts/git-sync.sh")" "cron_registry_snapshot.py" "migration installs snapshot-aware git-sync"
assert_has "$(cat "$PROFILE/config.yaml")" "max_turns: 200" "migration bounds runaway model-turn budgets to 200"
assert_has "$(cat "$PROFILE/cron/jobs.definition.json")" '"workdir": "'"$ROOT"'"' "migration scopes memory maintenance to the agent root"
assert_has "$(cat "$PROFILE/cron/jobs.definition.json")" 'at most 8 model calls' "migration bounds memory maintenance model calls"
[ -x "$PROFILE/scripts/cron_registry_snapshot.py" ] && ok "migration installs executable snapshot helper" || bad "migration installs executable snapshot helper"
AGENT_GIT_ROOT="$ROOT" bash "$PROFILE/scripts/git-sync.sh" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "0" "migrated git-sync commits the upgrade"
printf '{"jobs":[{"id":"daily","name":"Daily identity git-sync","script":"git-sync.sh","no_agent":true,"schedule":{"kind":"cron","expr":"0 0 * * *"},"enabled":true,"last_run_at":"2026-07-12T00:00:00Z","last_status":"ok"}],"updated_at":"later"}\n' > "$PROFILE/cron/jobs.json"
assert_eq "$(git -C "$ROOT" status --porcelain)" "" "migrated runtime metadata stays clean"
rm -rf "$T"

# ---------------------------------------------------------------------------
section "cron-jobs.json.tmpl — renders valid, maintenance is snapshot-fed, git-sync standalone"
T="$(mktemp -d)"
AGENT_NAME=Probe AGENT_ROOT=/tmp/Probe MAINT_ID=m SYNC_ID=s AUTOSYNC_ID=a BACKUP_ID=b BACKUP_MINUTE=17 NOW=n \
  python3 -c "import os,re,sys;print(re.sub(r'__([A-Z_]+)__',lambda m:os.environ.get(m.group(1),m.group(0)),open(sys.argv[1]).read()),end='')" \
  "$REPO/templates/cron-jobs.json.tmpl" > "$T/jobs.json"
chk="$(python3 - "$T/jobs.json" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))["jobs"]
m=next((x for x in j if x["name"]=="Daily memory maintenance"),{})
g=next((x for x in j if x.get("script")=="git-sync.sh"),{})
a=next((x for x in j if x.get("script")=="gbrain-autosync.sh"),{})
b=next((x for x in j if x.get("script")=="full-backup.sh"),{})
print("VALID" if len(j)==4 else "BADCOUNT")
print("AUTOSYNC_OK" if a.get("no_agent") is True and a.get("schedule",{}).get("expr")=="*/30 * * * *" else "AUTOSYNC_BAD")
print("BACKUP_OK" if b.get("no_agent") is True and b.get("schedule",{}).get("expr")=="17 3 * * *" else "BACKUP_BAD")
print("MAINT_OK" if m.get("script")=="memory_health_snapshot.py" and m.get("skill")=="memory-architecture" and not m.get("no_agent") else "MAINT_BAD")
print("MAINT_SCOPED" if m.get("workdir")=="/tmp/Probe" and m.get("enabled_toolsets")==["file","terminal","session_search","memory"] else "MAINT_UNSCOPED")
print("MAINT_BOUNDED" if "one session_search discovery with limit=1" in m.get("prompt","") and "at most 8 model calls" in m.get("prompt","") else "MAINT_UNBOUNDED")
print("SYNC_OK" if g.get("no_agent") is True else "SYNC_BAD")
PY
)"
assert_has "$chk" "VALID"     "renders exactly 4 jobs"
assert_has "$chk" "AUTOSYNC_OK" "gbrain autosync = no_agent every 30m"
assert_has "$chk" "BACKUP_OK"   "full backup = no_agent daily at the staggered minute"
assert_has "$chk" "MAINT_OK"  "maintenance = script(snapshot)+skill, LLM job"
assert_has "$chk" "MAINT_SCOPED" "maintenance is restricted to its agent root and necessary toolsets"
assert_has "$chk" "MAINT_BOUNDED" "maintenance prompt carries explicit retrieval and model-call budgets"
assert_has "$chk" "SYNC_OK"   "git-sync = standalone no_agent job"
rm -rf "$T"

# ---------------------------------------------------------------------------
section "boot-services — a restart re-renders stale normalised scripts (drift self-heal)"
T="$(mktemp -d)"; PR="$T/Probe"; PROF="$PR/.hermes/profiles/probe"
mkdir -p "$PROF/scripts" "$PROF/cron"
printf '{"jobs":[],"updated_at":"runtime"}\n' > "$PROF/cron/jobs.json"
# A restart inherits whatever stale rendered copies the agent already has on disk.
echo "STALE git-sync" > "$PROF/scripts/git-sync.sh"
echo "STALE snapshot" > "$PROF/scripts/memory_health_snapshot.py"
# Run the boot's first step. Subshell: boot-services.sh redefines say/ok/warn, so
# keep its sourcing out of this harness's ok() PASS counter.
( source "$REPO/lib/boot-services.sh"
  NAME=Probe SLUG=probe AGENT_ROOT="$PR" PROFILE="$PROF" render_normalised_scripts ) >/dev/null 2>&1
want_gs="$(A_NAME=Probe A_SLUG=probe A_ROOT="$PR" render "$REPO/templates/git-sync.sh.tmpl")"
want_ms="$(A_NAME=Probe A_SLUG=probe A_ROOT="$PR" render "$REPO/templates/memory-health-snapshot.py.tmpl")"
want_cs="$(A_NAME=Probe A_SLUG=probe A_ROOT="$PR" render "$REPO/templates/cron-registry-snapshot.py.tmpl")"
assert_eq "$(cat "$PROF/scripts/git-sync.sh")"               "$want_gs" "boot re-renders stale git-sync.sh to match template"
assert_eq "$(cat "$PROF/scripts/memory_health_snapshot.py")" "$want_ms" "boot re-renders stale snapshot to match template"
assert_eq "$(cat "$PROF/scripts/cron_registry_snapshot.py")" "$want_cs" "boot renders cron registry snapshot helper"
assert_has "$(cat "$PROF/cron/jobs.definition.json")" '"jobs": []' "boot creates durable cron definitions for existing agents"
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

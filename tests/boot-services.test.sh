#!/usr/bin/env bash
# TDD test for lib/boot-services.sh. Mocks every external (launchctl/curl/bun/
# git/python3/sleep/docker) via a PATH shim dir, runs boot_agent_services against
# a throwaway fake agent, and asserts the boot sequence. No real launchd.
#
# Memory is GBrain only — the sequence must never touch Docker.
#
# Run: bash tests/boot-services.test.sh   (exit 0 = pass)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO="$(cd "$HERE/.." && pwd)"   # SuperHermes
LIB="$REPO/lib/boot-services.sh"

fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -f "$LIB" ] || fail "missing $LIB"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
calls="$tmp/calls.log"; : > "$calls"

# ---- PATH mocks: every external logs its argv and exits 0 ----
mock="$tmp/bin"; mkdir -p "$mock"
for tool in docker launchctl curl bun git python3 sleep; do
  { printf '#!/usr/bin/env bash\n'; printf 'echo "%s $*" >> "%s"\n' "$tool" "$calls"; printf 'sub=${1##*/}; sub=${sub//-/_}; sub=${sub//./_}; key=SHIM_EXIT_%s_$sub; exit ${!key:-0}\n' "$tool"; } > "$mock/$tool"
  chmod +x "$mock/$tool"
done

# ---- fake agent ----
export AGENTS_ROOT="$tmp/agents"
export NAME="Probe" SLUG="probe"
export AGENT_ROOT="$AGENTS_ROOT/Probe"
export PROFILE="$AGENT_ROOT/.hermes/profiles/probe"
export LA="$tmp/LaunchAgents"
export DISK_FLOOR_GB=0
mkdir -p "$PROFILE" "$AGENT_ROOT/.local/bin" "$LA" "$AGENT_ROOT/vault/brain"
printf 'TELEGRAM_BOT_TOKEN=\n' > "$PROFILE/.env"; chmod 644 "$PROFILE/.env"
export SECRETS_ENV="$AGENTS_ROOT/secrets.env"
printf 'BWS_ACCESS_TOKEN=test-token-xyz\n' > "$SECRETS_ENV"
{ printf '#!/bin/sh\n'; printf 'sub=${1##*/}; sub=${sub//-/_}; sub=${sub//./_}; key=SHIM_EXIT_%s_$sub; exit ${!key:-0}\n' "$tool"; } > "$AGENT_ROOT/.local/bin/gbrain"; chmod +x "$AGENT_ROOT/.local/bin/gbrain"

# ---- run with mocks on PATH ----
# shellcheck disable=SC1090
source "$LIB" || fail "could not source $LIB"
PATH="$mock:$PATH" boot_agent_services || fail "boot_agent_services returned non-zero"

# ---- assertions: the boot sequence happened ----
grep -q "cron_registry_snapshot.py" "$calls"                    || fail "normalised scripts not reconciled"
grep -q "launchctl setenv BWS_ACCESS_TOKEN" "$calls"            || fail "BWS token not asserted (credentials fix)"
grep -q "bun add -g" "$calls"                                   || fail "gbrain not installed"
grep -q "launchctl bootstrap gui/.*gateway-probe" "$calls"      || fail "gateway not bootstrapped"
grep -q "launchctl start gui/.*gateway-probe" "$calls"          || fail "gateway not started"
grep -q "verify-agents --agent Probe" "$calls"                   || fail "verify-agents not run"

# ---- assertion: Honcho is decommissioned — nothing may touch Docker ----
grep -q "^docker " "$calls" && fail "boot sequence must not call docker (Honcho decommissioned)"

# ---- assertion: the .env got tightened to 600 (config fix) ----
perms="$(stat -f '%Lp' "$PROFILE/.env" 2>/dev/null || stat -c '%a' "$PROFILE/.env")"
[ "$perms" = "600" ] || fail ".env not chmod 600 (got $perms)"

echo "PASS: boot-services sequence verified ($(wc -l < "$calls" | tr -d ' ') mock calls)"

# Boundary faults run independently so every planted failure is visible.
failed=0
run_case() {
  local name="$1" expected="$2" fault="$3" value="$4" forbidden="$5"
  : > "$calls"
  local output rc=0
  output="$(export "$fault=$value"; PATH="$mock:$PATH" boot_agent_services 2>&1)" || rc=$?
  if { [ "$expected" = fail ] && [ "$rc" -eq 0 ]; } ||
     { [ "$expected" = pass ] && [ "$rc" -ne 0 ]; } ||
     { [ -n "$forbidden" ] && grep -Eq "$forbidden" "$calls"; } ||
     [[ "$output" == *test-token-xyz* ]] ||
     { [ "$expected" = fail ] && [[ "$output" == *"invariants pass"* ]]; }; then
    echo "FAIL: $name (status $rc)"; failed=$((failed+1))
  else
    echo "PASS: $name"
  fi
}
run_case verify_failure_not_ready fail SHIM_EXIT_python3_verify_agents 1 ''
run_case install_failure_stops_seed fail SHIM_EXIT_bun_add 1 'gbrain (import|embed)'
run_case bootstrap_failure_stops_start fail SHIM_EXIT_launchctl_bootstrap 1 'launchctl start|verify-agents'
run_case already_running_ok pass SHIM_EXIT_launchctl_bootstrap 5 ''
run_case cron_reconcile_failure_fatal fail SHIM_EXIT_python3_cron_registry_snapshot_py 1 ''
run_case no_secret_in_output pass SHIM_EXIT_bun_add 0 ''
[ "$failed" -eq 0 ]

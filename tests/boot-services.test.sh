#!/usr/bin/env bash
# TDD test for lib/boot-services.sh. Mocks every external (docker/launchctl/curl/
# bun/git/python3/sleep) via a PATH shim dir, runs boot_agent_services against a
# throwaway fake agent, and asserts the boot sequence. No real Docker/launchd.
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
  { printf '#!/usr/bin/env bash\n'; printf 'echo "%s $*" >> "%s"\n' "$tool" "$calls"; printf 'exit 0\n'; } > "$mock/$tool"
  chmod +x "$mock/$tool"
done

# ---- fake agent ----
export AGENTS_ROOT="$tmp/agents"
export NAME="Probe" SLUG="probe"
export AGENT_ROOT="$AGENTS_ROOT/Probe"
export PROFILE="$AGENT_ROOT/.hermes/profiles/probe"
export HONCHO_DIR="$AGENT_ROOT/.hermes/honcho"
export PROJECT="honcho-probe" API_PORT="8099"
export LA="$tmp/LaunchAgents"
export DISK_FLOOR_GB=0
mkdir -p "$PROFILE" "$HONCHO_DIR/honcho" "$AGENT_ROOT/.local/bin" "$LA" "$AGENT_ROOT/vault/brain"
printf 'pyproject\n' > "$HONCHO_DIR/honcho/pyproject.toml"   # honcho source "present" → skip clone
printf 'TELEGRAM_BOT_TOKEN=\n' > "$PROFILE/.env"; chmod 644 "$PROFILE/.env"
printf 'BWS_ACCESS_TOKEN=test-token-xyz\n' > "$AGENTS_ROOT/.fleet.env"
{ printf '#!/bin/sh\n'; printf 'exit 0\n'; } > "$AGENT_ROOT/.local/bin/gbrain"; chmod +x "$AGENT_ROOT/.local/bin/gbrain"

# ---- run with mocks on PATH ----
# shellcheck disable=SC1090
source "$LIB" || fail "could not source $LIB"
PATH="$mock:$PATH" boot_agent_services || fail "boot_agent_services returned non-zero"

# ---- assertions: the boot sequence happened ----
grep -q "docker compose -p honcho-probe up -d --build" "$calls" || fail "no compose up --build"
grep -q "configure_embeddings.py" "$calls"                      || fail "no pgvector reshape"
grep -q "curl .*127.0.0.1:8099/health" "$calls"                 || fail "no health gate"
grep -q "launchctl setenv BWS_ACCESS_TOKEN" "$calls"            || fail "BWS token not asserted (credentials fix)"
grep -q "launchctl bootstrap gui/.*gateway-probe" "$calls"      || fail "gateway not bootstrapped"
grep -q "launchctl kickstart -k gui/.*gateway-probe" "$calls"   || fail "gateway not kickstarted"
grep -q "verify-fleet --agent Probe" "$calls"                   || fail "verify-fleet not run"

# ---- assertion: the .env got tightened to 600 (config fix) ----
perms="$(stat -f '%Lp' "$PROFILE/.env" 2>/dev/null || stat -c '%a' "$PROFILE/.env")"
[ "$perms" = "600" ] || fail ".env not chmod 600 (got $perms)"

echo "PASS: boot-services sequence verified ($(wc -l < "$calls" | tr -d ' ') mock calls)"

#!/usr/bin/env bash
# boot-services.sh — SOURCED library (do not execute directly). Defines
# boot_agent_services(): the one shared "bring an agent's services online"
# sequence, used by both `bin/new-agent` (fresh full boot, step 8/8) and
# `Shared/Fleet/bin/boot-agent` (boot an already-scaffolded agent). Keeping a
# single copy means a fix to the boot path (e.g. the pgvector self-heal, the
# .env perms, the BWS token) lands for both.
#
# Sequence: optional Honcho (only when SKIP_HONCHO=0) → secret-file perms +
# fleet BWS token → GBrain install + seed → launchd gateway → verify-fleet.
# Honcho is deprecated fleet-wide. Callers should leave SKIP_HONCHO unset or 1.
#
# Required env (set by the caller before calling boot_agent_services):
#   NAME SLUG AGENT_ROOT PROFILE HONCHO_DIR PROJECT API_PORT LA AGENTS_ROOT REPO
# (HONCHO_DIR is .../.hermes/honcho; the compose project lives at $HONCHO_DIR/honcho.
#  REPO is the SuperHermes root, for bin/verify-fleet.)
#
# Best-effort per phase (no `set -e` dependency); returns non-zero only on a
# preflight that makes booting pointless (Docker down, disk below floor, Honcho
# source unavailable). verify-fleet is the real green gate.

GBRAIN_REF="${GBRAIN_REF:-github:garrytan/gbrain#248fb7a90f9ce5fe2e5d01fe486345d08834ed40}"  # 0.41.38.0
DISK_FLOOR_GB="${DISK_FLOOR_GB:-25}"

# Canonical progress helpers (callers may define identical ones — harmless to override).
say(){ printf '\033[36m%s\033[0m\n' "$*"; }
ok(){  printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33m⚠\033[0m %s\n' "$*"; }

# Re-render the normalised cron scripts from their templates, byte-for-byte the
# way bin/new-agent does (__AGENT_NAME__/__AGENT_SLUG__/__AGENT_ROOT__). ONLY the
# scripts meant to be identical across agents — never per-agent config. Guarded on
# template existence + atomic temp→mv so a partial checkout or a render failure
# can't wipe a working script. Uses NAME/SLUG/AGENT_ROOT/PROFILE/REPO from scope.
render_normalised_scripts() {
  local pair tmpl dst
  mkdir -p "$PROFILE/scripts" 2>/dev/null || true
  for pair in "git-sync.sh.tmpl:git-sync.sh" \
              "memory-health-snapshot.py.tmpl:memory_health_snapshot.py" \
              "cron-registry-snapshot.py.tmpl:cron_registry_snapshot.py"; do
    tmpl="$REPO/templates/${pair%%:*}"; dst="$PROFILE/scripts/${pair##*:}"
    [ -f "$tmpl" ] || continue   # partial checkout: never wipe a working script
    if AGENT_NAME="$NAME" AGENT_SLUG="$SLUG" AGENT_ROOT="$AGENT_ROOT" python3 -c \
         'import os,re,sys;sys.stdout.write(re.sub(r"__([A-Z_]+)__",lambda m:os.environ.get(m.group(1),m.group(0)),open(sys.argv[1]).read()))' \
         "$tmpl" > "$dst.tmp" 2>/dev/null; then
      mv "$dst.tmp" "$dst" && chmod +x "$dst"
    else
      rm -f "$dst.tmp"
    fi
  done
  python3 "$PROFILE/scripts/cron_registry_snapshot.py" || {
    warn "cron registry definition could not be reconciled"
    return 1
  }
}

boot_agent_services() {
  local compose_dir="$HONCHO_DIR/honcho" i

  # Self-heal script drift FIRST, before any preflight that could bail: re-render
  # the normalised scripts so a fix to a shared template reaches already-provisioned
  # agents on restart, not just fresh `new-agent` runs. A git-sync self-heal added
  # 2026-06-19 never reached Doc/Probe — their daily crons CRIT'd on a stale
  # index.lock until the scripts were re-rendered by hand (incident 2026-06-20).
  say "services: re-render normalised scripts"
  render_normalised_scripts
  ok "normalised scripts in sync with templates (git-sync.sh, memory_health_snapshot.py, cron_registry_snapshot.py)"

  say "services: preflight"
  local free_gb; free_gb="$(df -k "$AGENTS_ROOT" | tail -1 | awk '{printf "%d",$4/1024/1024}')"
  if [ "${free_gb:-0}" -lt "$DISK_FLOOR_GB" ]; then warn "disk below floor: ${free_gb}GB < ${DISK_FLOOR_GB}GB"; return 1; fi
  ok "disk · ${free_gb}GB free"

  if [ "${SKIP_HONCHO:-1}" != "0" ]; then
    ok "Honcho skipped (deprecated)"
  else
  { command -v docker >/dev/null && docker info >/dev/null 2>&1; } || { warn "Docker not running — cannot boot Honcho"; return 1; }
  ok "docker up"

  say "services: honcho source"
  if [ -d "$compose_dir/.git" ] || [ -f "$compose_dir/pyproject.toml" ]; then
    ok "honcho source present"
  elif git clone --depth 1 https://github.com/plastic-labs/honcho.git "$HONCHO_DIR/.src" >/dev/null 2>&1; then
    cp -R "$HONCHO_DIR/.src/." "$compose_dir/"; rm -rf "$HONCHO_DIR/.src"; ok "honcho cloned"
  else
    warn "honcho clone failed"; return 1
  fi

  say "services: docker compose up --build"
  # No `|| return` here: on first boot the api stays unhealthy until the pgvector
  # reshape below, so `compose up` exits non-zero — but it self-heals after the
  # reshape. Dying here would abort a boot that's actually fine.
  ( cd "$compose_dir" && docker compose -p "$PROJECT" up -d --build ) \
    || warn "compose up nonzero — api awaiting pgvector reshape; continuing"
  ok "stack created"

  say "services: pgvector reshape -> 768"
  local reshaped=0
  for i in $(seq 1 15); do
    ( cd "$compose_dir" && docker compose -p "$PROJECT" run --rm --entrypoint /app/.venv/bin/python api scripts/configure_embeddings.py --yes ) >/dev/null 2>&1 \
      && { reshaped=1; break; }
    sleep 4
  done
  [ "$reshaped" = 1 ] && ok "pgvector reshaped to 768" || warn "pgvector reshape unconfirmed (continuing)"
  ( cd "$compose_dir" && docker compose -p "$PROJECT" up -d ) >/dev/null 2>&1

  say "services: honcho health gate :$API_PORT"
  local healthy=0
  for i in $(seq 1 30); do curl -fsS "http://127.0.0.1:$API_PORT/health" >/dev/null 2>&1 && { healthy=1; break; }; sleep 2; done
  [ "$healthy" = 1 ] && ok "honcho api healthy ($API_PORT)" || warn "honcho api not healthy yet"
  fi

  say "services: secret perms + fleet token"
  chmod 600 "$PROFILE/.env" 2>/dev/null || true
  [ -f "$PROFILE/auth.json" ] && chmod 600 "$PROFILE/auth.json" 2>/dev/null || true
  # Assert the shared Bitwarden reader token into the launchd domain so the fresh
  # gateway's day-one vault pull succeeds (otherwise it logs "BWS_ACCESS_TOKEN is
  # not set" → credentials CRIT, even though it's the fleet single-source).
  local bws; bws="$(grep -E '^BWS_ACCESS_TOKEN=' "$AGENTS_ROOT/.fleet.env" 2>/dev/null | head -1 | cut -d= -f2-)"
  if [ -n "$bws" ]; then
    launchctl setenv BWS_ACCESS_TOKEN "$bws" 2>/dev/null || true
    ok "secret-file perms tightened (.env 600) + BWS reader token asserted"
  else
    warn "BWS_ACCESS_TOKEN not in $AGENTS_ROOT/.fleet.env — vault pull may fail"
  fi

  say "services: GBrain install + seed"
  if command -v bun >/dev/null; then
    ( export HOME="$PROFILE/home" BUN_INSTALL="$PROFILE/home/.bun" XDG_CACHE_HOME="$PROFILE/home/.cache" PATH="/opt/homebrew/bin:$PROFILE/home/.bun/bin:$PATH"
      mkdir -p "$BUN_INSTALL/bin"; bun add -g "$GBRAIN_REF" >/dev/null 2>&1 ) || warn "gbrain install reported an error"
    "$AGENT_ROOT/.local/bin/gbrain" import "$AGENT_ROOT/vault/brain" >/dev/null 2>&1 || true
    "$AGENT_ROOT/.local/bin/gbrain" embed --stale >/dev/null 2>&1 || true
    ok "gbrain installed + vault seeded"
  else
    warn "bun not found — skipping gbrain"
  fi

  say "services: launchd + verify"
  launchctl bootstrap "gui/$(id -u)" "$LA/ai.hermes.gateway-$SLUG.plist" 2>/dev/null || true
  if [ "${SKIP_HONCHO:-1}" = "0" ]; then
    launchctl bootstrap "gui/$(id -u)" "$LA/ai.hermes.honcho.$SLUG.backup.plist" 2>/dev/null || true
  fi
  # shellcheck disable=SC2034
  # Start gateway via launchctl (label ai.hermes.gateway-$SLUG). Use kickstart -k from host shell.
  launchctl enable "gui/$(id -u)/ai.hermes.gateway-$SLUG" 2>/dev/null || true
  launchctl start "gui/$(id -u)/ai.hermes.gateway-$SLUG" 2>/dev/null \
    || launchctl kickstart -k "gui/$(id -u)/ai.hermes.gateway-$SLUG" 2>/dev/null \
    || true
  ok "gateway booted"
  if python3 "$REPO/bin/verify-fleet" --agent "$NAME" --quiet 2>/dev/null; then
    ok "verify-fleet: $NAME invariants pass"
  else
    warn "verify-fleet flagged issues for $NAME (run: $REPO/bin/verify-fleet --agent $NAME)"
  fi

  return 0
}

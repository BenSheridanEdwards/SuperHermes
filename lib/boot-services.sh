#!/usr/bin/env bash
# boot-services.sh — SOURCED library (do not execute directly). Defines
# boot_agent_services(): shared "bring an agent's services online" sequence for
# `bin/new-agent` (fresh full boot) and any caller that sources this file.
#
# Sequence: disk preflight → secret-file perms + shared BWS token → GBrain
# install + seed → launchd gateway → verify-agents.
#
# Honcho is not part of this path. Memory is GBrain only.
#
# Required env (set by the caller before calling boot_agent_services):
#   NAME SLUG AGENT_ROOT PROFILE LA AGENTS_ROOT REPO
# Optional: API_PORT (unused; retained only if a caller still exports it)
#
# Best-effort per phase. Returns non-zero only on a preflight that makes
# booting pointless (disk below floor). verify-agents is the green gate.

# 0.41.38.0 + stdio-stderr patch (fork of garrytan/gbrain@248fb7a9): routes
# slog/console progress to stderr under `gbrain serve` so vault-import/embed
# lines can't corrupt the MCP stdio JSON-RPC channel (was flooding every
# gateway.error.log with "Failed to parse JSONRPC message"). The upstream PR
# carrying this patch (garrytan/gbrain#3844) was closed without merging, so the
# fork pin stands until upstream ships an equivalent. Override with GBRAIN_REF
# to install any other ref, including plain upstream.
GBRAIN_REF="${GBRAIN_REF:-github:BenSheridanEdwards/gbrain#3eec49b59e4cc91552b8212243438f5a98b7361f}"
DISK_FLOOR_GB="${DISK_FLOOR_GB:-25}"

say(){ printf '\033[36m%s\033[0m\n' "$*"; }
ok(){  printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33m⚠\033[0m %s\n' "$*"; }

# Re-render the normalised cron scripts from their templates, byte-for-byte the
# way bin/new-agent does (__AGENT_NAME__/__AGENT_SLUG__/__AGENT_ROOT__).
render_normalised_scripts() {
  local pair tmpl dst
  mkdir -p "$PROFILE/scripts" 2>/dev/null || true
  for pair in "git-sync.sh.tmpl:git-sync.sh" \
              "memory-health-snapshot.py.tmpl:memory_health_snapshot.py" \
              "cron-registry-snapshot.py.tmpl:cron_registry_snapshot.py"; do
    tmpl="$REPO/templates/${pair%%:*}"; dst="$PROFILE/scripts/${pair##*:}"
    [ -f "$tmpl" ] || continue
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
  say "services: re-render normalised scripts"
  render_normalised_scripts
  ok "normalised scripts in sync with templates (git-sync.sh, memory_health_snapshot.py, cron_registry_snapshot.py)"

  say "services: preflight"
  local free_gb; free_gb="$(df -k "$AGENTS_ROOT" | tail -1 | awk '{printf "%d",$4/1024/1024}')"
  if [ "${free_gb:-0}" -lt "$DISK_FLOOR_GB" ]; then warn "disk below floor: ${free_gb}GB < ${DISK_FLOOR_GB}GB"; return 1; fi
  ok "disk · ${free_gb}GB free"

  say "services: secret perms + shared token"
  chmod 600 "$PROFILE/.env" 2>/dev/null || true
  [ -f "$PROFILE/auth.json" ] && chmod 600 "$PROFILE/auth.json" 2>/dev/null || true
  # SECRETS_ENV (operator config) points at the env file holding the shared
  # secrets-manager reader token; unset = no shared token, per-agent .env only.
  local bws=""
  if [ -n "${SECRETS_ENV:-}" ]; then
    bws="$(grep -E '^BWS_ACCESS_TOKEN=' "$SECRETS_ENV" 2>/dev/null | head -1 | cut -d= -f2-)"
  fi
  if [ -n "$bws" ]; then
    launchctl setenv BWS_ACCESS_TOKEN "$bws" 2>/dev/null || true
    ok "secret-file perms tightened (.env 600) + BWS reader token asserted"
  else
    warn "no BWS_ACCESS_TOKEN (set SECRETS_ENV to your token env file) — vault pull may fail"
  fi

  say "services: GBrain install + seed"
  # Resolve bun via the CALLER's PATH and invoke that binary — a hard-coded
  # /opt/homebrew/bin prepend inside the subshell would silently override the
  # caller's resolution (and defeat PATH-shim test mocks).
  local bun_bin; bun_bin="$(command -v bun 2>/dev/null || true)"
  if [ -n "$bun_bin" ]; then
    ( export HOME="$PROFILE/home" BUN_INSTALL="$PROFILE/home/.bun" XDG_CACHE_HOME="$PROFILE/home/.cache" PATH="/opt/homebrew/bin:$PROFILE/home/.bun/bin:$PATH"
      mkdir -p "$BUN_INSTALL/bin"; "$bun_bin" add -g "$GBRAIN_REF" >/dev/null 2>&1 ) || warn "gbrain install reported an error"
    "$AGENT_ROOT/.local/bin/gbrain" import "$AGENT_ROOT/vault/brain" >/dev/null 2>&1 || true
    "$AGENT_ROOT/.local/bin/gbrain" embed --stale >/dev/null 2>&1 || true
    ok "gbrain installed + vault seeded"
  else
    warn "bun not found — skipping gbrain"
  fi

  say "services: launchd + verify"
  launchctl bootstrap "gui/$(id -u)" "$LA/ai.hermes.gateway-$SLUG.plist" 2>/dev/null || true
  launchctl enable "gui/$(id -u)/ai.hermes.gateway-$SLUG" 2>/dev/null || true
  launchctl start "gui/$(id -u)/ai.hermes.gateway-$SLUG" 2>/dev/null || true
  ok "gateway booted"
  if python3 "$REPO/bin/verify-agents" --agent "$NAME" --quiet 2>/dev/null; then
    ok "verify-agents: $NAME invariants pass"
  else
    warn "verify-agents flagged issues for $NAME (run: $REPO/bin/verify-agents --agent $NAME)"
  fi

  return 0
}

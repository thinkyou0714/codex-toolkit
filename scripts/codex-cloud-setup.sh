#!/usr/bin/env bash
# codex-cloud-setup.sh — make the Codex CLI usable in a cloud/ephemeral session.
#
# One idempotent command that takes a fresh container (Claude Code on the web,
# GitHub Actions, Codespaces, a devcontainer, any CI box) to "codex exec works":
#
#   1) detect   which cloud environment this is
#   2) cli      install the Codex CLI via npm when missing (pin: CODEX_CLI_VERSION)
#   3) auth     wire credentials without writing secrets into the repo:
#                 - already logged in            -> keep
#                 - $CODEX_AUTH_JSON(_B64)       -> write $CODEX_HOME/auth.json (0600)
#                 - $OPENAI_API_KEY              -> codex login --with-api-key (stdin)
#                 - none                         -> print how (device auth / secrets)
#   4) toolkit  install the global toolkit layer (install.sh --home --scripts)
#   5) profile  seed $CODEX_HOME/cloud.config.toml (non-interactive defaults)
#   6) egress   preflight the OpenAI endpoints and name the blocked domains
#
# Usage:
#   codex-cloud-setup.sh              # do everything, best effort
#   codex-cloud-setup.sh --dry-run    # print the plan, change nothing
#   codex-cloud-setup.sh --check      # report readiness only (changes nothing)
#   codex-cloud-setup.sh --strict     # exit 1 unless fully ready at the end
#   codex-cloud-setup.sh --no-egress  # skip the network preflight
#
# Exit: 0 ready-or-partial (warnings printed); 1 hard failure or --strict unmet;
#       2 usage error.
set -uo pipefail

# --- locate lib/paths.sh (same 3-way fallback as the sibling wrappers) --------
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/paths.sh" ]; then _lib="$SCRIPT_DIR/lib/paths.sh"
elif [ -n "${CODEX_TOOLKIT_ROOT:-}" ] && [ -f "$CODEX_TOOLKIT_ROOT/scripts/lib/paths.sh" ]; then _lib="$CODEX_TOOLKIT_ROOT/scripts/lib/paths.sh"
elif [ -f "$HOME/.codex/toolkit-root" ] && [ -f "$(cat "$HOME/.codex/toolkit-root")/scripts/lib/paths.sh" ]; then _lib="$(cat "$HOME/.codex/toolkit-root")/scripts/lib/paths.sh"
else echo "error: cannot locate scripts/lib/paths.sh (set CODEX_TOOLKIT_ROOT)" >&2; exit 1; fi
# shellcheck source=lib/paths.sh
source "$_lib"

DRY_RUN=0 CHECK=0 STRICT=0 QUIET=0 DO_EGRESS=1
for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=1 ;;
    --check)     CHECK=1; DRY_RUN=1 ;;
    --strict)    STRICT=1 ;;
    --quiet)     QUIET=1 ;;
    --no-egress) DO_EGRESS=0 ;;
    -h|--help)   sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

warns=0 fails=0
say()  { [ "$QUIET" = 1 ] || echo "$*"; }
ok()   { [ "$QUIET" = 1 ] || echo "  ✅ $*"; }
warn() { echo "  ⚠️  $*"; warns=$((warns+1)); }
bad()  { echo "  ❌ $*"; fails=$((fails+1)); }
act()  {
  # act <description> <cmd...> — honor --dry-run.
  local desc="$1"; shift
  if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] $desc"; return 0; fi
  say "  $desc"
  "$@"
}

# --- 1) detect -----------------------------------------------------------------
cloud_env="$(codex_cloud_env)"
say "== codex-cloud-setup: environment =="
ok "detected: $cloud_env  (CODEX_HOME=$CODEX_HOME)"

# --- 2) Codex CLI --------------------------------------------------------------
say "== Codex CLI =="
want_ver="${CODEX_CLI_VERSION:-}"
pkg="@openai/codex${want_ver:+@$want_ver}"
npm_quiet() { npm install -g "$1" >/dev/null 2>&1; }
if codex_have "$CODEX_BIN"; then
  have_ver="$("$CODEX_BIN" --version 2>/dev/null | head -n1 || true)"
  if [ -n "$want_ver" ] && ! printf '%s' "$have_ver" | grep -q "$want_ver"; then
    act "npm install -g $pkg (pin: have '$have_ver')" npm_quiet "$pkg" \
      && ok "pinned to $pkg" || bad "npm install -g $pkg failed"
  else
    ok "$CODEX_BIN on PATH: ${have_ver:-unknown version}"
  fi
elif codex_have npm; then
  act "npm install -g $pkg" npm_quiet "$pkg" \
    && { [ "$DRY_RUN" = 1 ] || ok "installed: $("$CODEX_BIN" --version 2>/dev/null | head -n1)"; } \
    || bad "npm install -g $pkg failed (check proxy/registry; see 'npm config get proxy')"
else
  bad "neither '$CODEX_BIN' nor npm found. Install Node 18+ first (e.g. via your setup script/devcontainer feature)."
fi

# --- 3) auth -------------------------------------------------------------------
say "== auth =="
auth_state="none"
if codex_have "$CODEX_BIN" && "$CODEX_BIN" login status </dev/null >/dev/null 2>&1; then
  auth_state="logged-in"
  ok "already authenticated ($("$CODEX_BIN" login status </dev/null 2>&1 | head -n1))"
elif [ -n "${CODEX_AUTH_JSON:-}${CODEX_AUTH_JSON_B64:-}" ]; then
  # A whole auth.json passed as a secret (the way to reuse ChatGPT-plan auth in
  # CI: run `codex login` locally once, store ~/.codex/auth.json as the secret).
  if [ "$DRY_RUN" = 1 ]; then
    say "  [dry-run] write \$CODEX_HOME/auth.json from CODEX_AUTH_JSON(_B64) (mode 0600)"
    auth_state="would-write"
  else
    mkdir -p "$CODEX_HOME" && (
      umask 077
      if [ -n "${CODEX_AUTH_JSON_B64:-}" ]; then
        # GNU decodes with -d, older BSD/macOS with -D; try both.
        printf '%s' "$CODEX_AUTH_JSON_B64" | base64 -d > "$CODEX_HOME/auth.json" 2>/dev/null \
          || printf '%s' "$CODEX_AUTH_JSON_B64" | base64 -D > "$CODEX_HOME/auth.json"
      else
        printf '%s' "$CODEX_AUTH_JSON" > "$CODEX_HOME/auth.json"
      fi
    ) && { auth_state="auth-json"; ok "wrote \$CODEX_HOME/auth.json from secret (0600)"; } \
      || bad "could not write \$CODEX_HOME/auth.json"
  fi
elif [ -n "${OPENAI_API_KEY:-}" ]; then
  if [ "$DRY_RUN" = 1 ]; then
    say "  [dry-run] printenv OPENAI_API_KEY | codex login --with-api-key"
    auth_state="would-login"
  elif codex_have "$CODEX_BIN" && printenv OPENAI_API_KEY | "$CODEX_BIN" login --with-api-key >/dev/null 2>&1; then
    auth_state="api-key"
    ok "logged in with OPENAI_API_KEY (usage billed to the API key)"
  else
    bad "codex login --with-api-key failed"
  fi
elif [ -n "${CODEX_API_KEY:-}" ]; then
  # Run-scoped key: `codex exec` reads CODEX_API_KEY directly, no login needed.
  auth_state="exec-env-key"
  ok "CODEX_API_KEY set — codex exec will use it (no login written)"
else
  warn "no credentials. Options:
      - set OPENAI_API_KEY in the environment's secrets (API billing), or
      - set CODEX_API_KEY (used by codex exec only, nothing written to disk), or
      - store your local ~/.codex/auth.json as secret CODEX_AUTH_JSON_B64
        (base64 -w0 ~/.codex/auth.json) to reuse your ChatGPT plan, or
      - interactively: codex login --device-auth"
fi

# --- 4) toolkit global layer -----------------------------------------------------
say "== toolkit (~/.codex + PATH wrappers) =="
if [ -f "$CODEX_HOME/env.sh" ] && [ -f "$CODEX_HOME/toolkit-root" ]; then
  ok "global layer present"
else
  installer="$CODEX_TOOLKIT_ROOT/install.sh"
  if [ -f "$installer" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      say "  [dry-run] bash install.sh --home --scripts"
    else
      bash "$installer" --home --scripts >/dev/null && ok "installed global layer + wrappers" \
        || bad "install.sh --home --scripts failed"
    fi
  else
    warn "install.sh not found at CODEX_TOOLKIT_ROOT=$CODEX_TOOLKIT_ROOT; skipping"
  fi
fi
bin_dir="${CODEX_BIN_DIR:-$HOME/.local/bin}"
case ":$PATH:" in
  *":$bin_dir:"*) ok "$bin_dir on PATH" ;;
  *) if [ "$cloud_env" = "github-actions" ] && [ -n "${GITHUB_PATH:-}" ] && [ "$DRY_RUN" = 0 ]; then
       echo "$bin_dir" >> "$GITHUB_PATH" && ok "appended $bin_dir to \$GITHUB_PATH"
     else
       warn "$bin_dir not on PATH. Add: export PATH=\"$bin_dir:\$PATH\""
     fi ;;
esac

# --- 5) cloud profile ------------------------------------------------------------
say "== cloud profile =="
profile_src="$CODEX_TOOLKIT_ROOT/home/cloud.config.toml.example"
profile_dst="$CODEX_HOME/cloud.config.toml"
if [ -f "$profile_dst" ]; then
  ok "cloud profile present ($profile_dst) — run with: codex exec -p cloud ..."
elif [ -f "$profile_src" ]; then
  act "seed $profile_dst (from example; never overwritten)" \
    bash -c 'mkdir -p "$(dirname "$2")" && cp "$1" "$2"' _ "$profile_src" "$profile_dst" \
    && { [ "$DRY_RUN" = 1 ] || ok "seeded — run with: codex exec -p cloud ..."; }
else
  warn "cloud profile example missing at $profile_src"
fi

# --- 6) egress preflight -----------------------------------------------------------
if [ "$DO_EGRESS" = 1 ] && codex_have curl; then
  say "== egress preflight =="
  blocked=""
  for h in $CODEX_OPENAI_HOSTS; do
    if codex_egress_probe "$h"; then
      ok "https://$h reachable"
    else
      bad "https://$h blocked (proxy/network policy)"
      blocked="$blocked $h"
    fi
  done
  if [ -n "$blocked" ]; then
    echo "  fix: allow these domains in this environment's network policy:$blocked"
    echo "       (Claude Code on the web: environment settings -> network policy;"
    echo "        corporate proxy: also export SSL_CERT_FILE to the proxy CA bundle)"
  fi
fi

# --- summary -------------------------------------------------------------------
echo
echo "codex-cloud-setup: $fails fail, $warns warn (env=$cloud_env, auth=$auth_state)"
if [ "$CHECK" = 1 ] || [ "$STRICT" = 1 ]; then
  [ $((fails)) -gt 0 ] && exit 1
  [ "$STRICT" = 1 ] && [ "$warns" -gt 0 ] && exit 1
fi
exit 0

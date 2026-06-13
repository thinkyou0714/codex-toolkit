#!/usr/bin/env bash
# codex-doctor.sh — read-only health check for the Codex toolkit setup.
#
# Reports each check as one of:
#   ok    — fine
#   warn  — fine but worth knowing
#   fail  — actually broken, with a concrete fix
#
# Exit code: 0 unless --strict, then 1 if any fail/warn.
#
# Usage:
#   codex-doctor.sh             # human-friendly report
#   codex-doctor.sh --strict    # exit non-zero on any fail or warn (for CI)
#   codex-doctor.sh --quiet     # only print fails/warns
set -uo pipefail

# --- self-locating, like the other wrappers (handles symlink install) ----------
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

STRICT=0; QUIET=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
    --quiet)  QUIET=1 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

fails=0; warns=0
ok()   { [ "$QUIET" = 1 ] || echo "  ✅ $*"; }
warn() { echo "  ⚠️  $*"; warns=$((warns+1)); }
fail() { echo "  ❌ $*"; fails=$((fails+1)); }

section() { [ "$QUIET" = 1 ] || echo; [ "$QUIET" = 1 ] || echo "== $* =="; }

# --- 1. Codex CLI -------------------------------------------------------------
section "Codex CLI"
if codex_have "$CODEX_BIN"; then
  ver="$("$CODEX_BIN" --version 2>/dev/null | head -n1 || true)"
  if [ -n "$ver" ]; then
    ok "$CODEX_BIN: $ver"
  else
    warn "$CODEX_BIN found but --version returned nothing"
  fi
else
  fail "$CODEX_BIN not on PATH. Install: 'npm install -g @openai/codex' (Node 18+)."
fi

# --- 2. Environment -----------------------------------------------------------
section "Environment"
for var in CODEX_HOME CODEX_TOOLKIT_ROOT; do
  if [ -n "${!var:-}" ]; then ok "$var=${!var}"; else warn "$var not set. Add 'export $var=...' to your shell rc."; fi
done
if [ -n "${OPENAI_API_KEY:-}" ]; then ok "OPENAI_API_KEY: set (value not shown)"; else warn "OPENAI_API_KEY not set. Most calls will fail until you export it."; fi

# --- 3. ~/.codex layout -------------------------------------------------------
section "Global config ($CODEX_HOME)"
if [ -d "$CODEX_HOME" ]; then
  for f in AGENTS.md config.toml env.sh scripts/cost-breaker.py scripts/quota-fallback.py; do
    if [ -f "$CODEX_HOME/$f" ]; then ok "$f"; else fail "$f missing. Run: install.sh --home"; fi
  done
  if [ -f "$CODEX_HOME/session_context.md" ]; then ok "session_context.md (PSM)"; else warn "session_context.md missing (PSM disabled). Run: install.sh --home"; fi
else
  fail "$CODEX_HOME does not exist. Run: install.sh --home"
fi

# --- 4. Cost breaker status ---------------------------------------------------
section "Cost breaker"
if [ -f "$CODEX_HOME/scripts/cost-breaker.py" ] && codex_have python3; then
  status_out="$(python3 "$CODEX_HOME/scripts/cost-breaker.py" status 2>&1 || true)"
  echo "$status_out" | sed 's/^/  /'
  if echo "$status_out" | grep -qi 'breaker:\s*OFF'; then warn "breaker is OFF (CODEX_COST_BREAKER_OFF=1). Unset for safety."; fi
fi

# --- 5. Project wiring --------------------------------------------------------
section "Project wiring ($CODEX_PROJECT_DIR)"
if [ -f "$CODEX_PROJECT_DIR/AGENTS.md" ]; then
  ok "AGENTS.md present"
  # Catch the most common post-install mistake: unfilled template placeholders.
  if grep -qE '\{\{[A-Z_]+\}\}' "$CODEX_PROJECT_DIR/AGENTS.md"; then
    leftover="$(grep -oE '\{\{[A-Z_]+\}\}' "$CODEX_PROJECT_DIR/AGENTS.md" | sort -u | tr '\n' ' ')"
    fail "AGENTS.md still has unfilled placeholders: $leftover  Fill them in before relying on the agent."
  else
    ok "AGENTS.md has no unfilled {{PLACEHOLDERS}}"
  fi
else
  warn "No AGENTS.md at project root. From a target repo: install.sh --repo"
fi
if [ -f "$CODEX_PROJECT_DIR/.github/workflows/codex-pr-review.yml" ]; then ok "PR-review workflow present"; else warn "No PR-review workflow (optional)."; fi
if [ -d "$CODEX_PROJECT_DIR/.codex/skills" ]; then ok ".codex/skills/ present"; else warn ".codex/skills/ absent (optional)."; fi

# --- 6. Git remote metadata ----------------------------------------------------
section "Git remote metadata"
if codex_have git && git -C "$CODEX_PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$CODEX_PROJECT_DIR" remote get-url origin >/dev/null 2>&1; then
    origin_head="$(git -C "$CODEX_PROJECT_DIR" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null || true)"
    default_ref="$(GIT_TERMINAL_PROMPT=0 git -C "$CODEX_PROJECT_DIR" ls-remote --symref origin HEAD 2>/dev/null \
      | sed -n 's/^ref: \(refs\/heads\/.*\)[[:space:]]HEAD$/\1/p' | head -n1 || true)"
    if [ -n "$default_ref" ]; then
      expected_head="refs/remotes/origin/${default_ref#refs/heads/}"
      if [ -z "$origin_head" ]; then
        warn "origin/HEAD is not set. Run: git remote set-head origin -a"
      elif [ "$origin_head" = "$expected_head" ]; then
        ok "origin/HEAD matches default branch ($origin_head)"
      else
        warn "origin/HEAD points to $origin_head, expected $expected_head. Run: git remote set-head origin -a"
      fi
    elif [ -n "$origin_head" ]; then
      warn "Cannot query origin default branch; current origin/HEAD is $origin_head"
    else
      warn "Cannot query origin default branch, and origin/HEAD is not set. Run: git remote set-head origin -a"
    fi
  else
    ok "No origin remote configured; skipping origin/HEAD check"
  fi
else
  ok "Not a git worktree; skipping origin/HEAD check"
fi

# --- 7. Claude integration (optional) -----------------------------------------
if [ -d "$CODEX_PROJECT_DIR/.claude" ]; then
  section "Claude integration"
  settings="$CODEX_PROJECT_DIR/.claude/settings.json"
  if [ -f "$settings" ]; then
    if grep -qE '"command":\s*"[^"]*\.claude/hooks/[^"]+\.py"' "$settings"; then
      warn "Hook command uses a relative path. Use absolute \$CLAUDE_PROJECT_DIR/... — relative paths can be silently disabled by 'cd'."
    else
      ok "settings.json hook paths look absolute (or no python hooks registered)"
    fi
  fi
fi

# --- 8. Safety primitives (v0.2.0) --------------------------------------------
section "Safety primitives"
# secret_redact lib: must be present and pass its own 8/8 selftest.
redact_lib=""
for cand in "$CODEX_HOME/lib/secret_redact.py" "${CODEX_TOOLKIT_ROOT:-}/home/lib/secret_redact.py"; do
  [ -n "$cand" ] && [ -f "$cand" ] && { redact_lib="$cand"; break; }
done
if [ -n "$redact_lib" ]; then
  ok "secret_redact.py present ($redact_lib)"
  if codex_have python3 && python3 "$redact_lib" --selftest 2>/dev/null | grep -q "^selftest: 8/8 PASS$"; then
    ok "secret_redact 8/8 PASS"
  else
    fail "secret_redact selftest did not report 8/8. Try: python3 $redact_lib --selftest"
  fi
else
  warn "secret_redact.py not installed. Run: install.sh --home"
fi

# kill-switch script: must be executable; report current state. Warn if ACTIVE >24h (likely forgotten).
killswitch=""
for cand in "$CODEX_HOME/scripts/kill-switch.sh" "${CODEX_TOOLKIT_ROOT:-}/home/scripts/kill-switch.sh"; do
  [ -n "$cand" ] && [ -f "$cand" ] && { killswitch="$cand"; break; }
done
if [ -n "$killswitch" ]; then
  ok "kill-switch.sh present"
  flag="$CODEX_HOME/state/kill-switch.flag"
  if [ -f "$flag" ]; then
    age_h=$(( ( $(date +%s) - $(date -r "$flag" +%s 2>/dev/null || echo 0) ) / 3600 ))
    if [ "$age_h" -gt 24 ]; then
      warn "kill-switch ACTIVE for ${age_h}h (>24h, likely forgotten). Run: kill-switch deactivate"
    else
      warn "kill-switch ACTIVE (${age_h}h). codex-run will refuse to invoke codex."
    fi
  else
    ok "kill-switch CLEAR"
  fi
else
  warn "kill-switch.sh not installed. Run: install.sh --home"
fi

# --- summary ------------------------------------------------------------------
echo
echo "Summary: $fails fail, $warns warn"
if [ "$STRICT" = 1 ] && [ $((fails+warns)) -gt 0 ]; then exit 1; fi
[ "$fails" -gt 0 ] && exit 1 || exit 0

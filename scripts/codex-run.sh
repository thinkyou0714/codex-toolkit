#!/usr/bin/env bash
# codex-run.sh — thin wrapper around `codex exec` with two safety primitives:
#
#   1) kill-switch gate: refuses to invoke codex when the toolkit's kill switch
#      is ACTIVE. Lets you stop runaway/incident codex usage in one command
#      (`kill-switch activate "<reason>"`) without hunting every caller.
#
#   2) secret redaction: arguments are scrubbed via home/lib/secret_redact.py
#      before they hit the failure log, so a leaked Bearer/sk-/xai-/api_key in
#      your shell history doesn't end up in failures.jsonl too.
#
# Failures are appended to $CODEX_LOG_DIR/failures.jsonl with hook=codex-run.
#
# Usage:
#   codex-run.sh exec <prompt> [...flags]   # most common — wraps `codex exec`
#   codex-run.sh -- <any codex subcommand>  # pass-through for the rest
#   codex-run.sh --selftest                 # offline gate + redact smoke (no codex required)
#
# Exit: codex's exit code on success/failure; 7 if blocked by kill switch; 2 on misuse.

set -uo pipefail

# --- locate paths.sh + sibling kill-switch ------------------------------------
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" && pwd)"

_lib=""
for cand in \
    "$SCRIPT_DIR/lib/paths.sh" \
    "${CODEX_TOOLKIT_ROOT:-/dev/null}/scripts/lib/paths.sh" \
    "$HOME/.codex/lib/paths.sh"; do
  if [ -f "$cand" ]; then _lib="$cand"; break; fi
done
if [ -n "$_lib" ]; then
  # shellcheck source=/dev/null
  source "$_lib"
fi
: "${CODEX_HOME:=$HOME/.codex}"
: "${CODEX_LOG_DIR:=$CODEX_HOME/logs}"

REDACT_PY=""
for cand in \
    "$CODEX_HOME/lib/secret_redact.py" \
    "${CODEX_TOOLKIT_ROOT:-/dev/null}/home/lib/secret_redact.py" \
    "$SCRIPT_DIR/../home/lib/secret_redact.py"; do
  if [ -f "$cand" ]; then REDACT_PY="$cand"; break; fi
done

KILL_SWITCH=""
for cand in \
    "$CODEX_HOME/scripts/kill-switch.sh" \
    "${CODEX_TOOLKIT_ROOT:-/dev/null}/home/scripts/kill-switch.sh"; do
  if [ -f "$cand" ]; then KILL_SWITCH="$cand"; break; fi
done

FAILURES_LOG="$CODEX_LOG_DIR/failures.jsonl"
mkdir -p "$CODEX_LOG_DIR" 2>/dev/null || true

# --- helpers ------------------------------------------------------------------
redact() {
  # Read from stdin, redact, write to stdout. Falls back to identity if the lib
  # is missing (the wrapper still runs codex; we just can't scrub log text).
  if [ -n "$REDACT_PY" ] && command -v python3 >/dev/null 2>&1; then
    python3 "$REDACT_PY"
  else
    cat
  fi
}

log_failure() {
  # log_failure <category> <exit_code> <detail-text>
  local category="$1" code="$2" detail="$3" ts detail_red detail_json
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  detail_red=$(printf '%s' "$detail" | redact)
  detail_json=$(printf '%s' "$detail_red" | python3 -c '
import json,sys
print(json.dumps(sys.stdin.read().strip()))
' 2>/dev/null || printf '"%s"' "${detail_red//\"/\\\"}")
  printf '{"ts":"%s","hook":"codex-run","category":"%s","exit_code":%d,"detail":%s}\n' \
    "$ts" "$category" "$code" "$detail_json" >> "$FAILURES_LOG" 2>/dev/null || true
}

kill_switch_blocked() {
  [ -n "$KILL_SWITCH" ] || return 1
  bash "$KILL_SWITCH" check >/dev/null 2>&1 && return 1 || return 0
}

# --- selftest (offline) -------------------------------------------------------
if [ "${1:-}" = "--selftest" ]; then
  ok=0 total=0
  check() { total=$((total+1)); if [ "$2" = "$3" ]; then ok=$((ok+1)); else echo "FAIL[$1]: got=$2 want=$3" >&2; fi; }

  # 1) redact produces stable output for a known input
  got=$(printf 'Authorization: Bearer abcdef0123456789ABCDEF' | redact)
  check redact-bearer "$got" "Authorization: Bearer ***"

  # 2) failures.jsonl format is valid JSON (round-trip)
  tmp_log="${CODEX_LOG_DIR}/selftest-$$.jsonl"
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '{"ts":"%s","hook":"codex-run","category":"smoke","exit_code":0,"detail":"ok"}\n' "$ts" > "$tmp_log"
  parsed=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("hook"))' "$tmp_log" 2>/dev/null || echo "")
  check log-json "$parsed" "codex-run"
  rm -f "$tmp_log"

  # 3) kill_switch_blocked reports a boolean correctly when no flag exists
  if [ -n "$KILL_SWITCH" ]; then bash "$KILL_SWITCH" deactivate >/dev/null 2>&1 || true; fi
  if kill_switch_blocked; then result=blocked; else result=clear; fi
  check kill-switch-clear "$result" "clear"

  echo "selftest: $ok/$total PASS"
  [ "$ok" -eq "$total" ] && exit 0 || exit 1
fi

# --- arg parse ----------------------------------------------------------------
if [ "$#" -lt 1 ]; then
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

# --- gate ---------------------------------------------------------------------
if kill_switch_blocked; then
  reason=""
  if [ -n "$KILL_SWITCH" ]; then
    reason=$(bash "$KILL_SWITCH" status 2>/dev/null | head -1)
  fi
  log_failure kill_switch_blocked 7 "blocked by kill-switch: ${reason:-ACTIVE}"
  echo "codex-run: BLOCKED — toolkit kill-switch is ACTIVE." >&2
  echo "  ${reason:-Run kill-switch deactivate when ready.}" >&2
  exit 7
fi

# --- invoke -------------------------------------------------------------------
# Decide between `codex exec ...` (the common path) and pass-through with `--`.
if [ "${1:-}" = "--" ]; then
  shift
  args=("$@")
else
  args=("$@")
fi

# Log the (redacted) command line we're about to run, for incident triage.
preview=$(printf '%s ' "codex" "${args[@]}" | redact | head -c 500)
log_failure invoke 0 "$preview"

if ! command -v codex >/dev/null 2>&1; then
  log_failure codex_missing 127 "codex not found on PATH"
  echo "codex-run: ERROR codex CLI not found on PATH. Install with: npm i -g @openai/codex" >&2
  exit 127
fi

codex "${args[@]}"
rc=$?
if [ $rc -ne 0 ]; then
  log_failure nonzero_exit "$rc" "codex exited with code $rc"
fi
exit $rc

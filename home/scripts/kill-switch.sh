#!/usr/bin/env bash
# kill-switch.sh — emergency stop for codex invocations.
#
# A file-flag based switch any codex wrapper can honor before invoking the CLI.
# When ACTIVE, wrappers that source the toolkit (e.g. scripts/codex-run.sh)
# refuse to run and exit non-zero. Pure file semantics — works across shells,
# survives reboots, has no daemon.
#
# Commands:
#   activate <reason>   write the flag with {ts, reason, by}. Idempotent.
#   deactivate          remove the flag. Idempotent.
#   check               exit 0 if CLEAR, exit 1 if ACTIVE. Quiet by default.
#   status              human-friendly: print state + age + reason.
#
# State file:        $CODEX_HOME/state/kill-switch.flag  (JSON)
# Audit log:         $CODEX_LOG_DIR/failures.jsonl       (append; event=kill_switch)
# Both paths resolved by scripts/lib/paths.sh; safe defaults if it isn't sourced.

set -uo pipefail

# --- locate paths.sh (the single source of truth) -----------------------------
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" && pwd)"

# Resolve toolkit root → paths.sh. Several fallback locations so the script
# works whether it's been installed, symlinked, or invoked from a checkout.
_lib=""
for cand in \
    "$SCRIPT_DIR/../../scripts/lib/paths.sh" \
    "${CODEX_TOOLKIT_ROOT:-/dev/null}/scripts/lib/paths.sh" \
    "$HOME/.codex/lib/paths.sh"; do
  if [ -f "$cand" ]; then _lib="$cand"; break; fi
done
if [ -n "$_lib" ]; then
  # shellcheck source=/dev/null
  source "$_lib"
fi
# Defensive defaults so this script can be run even if paths.sh is missing.
: "${CODEX_HOME:=$HOME/.codex}"
: "${CODEX_LOG_DIR:=$CODEX_HOME/logs}"

FLAG_DIR="$CODEX_HOME/state"
FLAG_FILE="$FLAG_DIR/kill-switch.flag"
FAILURES_LOG="$CODEX_LOG_DIR/failures.jsonl"

mkdir -p "$FLAG_DIR" "$CODEX_LOG_DIR" 2>/dev/null || true

# --- audit logging (codex-toolkit convention, mirrors LAB schema) -------------
audit() {
  # audit <category> <detail-json-fragment>
  local category="$1" detail="$2" ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '{"ts":"%s","hook":"codex-toolkit","event":"kill_switch","category":"%s","detail":%s}\n' \
    "$ts" "$category" "$detail" >> "$FAILURES_LOG" 2>/dev/null || true
}

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

cmd="${1:-}"
case "$cmd" in
  activate)
    reason="${2:-unspecified}"
    by="${USER:-unknown}"
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Escape the reason for JSON: replace " and \ and control chars conservatively.
    safe_reason=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r')
    printf '{"ts":"%s","reason":"%s","by":"%s"}\n' "$ts" "$safe_reason" "$by" > "$FLAG_FILE"
    audit activated "$(printf '{"reason":"%s","by":"%s"}' "$safe_reason" "$by")"
    echo "kill-switch ACTIVATED: $safe_reason (flag: $FLAG_FILE)"
    exit 0
    ;;
  deactivate)
    prior_reason=""
    if [ -f "$FLAG_FILE" ]; then
      prior_reason=$(grep -oE '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' "$FLAG_FILE" \
        | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    fi
    rm -f "$FLAG_FILE" 2>/dev/null
    audit deactivated "$(printf '{"prior_reason":"%s"}' "${prior_reason:-}")"
    echo "kill-switch DEACTIVATED${prior_reason:+ (was: $prior_reason)}"
    exit 0
    ;;
  check)
    if [ -f "$FLAG_FILE" ]; then exit 1; else exit 0; fi
    ;;
  status|"")
    if [ -f "$FLAG_FILE" ]; then
      reason=$(grep -oE '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' "$FLAG_FILE" \
        | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
      ts=$(grep -oE '"ts"[[:space:]]*:[[:space:]]*"[^"]*"' "$FLAG_FILE" \
        | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
      echo "ACTIVE since $ts: ${reason:-unknown reason}"
      echo "  flag: $FLAG_FILE"
      exit 1
    fi
    echo "CLEAR"
    exit 0
    ;;
  -h|--help) usage 0 ;;
  *) echo "kill-switch: unknown command: $cmd" >&2; usage 2 ;;
esac

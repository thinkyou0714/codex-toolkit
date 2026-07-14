#!/usr/bin/env bash
# codex_fix.sh — ask Codex to apply fixes to the working tree for a described issue.
#
# Portable rewrite. Writes nothing outside the project; relies on Codex's own
# sandbox/approval settings (see home/config.toml.example).
#
# Usage:
#   codex_fix.sh "make the login form validate email before submit"
#   codex_fix.sh -f notes.md          # read the task from a file
set -euo pipefail

# Resolve our real location even when invoked via a symlink (e.g. ~/.local/bin),
# then locate the shared lib next to it, or via the toolkit root.
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

codex_require "$CODEX_BIN" || exit 127

TASK=""
if [ "${1:-}" = "-f" ]; then
  [ -n "${2:-}" ] || codex_die "-f needs a file path"
  [ -f "$2" ] || codex_die "file not found: $2"
  TASK="$(cat "$2")"
else
  TASK="${*:-}"
fi
[ -n "$TASK" ] || codex_die "no task given. Usage: codex_fix.sh \"<task>\"  |  codex_fix.sh -f <file>"

# Optional cost gate (estimate-based): check before, record after, so the daily
# ledger actually accumulates and can trip on the Nth call of the day.
EST="${CODEX_FIX_EST_USD:-0.40}"
if ! codex_cost_gate fix "$EST"; then
  echo "Cost circuit-breaker tripped — fix skipped. Override with CODEX_COST_BREAKER_OFF=1." >&2
  exit 3
fi

MODEL="${CODEX_FIX_MODEL:-gpt-5-codex}"

echo "==> Codex fix in $CODEX_PROJECT_DIR, model=$MODEL"
# `< /dev/null` works around openai/codex#20919: `codex exec "<prompt>"`
# hangs forever in non-interactive shells waiting for stdin EOF when invoked
# with a positional prompt. Redirecting stdin from /dev/null closes it cleanly.
if "$CODEX_BIN" exec --model "$MODEL" --cd "$CODEX_PROJECT_DIR" "$TASK" </dev/null; then
  status=0
else
  status=$?
fi

if [ "$status" = 0 ]; then codex_cost_record fix "$EST"; fi
exit "$status"

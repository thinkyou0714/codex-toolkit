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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

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

# Optional cost gate.
if [ -f "$CODEX_HOME/scripts/cost-breaker.py" ] && codex_have python3; then
  if ! python3 "$CODEX_HOME/scripts/cost-breaker.py" check --label fix 2>/dev/null; then
    echo "Cost circuit-breaker tripped — fix skipped. Override with CODEX_COST_BREAKER_OFF=1." >&2
    [ "${CODEX_COST_BREAKER_OFF:-0}" = "1" ] || exit 3
  fi
fi

MODEL="${CODEX_FIX_MODEL:-gpt-5-codex}"

echo "==> Codex fix in $CODEX_PROJECT_DIR, model=$MODEL"
"$CODEX_BIN" exec --model "$MODEL" --cd "$CODEX_PROJECT_DIR" "$TASK"

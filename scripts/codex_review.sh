#!/usr/bin/env bash
# codex_review.sh — run a Codex code review over the current diff (or a given range).
#
# Portable rewrite: no machine-specific paths, no lab_*.sh helper dependency.
# Honors the cost circuit-breaker if installed (~/.codex/scripts/cost-breaker.py).
#
# Usage:
#   codex_review.sh                 # review uncommitted changes (working tree)
#   codex_review.sh main            # review HEAD vs main
#   codex_review.sh main feature    # review feature vs main
#   CODEX_REVIEW_MODEL=gpt-5-codex codex_review.sh
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

codex_require git || exit 127
codex_require "$CODEX_BIN" || exit 127

BASE="${1:-}"
HEAD_REF="${2:-}"

if [ -n "$BASE" ] && [ -n "$HEAD_REF" ]; then
  DIFF="$(git diff "$BASE...$HEAD_REF")"
  SCOPE="$BASE...$HEAD_REF"
elif [ -n "$BASE" ]; then
  DIFF="$(git diff "$BASE")"
  SCOPE="vs $BASE"
else
  DIFF="$(git diff HEAD)"
  SCOPE="working tree"
fi

if [ -z "$DIFF" ]; then
  echo "No changes to review ($SCOPE)."
  exit 0
fi

# Optional cost gate (estimate-based): check before, record after, so the daily
# ledger actually accumulates and can trip on the Nth call of the day.
EST="${CODEX_REVIEW_EST_USD:-0.20}"
BREAKER="$CODEX_HOME/scripts/cost-breaker.py"
if [ -f "$BREAKER" ] && codex_have python3; then
  if ! python3 "$BREAKER" check --label review --est-usd "$EST" 2>/dev/null; then
    echo "Cost circuit-breaker tripped — review skipped. Override with CODEX_COST_BREAKER_OFF=1." >&2
    [ "${CODEX_COST_BREAKER_OFF:-0}" = "1" ] || exit 3
  fi
fi

MODEL="${CODEX_REVIEW_MODEL:-gpt-5-codex}"

PROMPT="$(cat <<'EOF'
You are a senior code reviewer. Review ONLY the diff below.
Report, grouped by severity (blocker / high / medium / low):
- Correctness bugs, security issues, data-loss risks.
- Reuse/simplification opportunities and dead code.
For each finding give file:line and a concrete fix. Be terse. If clean, say so.

DIFF:
EOF
)"

echo "==> Codex review ($SCOPE), model=$MODEL"
# `codex exec` takes the prompt as a positional argument (the documented form).
# Combine prompt + diff into one argument.
INPUT="$(printf '%s\n\n%s\n' "$PROMPT" "$DIFF")"
if "$CODEX_BIN" exec --model "$MODEL" "$INPUT"; then
  status=0
else
  status=$?
fi

if [ "$status" = 0 ] && [ -f "$BREAKER" ] && codex_have python3; then
  python3 "$BREAKER" record --usd "$EST" --label review >/dev/null 2>&1 || true
fi
exit "$status"

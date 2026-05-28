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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

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

# Optional cost gate.
if [ -f "$CODEX_HOME/scripts/cost-breaker.py" ] && codex_have python3; then
  if ! python3 "$CODEX_HOME/scripts/cost-breaker.py" check --label review 2>/dev/null; then
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
printf '%s\n\n%s\n' "$PROMPT" "$DIFF" | "$CODEX_BIN" exec --model "$MODEL" -

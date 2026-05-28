#!/usr/bin/env bash
# codex_auto_review.sh — review the current diff, then ingest the result into the
# structured failures log so patterns can be tracked over time.
#
# Portable rewrite: log path comes from CODEX_REVIEW_FAILURES_LOG (lib/paths.sh),
# not a hardcoded ~/.lab location.
#
# Usage:
#   codex_auto_review.sh [base] [head]   # same args as codex_review.sh
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

codex_log_dir_ensure

TMP="$(mktemp "${TMPDIR:-/tmp}/codex-review.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

echo "==> Running review (output also captured to log)"
if "$SCRIPT_DIR/codex_review.sh" "$@" | tee "$TMP"; then
  STATUS="ok"
else
  STATUS="error"
fi

if codex_have python3; then
  python3 "$SCRIPT_DIR/codex_review_ingest.py" \
    --input "$TMP" \
    --status "$STATUS" \
    --scope "${*:-working-tree}" || true
fi

echo "==> Ingested to $CODEX_REVIEW_FAILURES_LOG"

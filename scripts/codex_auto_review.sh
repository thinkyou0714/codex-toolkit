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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"

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

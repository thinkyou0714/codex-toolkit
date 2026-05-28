#!/usr/bin/env bash
# save-to-vault.sh — save a research note to the knowledge vault, with optional
# Slack/n8n notification. Env-driven; degrades gracefully when nothing is set.
#
# Root-cause fix vs. original: no hardcoded vault path or webhook. Everything is
# an env var, and missing integrations are skipped (not errors).
#
# Usage: save-to-vault.sh <slug> <path-to-note.md>
set -euo pipefail

SLUG="${1:?usage: save-to-vault.sh <slug> <note.md>}"
SRC="${2:?usage: save-to-vault.sh <slug> <note.md>}"
[ -f "$SRC" ] || { echo "error: note not found: $SRC" >&2; exit 1; }

# Destination: explicit vault, else project-local ./research (with a notice).
if [ -n "${CODEX_VAULT_DIR:-}" ]; then
  DEST_DIR="$CODEX_VAULT_DIR"
else
  DEST_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/research"
  echo "note: CODEX_VAULT_DIR unset; saving into $DEST_DIR" >&2
fi
mkdir -p "$DEST_DIR"

STAMP="$(date -u +%Y-%m-%d)"
# Sanitize slug to a safe filename.
SAFE_SLUG="$(printf '%s' "$SLUG" | tr -c '[:alnum:]._-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')"
DEST="$DEST_DIR/${STAMP}-${SAFE_SLUG}.md"
cp "$SRC" "$DEST"
echo "saved: $DEST"

# Optional notification (skipped silently if unset).
notify_url="${CODEX_SLACK_WEBHOOK_URL:-${CODEX_N8N_WEBHOOK_URL:-}}"
if [ -n "$notify_url" ] && command -v curl >/dev/null 2>&1; then
  payload="$(printf '{"text":"New research note: %s"}' "$DEST")"
  curl -fsS -m 10 -X POST -H 'Content-Type: application/json' \
    -d "$payload" "$notify_url" >/dev/null 2>&1 \
    && echo "notified." || echo "note: notification failed (continuing)." >&2
fi

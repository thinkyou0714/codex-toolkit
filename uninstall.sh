#!/usr/bin/env bash
# uninstall.sh — remove toolkit-installed files. Conservative by design:
# it only removes files this toolkit installs, restores any .bak it finds, and
# NEVER deletes your config.toml or session_context.md (your data).
#
#   --home / --scripts / --claude / --repo / --all / --dry-run   (mirror install.sh)
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
BIN_DIR="${CODEX_BIN_DIR:-$HOME/.local/bin}"
PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

DRY_RUN=0; DO_HOME=0; DO_CLAUDE=0; DO_SCRIPTS=0; DO_REPO=0
for arg in "$@"; do
  case "$arg" in
    --all) DO_HOME=1; DO_CLAUDE=1; DO_SCRIPTS=1; DO_REPO=1 ;;
    --home) DO_HOME=1 ;;
    --claude) DO_CLAUDE=1 ;;
    --scripts) DO_SCRIPTS=1 ;;
    --repo) DO_REPO=1 ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done
[ $((DO_HOME+DO_CLAUDE+DO_SCRIPTS+DO_REPO)) -gt 0 ] || { echo "pass --all or a component flag" >&2; exit 1; }

rm_file() {
  local f="$1"
  [ -e "$f" ] || return 0
  if [ "$DRY_RUN" = 1 ]; then echo "  [dry-run] remove $f"; else echo "  remove $f"; rm -f "$f"; fi
}

if [ "$DO_HOME" = 1 ]; then
  echo "==> --home"
  for f in AGENTS.md AGENTS-full.md env.sh toolkit-root scripts/cost-breaker.py scripts/quota-fallback.py scripts/kill-switch.sh lib/secret_redact.py lib/SecretRedact.psm1; do
    rm_file "$CODEX_HOME/$f"
  done
  echo "  kept: config.toml, session_context.md, cost-ledger.jsonl (your data)"
fi

if [ "$DO_SCRIPTS" = 1 ]; then
  echo "==> --scripts"
  for s in codex_review codex_fix codex_auto_review codex-doctor codex-run; do rm_file "$BIN_DIR/$s"; done
fi

if [ "$DO_REPO" = 1 ]; then
  echo "==> --repo: remove toolkit-installed templates from $PROJECT_DIR"
  # Conservative: remove only the files install.sh ships as templates. Never
  # touch AGENTS.md (user-editable) or .codex/logs/ (user data).
  rm_file "$PROJECT_DIR/.github/workflows/codex-pr-review.yml"
  rm_file "$PROJECT_DIR/.github/codex/review-prompt.md"
  rm_file "$PROJECT_DIR/.github/codex/review-schema.json"
  rm_file "$PROJECT_DIR/.github/copilot-instructions.md.template"
  for d in codex-doctor lab-research; do
    if [ -d "$PROJECT_DIR/.codex/skills/$d" ]; then
      if [ "$DRY_RUN" = 1 ]; then
        echo "  [dry-run] remove $PROJECT_DIR/.codex/skills/$d"
      else
        echo "  remove $PROJECT_DIR/.codex/skills/$d"
        rm -rf "$PROJECT_DIR/.codex/skills/$d"
      fi
    fi
  done
  echo "  kept: AGENTS.md (user-editable), .codex/logs/ (user data)"
fi

if [ "$DO_CLAUDE" = 1 ]; then
  echo "==> --claude"
  rm_file "$PROJECT_DIR/.claude/skills/codex-delegate/SKILL.md"
  rm_file "$PROJECT_DIR/.claude/commands/codex-delegate.md"
  rm_file "$PROJECT_DIR/.claude/hooks/codex_psm_sync.py"
  rm_file "$PROJECT_DIR/.claude/hooks/codex_auto_delegate.py"
  rm_file "$PROJECT_DIR/.claude/scripts/assess_plan_delegatability.py"
  echo "  note: remove the hook registrations from .claude/settings.json yourself."
fi

echo "Done${DRY_RUN:+ (dry-run)}."

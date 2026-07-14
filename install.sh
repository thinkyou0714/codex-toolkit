#!/usr/bin/env bash
# install.sh — install the Codex toolkit into your environment.
#
# Idempotent and safe: existing files are backed up (.bak) before overwrite, and
# --dry-run shows exactly what would happen without touching anything.
#
# Components (choose any; --all selects everything):
#   --home     install global dotfiles to ~/.codex (or $CODEX_HOME)
#   --repo     scaffold the current repo (AGENTS.md, .github, .codex skills)
#   --claude   install the Claude Code drop-in into ./.claude
#   --scripts  symlink/copy the portable scripts onto PATH (~/.local/bin)
#
# Examples:
#   ./install.sh --all --dry-run
#   ./install.sh --home --scripts
#   CODEX_HOME=/custom ./install.sh --home
set -euo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
BIN_DIR="${CODEX_BIN_DIR:-$HOME/.local/bin}"
PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

DRY_RUN=0
DO_HOME=0 DO_REPO=0 DO_CLAUDE=0 DO_SCRIPTS=0

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

for arg in "$@"; do
  case "$arg" in
    --all)      DO_HOME=1; DO_REPO=1; DO_CLAUDE=1; DO_SCRIPTS=1 ;;
    --home)     DO_HOME=1 ;;
    --repo)     DO_REPO=1 ;;
    --claude)   DO_CLAUDE=1 ;;
    --scripts)  DO_SCRIPTS=1 ;;
    --dry-run)  DRY_RUN=1 ;;
    -h|--help)  usage 0 ;;
    *) echo "unknown arg: $arg" >&2; usage 1 ;;
  esac
done

if [ $((DO_HOME+DO_REPO+DO_CLAUDE+DO_SCRIPTS)) -eq 0 ]; then
  echo "nothing selected. Pass --all or one of --home/--repo/--claude/--scripts." >&2
  usage 1
fi

say() { echo "  $*"; }
run() {
  # run <description> <cmd...>
  local desc="$1"; shift
  if [ "$DRY_RUN" = 1 ]; then
    say "[dry-run] $desc"
  else
    say "$desc"
    "$@"
  fi
}

# copy_file SRC DEST — back up an existing, differing DEST, then copy.
copy_file() {
  local src="$1" dest="$2"
  if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
    run "backup $dest -> $dest.bak" cp "$dest" "$dest.bak"
  fi
  run "install $dest" bash -c 'mkdir -p "$(dirname "$2")" && cp "$1" "$2"' _ "$src" "$dest"
}

# copy_tree SRC_DIR DEST_DIR
copy_tree() {
  local src="$1" dest="$2"
  ( cd "$src" && find . -type f -print0 ) | while IFS= read -r -d '' rel; do
    copy_file "$src/${rel#./}" "$dest/${rel#./}"
  done
}

echo "Codex toolkit installer"
echo "  toolkit: $TOOLKIT_ROOT"
[ "$DRY_RUN" = 1 ] && echo "  MODE: dry-run (no changes will be made)"

if [ "$DO_HOME" = 1 ]; then
  echo "==> --home: ~/.codex ($CODEX_HOME)"
  copy_file "$TOOLKIT_ROOT/home/AGENTS.md"               "$CODEX_HOME/AGENTS.md"
  copy_file "$TOOLKIT_ROOT/home/AGENTS-full.md"          "$CODEX_HOME/AGENTS-full.md"
  copy_file "$TOOLKIT_ROOT/home/env.sh"                  "$CODEX_HOME/env.sh"
  copy_file "$TOOLKIT_ROOT/home/scripts/cost-breaker.py" "$CODEX_HOME/scripts/cost-breaker.py"
  copy_file "$TOOLKIT_ROOT/home/scripts/quota-fallback.py" "$CODEX_HOME/scripts/quota-fallback.py"
  # v0.2.0 minimal safety primitives.
  copy_file "$TOOLKIT_ROOT/home/scripts/kill-switch.sh"    "$CODEX_HOME/scripts/kill-switch.sh"
  copy_file "$TOOLKIT_ROOT/home/lib/secret_redact.py"      "$CODEX_HOME/lib/secret_redact.py"
  copy_file "$TOOLKIT_ROOT/home/lib/SecretRedact.psm1"     "$CODEX_HOME/lib/SecretRedact.psm1"
  # v0.3.0: the /goal delegation brief template.
  copy_file "$TOOLKIT_ROOT/home/templates/goal.md"         "$CODEX_HOME/templates/goal.md"
  # Examples are installed only if the real file is absent (never clobber config).
  [ -f "$CODEX_HOME/config.toml" ] || copy_file "$TOOLKIT_ROOT/home/config.toml.example" "$CODEX_HOME/config.toml"
  [ -f "$CODEX_HOME/cloud.config.toml" ] || copy_file "$TOOLKIT_ROOT/home/cloud.config.toml.example" "$CODEX_HOME/cloud.config.toml"
  [ -f "$CODEX_HOME/session_context.md" ] || copy_file "$TOOLKIT_ROOT/home/session_context.md.example" "$CODEX_HOME/session_context.md"
  # Record where the toolkit lives so skills can resolve it.
  run "write $CODEX_HOME/toolkit-root" bash -c 'mkdir -p "$1" && printf "%s\n" "$2" > "$1/toolkit-root"' _ "$CODEX_HOME" "$TOOLKIT_ROOT"
  echo "  note: add 'export CODEX_TOOLKIT_ROOT=$TOOLKIT_ROOT' and 'source $CODEX_HOME/env.sh' to your shell rc."
fi

if [ "$DO_SCRIPTS" = 1 ]; then
  echo "==> --scripts: $BIN_DIR"
  # Symlink (not copy) so wrappers always resolve their sibling lib/paths.sh in
  # the real toolkit checkout. A copy would orphan them from lib/ and break.
  run "mkdir -p $BIN_DIR" mkdir -p "$BIN_DIR"
  for s in codex_review.sh codex_fix.sh codex_auto_review.sh codex-doctor.sh codex-run.sh codex-goal.sh codex-cloud-setup.sh; do
    # codex-doctor.sh keeps its dash in the installed name (it's a one-shot
    # diagnostic, not a verb).
    case "$s" in
      codex-doctor.sh) link_name="codex-doctor" ;;
      *)               link_name="${s%.sh}" ;;
    esac
    run "symlink $BIN_DIR/$link_name -> $TOOLKIT_ROOT/scripts/$s" \
      ln -sf "$TOOLKIT_ROOT/scripts/$s" "$BIN_DIR/$link_name"
  done
  echo "  note: ensure $BIN_DIR is on your PATH."
fi

if [ "$DO_REPO" = 1 ]; then
  echo "==> --repo: scaffold $PROJECT_DIR"
  [ -f "$PROJECT_DIR/AGENTS.md" ] || copy_file "$TOOLKIT_ROOT/repo-template/AGENTS.md.template" "$PROJECT_DIR/AGENTS.md"
  copy_tree "$TOOLKIT_ROOT/repo-template/.github" "$PROJECT_DIR/.github"
  copy_tree "$TOOLKIT_ROOT/repo-template/.codex"  "$PROJECT_DIR/.codex"
  echo "  note: AGENTS.md was scaffolded from a template — fill in the {{PLACEHOLDERS}}."
fi

if [ "$DO_CLAUDE" = 1 ]; then
  echo "==> --claude: ./.claude"
  copy_tree "$TOOLKIT_ROOT/claude-integration/skills"   "$PROJECT_DIR/.claude/skills"
  copy_tree "$TOOLKIT_ROOT/claude-integration/commands" "$PROJECT_DIR/.claude/commands"
  copy_tree "$TOOLKIT_ROOT/claude-integration/hooks"    "$PROJECT_DIR/.claude/hooks"
  copy_tree "$TOOLKIT_ROOT/claude-integration/scripts"  "$PROJECT_DIR/.claude/scripts"
  echo "  note: register hooks in .claude/settings.json using ABSOLUTE \$CLAUDE_PROJECT_DIR paths"
  echo "        (see claude-integration/README.md). Relative hook paths break on cd."
fi

echo "Done${DRY_RUN:+ (dry-run)}."

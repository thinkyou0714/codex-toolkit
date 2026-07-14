#!/usr/bin/env bash
# shellcheck shell=bash
# scripts/lib/wrappers.sh — single source of truth for the scripts/ wrappers that
# install.sh symlinks onto PATH and uninstall.sh removes.
#
# Why this exists (root-cause fix): the install list, the uninstall list, and the
# link-name transform were three hand-kept copies. Adding a wrapper meant editing
# each; forgetting the uninstall side left a dangling symlink in ~/.local/bin
# pointing at a deleted checkout ("command not found" from a command that was
# supposedly uninstalled). Now both installers derive from one list.
#
# Emit one "<source-basename-in-scripts/> <installed-link-name>" pair per line.
# The link-name is explicit (no transform to keep in sync) — e.g. codex-doctor
# keeps its dash because it's a one-shot diagnostic, not a verb.
codex_wrapper_manifest() {
  cat <<'LIST'
codex_review.sh codex_review
codex_fix.sh codex_fix
codex_auto_review.sh codex_auto_review
codex-doctor.sh codex-doctor
codex-run.sh codex-run
codex-goal.sh codex-goal
codex-cloud-setup.sh codex-cloud-setup
LIST
}

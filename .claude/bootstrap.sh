#!/bin/sh
# Idempotent dev-tooling bootstrap for Makefile-based (shell/python) repos.
# Installs the pip-installable lint tools `make check` needs so it works in a cloud session.
# shellcheck is normally pre-installed in the Claude Code web sandbox. No-op once ruff is present.
dir="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$dir" || exit 0

if [ -f Makefile ] && ! command -v ruff >/dev/null 2>&1; then
  pip install --quiet ruff codespell 2>/dev/null || true
fi

exit 0

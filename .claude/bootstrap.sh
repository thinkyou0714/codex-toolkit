#!/bin/sh
# Idempotent dev-tooling bootstrap for Makefile-based (shell/python) repos.
# Installs the pip-installable lint tools `make check` needs so it works in a cloud session.
# (ShellCheck itself is usually pre-installed in the web sandbox.) No-op once ruff is present.
dir="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$dir" || exit 0

if [ -f Makefile ] && ! command -v ruff >/dev/null 2>&1; then
  pip install --quiet ruff codespell 2>/dev/null || true
fi

# Make the Codex CLI usable in this cloud session (install + auth + profile).
# Best-effort and quiet; opt out with CODEX_CLOUD_BOOTSTRAP=0. See docs/CLOUD.md.
if [ "${CODEX_CLOUD_BOOTSTRAP:-1}" != "0" ] && [ -f scripts/codex-cloud-setup.sh ]; then
  bash scripts/codex-cloud-setup.sh --quiet --no-egress 2>/dev/null || true
fi

exit 0

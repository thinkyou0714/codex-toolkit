# AGENTS.md — codex-toolkit

This repo IS a Codex CLI dev-OS toolkit, and it is also worked on by Codex/Claude.
These instructions govern changes to the toolkit itself.

## What this project is
A portable, installable toolkit that gives any repository a consistent "dev OS"
for the Codex CLI: global `~/.codex` dotfiles, portable review/fix scripts, a
per-repo template (AGENTS.md + CI + skills), and an optional Claude Code
integration. See `README.md` and `docs/ARCHITECTURE.md`.

## Layout
- `home/` — files installed to `~/.codex` (global agent config, cost breaker).
- `scripts/` — portable wrappers; `scripts/lib/paths.sh` is the single source of
  truth for path/env resolution. **All scripts must source it; never hardcode
  machine-specific paths.**
- `repo-template/` — dropped into target repos.
- `claude-integration/` — optional Claude Code drop-in.
- `docs/` — architecture, setup, strategy, prompt patterns.
- `tests/smoke.sh` — the smoke test; CI runs it.

## Build / test (run before declaring done)
```bash
bash tests/smoke.sh                 # shell syntax, py compile, install dry-run
command -v shellcheck && shellcheck scripts/*.sh home/*.sh install.sh uninstall.sh
```

## Hard rules (root-cause lessons baked into this repo)
1. **No hardcoded machine paths.** No `//wsl$/...`, no `C:/Users/<name>/...`, no
   `~/.lab/...`. Resolve via env vars + `scripts/lib/paths.sh` with fallbacks.
2. **No secrets in the repo.** `.example`/`.template` only; reference secrets by
   env-var name. Integrations must skip gracefully when their env var is unset.
3. **Hooks use absolute `$CLAUDE_PROJECT_DIR` paths**, never bare relative paths
   — a relative hook command breaks when the working directory changes and can
   disable the whole hook system at once. (This bit a previous session.)
4. **Installer stays idempotent**: back up before overwrite, support `--dry-run`,
   never clobber user data (`config.toml`, `session_context.md`).
5. Keep `home/AGENTS.md` small and its top section byte-stable (prompt-cache
   friendliness); detail goes in `AGENTS-full.md`.
6. **Wrappers that log codex invocations MUST redact** through
   `home/lib/secret_redact.py` before writing to `failures.jsonl` (or any other
   log). The lib is the single source of truth for the 8 patterns; do not roll
   your own regex set. PowerShell wrappers use `home/lib/SecretRedact.psm1`.
7. **Wrappers MUST honor the kill switch.** Before invoking `codex`, call
   `kill-switch check` (exit 0 = clear, exit 1 = ACTIVE). When ACTIVE, refuse to
   run and exit 7. `scripts/codex-run.sh` is the reference implementation —
   prefer wrapping it over re-implementing the gate.

## Conventions
- Bash: `set -euo pipefail`, source `lib/paths.sh`, shellcheck-clean.
- Python: stdlib only, no third-party deps; must `python3 -m py_compile` clean.
- Commit style: Conventional Commits, imperative mood.

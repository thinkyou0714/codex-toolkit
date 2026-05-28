# Changelog

All notable changes to this project are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); this project uses semantic
versioning.

## [0.1.0] - 2026-05-28

Initial extraction of the Codex CLI dev-OS toolkit into a standalone repo.

### Added
- Four installable layers: global `~/.codex` config (`home/`), portable
  review/fix scripts (`scripts/`), per-repo template (`repo-template/`), and an
  optional Claude Code integration (`claude-integration/`).
- Idempotent `install.sh`/`uninstall.sh` with `--dry-run` and component flags.
- Cost circuit-breaker (`cost-breaker.py`) with daily/per-call ceilings, now
  wired into the wrappers (estimate-based check + record).
- Provider quota fallback (`quota-fallback.py`).
- Per-repo Codex PR-review GitHub Action, review prompt, and JSON schema.
- `codex-doctor` and `lab-research` skills; Claude delegate skill/command/hooks.
- Docs: ARCHITECTURE, SETUP, STRATEGY, PROMPT-PATTERNS.
- CI (shellcheck `-S warning` + py compile + smoke) and `tests/smoke.sh`.
- `Makefile`, `.env.example`, `CONTRIBUTING.md`, MIT `LICENSE`.

### Fixed (hardening pass)
- Installed wrappers now resolve `lib/paths.sh` even when invoked through a
  symlink in `~/.local/bin`; `install.sh --scripts` symlinks instead of copying
  so wrappers are never orphaned from their lib.
- Cost breaker is now functional end-to-end: wrappers pass an estimate to
  `check` and `record` it after a successful run, so the daily ledger
  accumulates and can actually trip.
- Corrected the PR-review workflow's security note (it uses `pull_request`, not
  `pull_request_target`) and replaced the unused Python setup step with Node.
- PSM-sync hook now caps auto-appended notes (`CODEX_PSM_MAX_NOTES`, default 50)
  so the file can't grow unbounded.

### Root-cause portability fixes
- Removed all machine-specific hardcodes (`//wsl$/...`, `C:/Users/...`,
  `~/.lab/...`) in favor of env resolution via `scripts/lib/paths.sh`.
- Versioned the previously-unversioned `~/.codex` dotfiles.
- Removed embedded secrets; integrations skip gracefully when env is unset.
- Documented absolute `$CLAUDE_PROJECT_DIR` hook paths to prevent the
  relative-path "cd disables all hooks" failure mode.

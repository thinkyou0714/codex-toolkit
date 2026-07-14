# Changelog

All notable changes to this project are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); this project uses semantic
versioning.

## [0.3.0] - 2026-07-14

Cloud enablement + goal-contract delegation: make the Codex CLI a one-command
property of any cloud session, and make delegation to Codex deterministic.

### Added
- `scripts/codex-cloud-setup.sh` — idempotent cloud/CI bootstrap: environment
  detection (github-actions / codespaces / devcontainer / claude-cloud /
  container), npm install of the CLI (pin via `CODEX_CLI_VERSION`), headless
  auth wiring (`OPENAI_API_KEY` piped to `codex login --with-api-key`,
  `CODEX_AUTH_JSON(_B64)` restored 0600, `CODEX_API_KEY` recognized), global
  toolkit install, cloud profile seeding, and an egress preflight that names
  blocked domains. `--dry-run` / `--check` / `--strict` / `--no-egress`.
- `scripts/codex-goal.sh` — /goal-contract delegation to `codex exec`: renders
  a complete brief (purpose / target files / out-of-bounds / definition of
  done / verify) from `home/templates/goal.md`, gates through the kill switch
  (exit 7) and cost breaker (exit 3), applies a portable watchdog timeout
  (`CODEX_GOAL_TIMEOUT_S`, default 300s — `codex exec` has no built-in
  timeout), retries once, and exits 6 ("escalate") after two consecutive
  failures so orchestrators can branch deterministically. Prints
  `git diff --stat` + the `-o` last-message path as evidence on success.
- `home/templates/goal.md` — the bilingual /goal brief template, including the
  autonomy snippet ("do not stop at investigation") and a blocked-stop
  condition, per OpenAI's Goals/prompting guidance.
- `home/cloud.config.toml.example` — non-interactive cloud profile overlay
  (`codex exec -p cloud`): `approval_policy = "never"`, workspace-write with
  sandbox network access on. Installed to `~/.codex/cloud.config.toml` only
  when absent; treated as user data by uninstall.
- Claude integration: `codex-goal` skill + `/codex-goal` command encoding the
  full protocol (resolve spec forks before delegating; verify the diff, not
  the summary; exit-code branching; no silent third retry).
- `codex-doctor.sh` — new "Cloud readiness" section (environment, npm/CLI,
  auth state incl. env credentials, proxy/CA visibility) and an opt-in
  `--network` egress probe of the three OpenAI endpoints.
- `.claude/bootstrap.sh` now runs the cloud setup on SessionStart (best
  effort, quiet; opt out with `CODEX_CLOUD_BOOTSTRAP=0`).
- `tests/test_cloud.sh` (wired into `smoke.sh`): dry-run purity, auth wiring
  via secret and via API key (stub codex), /goal brief rendering, watchdog
  timeout → retry → exit 6, kill-switch exit 7, and the install/uninstall
  round-trip for the new files.
- Docs: `docs/CLOUD.md` (auth matrix, network-policy domains, container
  sandboxing, GitHub Actions recipes, headless gotchas) and
  `docs/IDEAS-100.md` (100-idea catalog for using Codex as the implementation
  worker, with per-idea implementation status).

### Changed
- `install.sh --home` also installs `templates/goal.md` and seeds
  `cloud.config.toml`; `--scripts` symlinks `codex-goal` and
  `codex-cloud-setup`. `uninstall.sh` mirrors both (keeps
  `cloud.config.toml`).
- `home/env.sh` / `.env.example`: new `CODEX_GOAL_*`, `CODEX_CLI_VERSION`,
  `CODEX_CLOUD_BOOTSTRAP` tunables.
- `home/config.toml.example`: removed the retired `on-failure` approval
  policy from the comments.
- Consolidated duplication into `scripts/lib/paths.sh` (the single-source-of-
  truth resolver): `codex_cloud_env`, `CODEX_OPENAI_HOSTS` + `codex_egress_probe`
  (shared by the setup preflight and the doctor probe), `codex_auth_env_source`,
  and `codex_cost_gate` / `codex_cost_record` (now used by `codex_fix`,
  `codex_review`, and `codex-goal` instead of three inline copies).
- `codex-goal.sh` now records watchdog timeouts and escalations to
  `failures.jsonl` (redacted) — a run the watchdog kills can't self-log through
  `codex-run.sh`, so incident triage would otherwise be blind to timeouts.
- `scripts/lib/wrappers.sh` — one manifest of the PATH wrappers, sourced by
  `install.sh` and `uninstall.sh` so the two lists (and the link-name rule)
  can't drift; adding a wrapper is now a one-line edit instead of three, and a
  forgotten uninstall entry (which left a dangling symlink) is impossible.
- `tests/lib/stub_codex.sh` — one `make_stub_codex` factory replaces four inline
  fake-`codex` heredocs across the suites, centralizing the stdin-drain
  invariant a stale copy used to violate (and deadlock the run).

## [0.2.0] - 2026-05-29

Quality bump (evaluation gap closure) + minimal LAB safety primitives port.

### Added
- Cross-platform CI: the smoke suite now runs on a `{ubuntu, macos}` matrix, so
  the portable-path / bash-3.2 promises are exercised on macOS too.
- Tag-driven `release.yml`: pushing a `v*` tag verifies the tag matches
  `VERSION` and that a matching `CHANGELOG` section exists, runs the smoke
  suite, then publishes that section as release notes via the preinstalled
  `gh` CLI (no third-party action).
- `scripts/bump-version.sh` to bump `VERSION` and seed a `CHANGELOG` section in
  one step, with `make bump` / `make release-check` targets.
- Ambiguity dampener in `assess_plan_delegatability.py`: exploratory markers
  ("investigate", "maybe", "figure out", …) reduce the score so vague work
  stays inline instead of auto-delegating on breadth keywords alone. Repeated
  in-category signals now add a small, capped bonus.
- New smoke coverage: `codex-doctor --strict` end-to-end on a fully-wired
  setup, installer no-arg/unknown-arg handling, dry-run touches nothing on
  disk, severity-tag parsing, the ambiguity dampener, and VERSION↔CHANGELOG
  sync.
- `home/lib/secret_redact.py` — single-source-of-truth 8-pattern secret redaction
  library (Bearer / `sk-` / `xai-` / `api_key` / `x-api-key` / `token` /
  `Authorization` / `user:pass@`). Importable + CLI + `--selftest` (8/8).
- `home/lib/SecretRedact.psm1` — PowerShell mirror for cross-shell parity.
- `home/scripts/kill-switch.sh` — file-flag emergency stop
  (`activate <reason>` / `deactivate` / `check` / `status`). Wrappers refuse to
  invoke codex when ACTIVE. Audit appends to `$CODEX_LOG_DIR/failures.jsonl`.
- `scripts/codex-run.sh` — thin wrapper around `codex exec` that honors the
  kill-switch gate and redacts arguments before they hit the failure log.
  Symlinked to `$CODEX_BIN_DIR/codex-run` by `install.sh --scripts`.
- `tests/test_safety.sh` — invoked by `smoke.sh`; covers the new primitives
  end-to-end (selftest 8/8 + kill-switch round-trip + audit log entries).
- `docs/SAFETY.md` — what's in v0.2.0, what's intentionally deferred, and the
  kill-switch operations runbook.

### Changed
- `codex_review_ingest.py` now reads severity only from explicit tags
  (`[HIGH]`, leading `HIGH:`, `severity: high`) instead of any stray word, so a
  phrase like "the low-level cache" no longer mis-scores a finding as `low`.
- `scripts/codex-doctor.sh` gains a "Safety primitives" section: verifies the
  redact lib is installed and passes 8/8, that `kill-switch.sh` is present, and
  reports the current switch state (warns if ACTIVE > 24h — likely forgotten).
- `install.sh --home` now also installs `home/lib/*` and `home/scripts/kill-switch.sh`.
- `install.sh --scripts` symlinks `codex-run.sh` alongside the other wrappers.
- `.github/workflows/ci.yml` lint job's ShellCheck now covers the new
  `home/scripts/*.sh` and `tests/*.sh` files added in 0.2.0.

### Fixed
- Default branch was `claude/vibrant-pasteur-CFfhR` from the initial cloud
  scaffolding — `main` now exists and is the default.
- Three comment-only `/home/rikuto` references in
  `claude-integration/hooks/codex_psm_sync.py` and `scripts/lib/paths.sh`
  genericized to `<legacy-user-home>` (matches AGENTS.md "No hardcoded machine
  paths" rule; eliminates personal-username leak on this public repo).

### Deferred (planned for v0.3.0+)
- Bernstein composition chain (codex_safe → codex_logged → codex_observed).
- Egress allowlist + DNS pinning (SSRF defense).
- Iteration guard (doom-loop detection).
- SLO percentile checker.
- See `docs/SAFETY.md` for the full scope decision and roadmap.

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
- Verified against the real Codex CLI docs and fixed mismatches:
  - Removed the fictional `allowed_hosts` array from `[sandbox_workspace_write]`
    in `config.toml.example`; per-domain restriction is via
    `[features.network_proxy]` and is now documented as such.
  - Clarified `approval_policy = "on-failure"` semantics in the example comment.
- After a closer read (openai/codex PR #15917 and issue #20919), reverted to
  the stdin-`-` form for `codex_review.sh` and the PR-review workflow, which
  IS the documented way to feed a long prompt and is ARG_MAX-safe. An earlier
  switch to positional was based on incomplete info and would have failed on
  large diffs.
- Added `</dev/null` to the `codex exec` call in `codex_fix.sh` to work around
  openai/codex#20919, where a positional-prompt invocation hangs forever in
  non-interactive shells waiting for stdin EOF.
- Added `uninstall.sh --repo` for symmetry with `install.sh --repo`. Removes
  only template files; never touches `AGENTS.md` (user-editable) or
  `.codex/logs/` (user data).
- Smoke now includes an end-to-end mock-codex test (stub `codex` on PATH +
  real cost-breaker against an isolated ledger), guards against the stdin/
  positional regression, asserts the `</dev/null` workaround is present, and
  covers the new `--repo` round-trip including AGENTS.md preservation.

### Added (pass 5: best-practice hardening)
- `SECURITY.md` — documented threat model, secret handling, CI/hook
  considerations, supply-chain notes, and vulnerability-reporting path.
- `scripts/codex-doctor.sh` — real, deterministic health check (CLI present,
  version, env vars, `~/.codex` layout, cost-breaker status, project wiring,
  Claude hook absolute-path check). The most valuable check it adds: catches
  unfilled `{{PLACEHOLDERS}}` in a scaffolded `AGENTS.md` — the #1 silent
  post-install mistake. `make doctor` invokes it; `install.sh --scripts`
  symlinks it as `codex-doctor` on PATH.
- `.editorconfig` for consistent whitespace across editors.
- `.github/ISSUE_TEMPLATE/bug_report.md` (requires doctor output).

### Fixed (pass 5)
- `paths.sh` was resolving `CODEX_TOOLKIT_ROOT` to the `scripts/` subdir
  instead of the repo root (one `..` short). Functionally benign because all
  consumers used other env vars, but `codex-doctor` surfaced the wrong value
  on its very first run. Fixed to `../..` and added a smoke regression guard
  asserting `CODEX_TOOLKIT_ROOT` contains `install.sh`.

### Root-cause portability fixes
- Removed all machine-specific hardcodes (`//wsl$/...`, `C:/Users/...`,
  `~/.lab/...`) in favor of env resolution via `scripts/lib/paths.sh`.
- Versioned the previously-unversioned `~/.codex` dotfiles.
- Removed embedded secrets; integrations skip gracefully when env is unset.
- Documented absolute `$CLAUDE_PROJECT_DIR` hook paths to prevent the
  relative-path "cd disables all hooks" failure mode.

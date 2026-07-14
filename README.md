# codex-toolkit

A portable, installable **dev OS for the Codex CLI**. It gives any repository a
consistent agent setup: global `~/.codex` configuration, portable review/fix
scripts, a per-repo template (AGENTS.md + CI + skills), and an optional Claude
Code integration so Claude can delegate work to Codex.

It is the extraction and hardening of a setup that previously lived tangled
inside a monorepo, with the machine-specific hardcodes and unversioned config
turned into portable, versioned, env-driven components.

## Why

Agent setups rot when they're ad-hoc: paths get hardcoded to one laptop, the
global `~/.codex` config is unversioned and "lost" if the machine dies, secrets
leak into scripts, and cost controls are an afterthought. This toolkit fixes
those at the root and ships them as something you can `install.sh` into any repo.

## What's inside

```
home/               -> installs to ~/.codex (global agent config)
  AGENTS.md(+full)  compressed global instructions (+ full reference)
  config.toml.example, cloud.config.toml.example, env.sh
  templates/goal.md (the /goal delegation brief)
  scripts/cost-breaker.py, quota-fallback.py, kill-switch.sh
scripts/            portable wrappers (review/fix/auto-review/goal/cloud-setup)
                    + lib/paths.sh
repo-template/      drop into any repo: AGENTS.md, .github CI, .codex skills
claude-integration/ optional Claude Code drop-in (skills, commands, hooks)
docs/               ARCHITECTURE, SETUP, STRATEGY, PROMPT-PATTERNS,
                    CLOUD (cloud/CI setup), IDEAS-100 (usage catalog, ja)
install.sh / uninstall.sh   idempotent, --dry-run
tests/smoke.sh      validation; CI runs it
```

## Quick start

```bash
# See exactly what would happen, change nothing:
./install.sh --all --dry-run

# Install the global config + scripts on PATH:
./install.sh --home --scripts
# then add to your shell rc:
#   export CODEX_TOOLKIT_ROOT=/path/to/codex-toolkit
#   source ~/.codex/env.sh

# Scaffold the repo you're standing in:
./install.sh --repo        # AGENTS.md + .github CI + .codex skills

# Optional: wire up Claude Code delegation:
./install.sh --claude      # then register hooks (see claude-integration/README.md)
```

Validate any time with `bash tests/smoke.sh` (or `codex-doctor` once installed).

## Design principles (root-cause fixes baked in)

- **No machine-specific paths.** Everything resolves through env vars and
  `scripts/lib/paths.sh` with sane fallbacks (`CODEX_HOME`, `CODEX_LOG_DIR`, …).
- **No secrets in the repo.** `.example`/`.template` only; integrations skip
  gracefully when their env var is unset.
- **Versioned global config.** The previously-"lost" `~/.codex` files now live
  here and are reinstallable.
- **Cost-safe by default.** A circuit-breaker enforces daily/per-call ceilings.
- **Absolute hook paths.** Claude hooks use `$CLAUDE_PROJECT_DIR`, so a `cd`
  can never silently disable them.

See `docs/ARCHITECTURE.md` for the full picture and `docs/SETUP.md` to get going.

## Safety (v0.2.0+)

Two minimal primitives that every wrapper honors:

- **Secret redaction** — `home/lib/secret_redact.py` (+ `SecretRedact.psm1`) is
  the single source of truth for the 8 patterns that get scrubbed before any
  command line / failure detail hits the log.
- **Kill switch** — `kill-switch activate "<reason>"` stops every codex
  invocation in one place; `kill-switch deactivate` resumes. `codex-doctor`
  warns if it's been ACTIVE > 24h.

What's intentionally deferred (egress allowlist, iteration guard, SLO checker,
the Bernstein composition chain) is documented in [docs/SAFETY.md](docs/SAFETY.md).

## License

MIT — see `LICENSE`.

## Claude Code で使う (web / cloud 対応)

このリポジトリは **Claude Code on the web** に対応しています。

- lint ツール（ruff/codespell）は `.claude/bootstrap.sh`（SessionStart）が pip で自動インストール。`make test`（smoke）は追加依存なし。
- 同じフックが `scripts/codex-cloud-setup.sh` を実行し、**Codex CLI をクラウドセッションで即使える状態**にします（インストール → 認証 → cloud プロファイル）。無効化は `CODEX_CLOUD_BOOTSTRAP=0`。前提・認証・ネットワークポリシーは [`docs/CLOUD.md`](docs/CLOUD.md)。
- 実装タスクの委譲は `scripts/codex-goal.sh`（/goal 契約 + 5 分ウォッチドッグ + 2 連続失敗でエスカレート）。活用アイデア 100 連発は [`docs/IDEAS-100.md`](docs/IDEAS-100.md)。
- クラウドセッションは `AGENTS.md` と `.claude/skills/`（例: `run-checks`）を自動ロード。
- MCP は本リポジトリではローカル専用。詳細は
  [`.github/docs/claude-code-web-readiness.md`](https://github.com/thinkyou0714/.github/blob/main/docs/claude-code-web-readiness.md)。

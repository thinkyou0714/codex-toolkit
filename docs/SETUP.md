# Setup

## Prerequisites
- The Codex CLI on PATH (`command -v codex`). Install per OpenAI's instructions.
- `python3` (stdlib only; no pip installs needed).
- `git`. Optionally `shellcheck` for linting.
- An API key in your environment (e.g. `export OPENAI_API_KEY=...`). Never put
  it in any file in this repo.

## 1. Install the global layer

```bash
./install.sh --home --scripts --dry-run   # preview
./install.sh --home --scripts             # do it
```

Then wire your shell (add to `~/.bashrc` / `~/.zshrc`):

```bash
export CODEX_TOOLKIT_ROOT="/absolute/path/to/codex-toolkit"
source "$HOME/.codex/env.sh"
export PATH="$HOME/.local/bin:$PATH"     # if you used --scripts
```

Open a new shell and verify:

```bash
codex_review.sh --help 2>/dev/null || true
python3 ~/.codex/scripts/cost-breaker.py status
```

## 2. Configure Codex

```bash
# install.sh --home created ~/.codex/config.toml from the example only if absent.
$EDITOR ~/.codex/config.toml      # set model, sandbox_mode, allowed_hosts, MCP
```

Tune the cost ceilings in `~/.codex/env.sh` (`CODEX_COST_DAILY_USD`,
`CODEX_COST_PER_CALL_USD`).

## 3. Scaffold a project

From inside the target repo:

```bash
/path/to/codex-toolkit/install.sh --repo
$EDITOR AGENTS.md                 # fill in the {{PLACEHOLDERS}}
```

This adds `AGENTS.md`, `.github/workflows/codex-pr-review.yml` (+ prompt/schema),
and `.codex/skills/`. For the PR-review workflow, add the repo secret
`OPENAI_API_KEY` in your Git host's settings.

## 4. (Optional) Claude Code integration

```bash
/path/to/codex-toolkit/install.sh --claude
```

Then register the hooks in `.claude/settings.json` with **absolute**
`$CLAUDE_PROJECT_DIR` paths — see `claude-integration/README.md`. The
`update-config` skill can do this safely. (Relative hook paths break the moment
the working directory changes — a real failure mode.)

## 5. Health check

```bash
bash /path/to/codex-toolkit/tests/smoke.sh
# or, in a scaffolded repo, run the codex-doctor skill.
```

## Uninstall

```bash
./uninstall.sh --all --dry-run
./uninstall.sh --all          # keeps your config.toml, session_context.md, ledger
```

## Troubleshooting
- **`codex: command not found`** — install the CLI, ensure it's on PATH.
- **Breaker trips immediately** — check `cost-breaker.py status`; raise the caps
  in `env.sh` or `reset` today's ledger if it's stale.
- **Hooks silently stopped firing** — you almost certainly used a relative path;
  switch to `$CLAUDE_PROJECT_DIR/...`.
- **`origin/HEAD` points at an old branch** — if
  `git symbolic-ref refs/remotes/origin/HEAD` shows a deleted or non-default
  branch, refresh the local remote default with `git remote set-head origin -a`.

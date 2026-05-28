# Architecture

The toolkit is organized in four layers, from global to project-specific. Each
layer is independently installable.

```
┌─────────────────────────────────────────────────────────────┐
│ 1. GLOBAL  (home/  ->  ~/.codex)                              │
│    AGENTS.md (+full), config.toml, env.sh, session_context.md │
│    scripts/cost-breaker.py, quota-fallback.py                 │
│    Applies to every repo on the machine.                      │
├─────────────────────────────────────────────────────────────┤
│ 2. PORTABLE TOOLS  (scripts/)                                 │
│    lib/paths.sh  <- single source of truth for paths/env      │
│    codex_review.sh / codex_fix.sh / codex_auto_review.sh      │
│    codex_review_ingest.py                                     │
├─────────────────────────────────────────────────────────────┤
│ 3. REPO TEMPLATE  (repo-template/  ->  a target repo)         │
│    AGENTS.md, .github (CI + review prompt/schema),            │
│    .codex/skills/{codex-doctor, lab-research}                 │
├─────────────────────────────────────────────────────────────┤
│ 4. CLAUDE INTEGRATION  (claude-integration/  ->  ./.claude)   │
│    skill + command (delegate to Codex), hooks (PSM, delegate) │
└─────────────────────────────────────────────────────────────┘
```

## Path/env resolution (the spine)

`scripts/lib/paths.sh` is sourced by every script and is the only place that
decides where things live. It resolves, in order, an explicit env var → a sane
default:

| Variable                     | Default                            | Replaces hardcode |
|------------------------------|------------------------------------|-------------------|
| `CODEX_HOME`                 | `$HOME/.codex`                     | `//wsl$/...`      |
| `CODEX_TOOLKIT_ROOT`         | resolved from the file location    | `C:/Users/...`    |
| `CODEX_PROJECT_DIR`          | `git rev-parse --show-toplevel`    | implicit cwd      |
| `CODEX_LOG_DIR`              | `$CODEX_PROJECT_DIR/.codex/logs`   | `~/.lab/codex`    |
| `CODEX_REVIEW_FAILURES_LOG`  | `$CODEX_LOG_DIR/review-failures.jsonl` | "                |

This is why a script written for one laptop now runs anywhere.

## Data flow: review → ingest

```
codex_auto_review.sh
  └─ codex_review.sh  ──(diff)──> codex exec ──(findings)──> stdout + tmpfile
                                                              │
       codex_review_ingest.py  <─────────────────────────────┘
              └─ append structured JSONL to CODEX_REVIEW_FAILURES_LOG
                 (query trends with: codex_review_ingest.py --stats)
```

## Cost & resilience

- `cost-breaker.py` keeps a per-UTC-day ledger and refuses work past a daily or
  per-call ceiling. Wrappers call `check` before launching Codex. It is
  override-able (`CODEX_COST_BREAKER_OFF=1`) but trips are meant to make you
  stop and think, not push through.
- `quota-fallback.py` encodes the provider chain so a 429 degrades to the next
  provider instead of hard-failing.

## Why the global AGENTS.md is split

`home/AGENTS.md` is small and its top section is byte-stable so the model
provider can cache the prompt prefix across calls (cheaper, faster). The
reasoning lives in `AGENTS-full.md`, out of the hot path. See
`docs/PROMPT-PATTERNS.md`.

## What is intentionally NOT here

The large application surfaces that lived in the original monorepo (e.g. a web
hub UI and its MCP server) are **not** bundled. The toolkit references such a UI
only by `HUB_BASE_URL` and degrades gracefully when it's absent. This keeps the
toolkit small, installable, and dependency-light.

---
name: codex-doctor
description: Diagnose the Codex toolkit setup in this environment — checks the CLI, global config, env vars, cost-breaker, hooks, and project wiring, then reports what's missing and how to fix it. Use when Codex commands misbehave or after a fresh install.
---

# codex-doctor

A read-only health check for the Codex toolkit. It never changes anything; it
reports findings and concrete next steps.

## What it checks

1. **CLI** — `command -v codex`, version.
2. **Global config** — `~/.codex/` (or `$CODEX_HOME`): `AGENTS.md`,
   `config.toml`, `env.sh`, `session_context.md`, `scripts/cost-breaker.py`.
3. **Env** — `CODEX_HOME`, `CODEX_TOOLKIT_ROOT`, `OPENAI_API_KEY` present?
   (report presence only, never the value).
4. **Cost breaker** — `cost-breaker.py status` runs and shows today's spend.
5. **Project wiring** — does this repo have `AGENTS.md`? a
   `.github/workflows/codex-pr-review.yml`? a `.codex/` dir?
6. **Claude integration (optional)** — hooks registered with ABSOLUTE paths in
   `.claude/settings.json`? (relative hook paths are a known footgun).

## How to run

Run these checks and summarize as a checklist (✅ / ⚠️ / ❌) with a one-line fix
for each non-✅ item:

```bash
echo "== CLI =="; command -v codex && codex --version || echo "MISSING: install codex"
echo "== CODEX_HOME =="; ls -1 "${CODEX_HOME:-$HOME/.codex}" 2>/dev/null || echo "MISSING: run install.sh --home"
echo "== env =="; for v in CODEX_HOME CODEX_TOOLKIT_ROOT OPENAI_API_KEY; do
  if [ -n "${!v:-}" ]; then echo "$v: set"; else echo "$v: UNSET"; fi; done
echo "== cost breaker =="; python3 "${CODEX_HOME:-$HOME/.codex}/scripts/cost-breaker.py" status 2>/dev/null || echo "breaker not installed"
echo "== project =="; [ -f AGENTS.md ] && echo "AGENTS.md ✅" || echo "AGENTS.md ❌ (copy repo-template/AGENTS.md.template)"
[ -f .github/workflows/codex-pr-review.yml ] && echo "PR review workflow ✅" || echo "PR review workflow ⚠️ (optional)"
```

## Reporting

Do NOT print secret values — only whether a variable is set. End with the single
highest-priority fix the user should do next.

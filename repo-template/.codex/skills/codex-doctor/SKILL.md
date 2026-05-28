---
name: codex-doctor
description: Diagnose the Codex toolkit setup in this environment — CLI, global config, env vars, cost-breaker, project wiring, and the most common post-install mistakes (unfilled AGENTS.md placeholders, relative-path hooks). Use when Codex commands misbehave or after a fresh install.
---

# codex-doctor

A read-only health check for the Codex toolkit setup. It never changes
anything; it reports findings (✅ / ⚠️ / ❌) with concrete next steps.

## How to run

Prefer the bundled script — it's deterministic and runs the same way for
everyone:

```bash
codex-doctor                  # if installed via install.sh --scripts
"$CODEX_TOOLKIT_ROOT/scripts/codex-doctor.sh"
```

`--strict` exits non-zero on any warn/fail (useful in CI); `--quiet` suppresses
the green ✅ lines.

## What it checks
1. **Codex CLI** — present on PATH and reports a version.
2. **Environment** — `CODEX_HOME`, `CODEX_TOOLKIT_ROOT`, presence (not value)
   of `OPENAI_API_KEY`.
3. **`~/.codex/` layout** — `AGENTS.md`, `config.toml`, `env.sh`,
   `scripts/cost-breaker.py`, `scripts/quota-fallback.py`, `session_context.md`.
4. **Cost breaker** — runs `cost-breaker.py status`; flags the OFF override.
5. **Project wiring** — `AGENTS.md` exists AND has no unfilled
   `{{PLACEHOLDERS}}` (the #1 post-install mistake), PR-review workflow,
   `.codex/skills/`.
6. **Claude integration** — if `.claude/` exists, warns when hook commands
   look like bare relative paths (a real footgun that can silently disable
   the whole hook system after a `cd`).

## What to do with the output
- ❌ items are real breakage; each has a concrete fix on the same line.
- ⚠️ items are fine but worth knowing — usually missing optional config.
- Run again after each fix; the doctor is fast.

---
name: codex-delegate
description: Delegate a large, mechanical, or highly-parallel coding task to Codex CLI from within Claude Code. Use when a task spans many files, is a repetitive transform (rename/migrate/codemod), or can run autonomously while you do other work. Not for small, surgical edits.
---

# codex-delegate

Hand a well-scoped task to the Codex CLI so it runs autonomously in the project,
while Claude stays free for interactive work.

## When to use
- Repo-wide renames, migrations, codemods, import rewrites, header insertion.
- "Do X for each of these N files" where the items are independent.
- Long mechanical work that would otherwise monopolize the session.

## When NOT to use
- Small, surgical edits (just do them).
- Anything destructive or irreversible without explicit user confirmation.
- Tasks needing tight back-and-forth judgement (keep those interactive).

## How to run

1. Confirm Codex is installed: `command -v codex`. If absent, tell the user to
   install it and stop.
2. Write a crisp, self-contained task description — Codex does not share this
   conversation's context, so include file paths, the exact transform, and the
   definition of done.
3. Run the wrapper (resolves paths/cost-breaker for you):

   ```bash
   "$CODEX_TOOLKIT_ROOT/scripts/codex_fix.sh" "<self-contained task>"
   ```

   If `$CODEX_TOOLKIT_ROOT` is not set, use the path where this toolkit was
   installed (see `claude-integration/README.md`). Do NOT hardcode a per-machine
   path like `C:/Users/<name>/...`; resolve it from the env var or the install
   location.

4. When Codex finishes, review its diff yourself (`git diff`) before reporting
   done. Trust but verify — the agent's summary is intent, the diff is fact.

## Notes
- Respect the cost circuit-breaker; if it trips, stop and tell the user rather
  than setting `CODEX_COST_BREAKER_OFF=1` without their say-so.
- For review (not fix), use `scripts/codex_review.sh`.

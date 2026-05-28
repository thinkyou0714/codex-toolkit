---
description: Delegate the described task to Codex CLI to run autonomously in this repo.
argument-hint: <self-contained task description>
---

Delegate this task to Codex CLI: $ARGUMENTS

Steps:
1. Verify `codex` is on PATH; if not, stop and tell me to install it.
2. Rewrite my request into a single, self-contained task string (Codex has none
   of this conversation's context): include exact file paths, the precise
   transform, and the definition of done.
3. Run it via the toolkit wrapper, resolving the path from the env var (never a
   hardcoded per-machine path):
   `"${CODEX_TOOLKIT_ROOT:?set CODEX_TOOLKIT_ROOT or use install path}/scripts/codex_fix.sh" "<task>"`
4. After it finishes, show me `git diff --stat` and a short summary of what
   changed. Do not declare success until you've inspected the actual diff.
5. If the cost circuit-breaker trips, stop and tell me — do not override it
   without my confirmation.

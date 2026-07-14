---
description: Delegate an implementation task to Codex with the /goal contract (complete brief, watchdog timeout, escalate after 2 failures).
argument-hint: <what to implement>
---

Delegate this implementation to Codex via the /goal contract: $ARGUMENTS

Follow the protocol exactly:

1. If `codex` is not on PATH and this is a cloud session, run
   `"$CODEX_TOOLKIT_ROOT/scripts/codex-cloud-setup.sh"` first.
2. Resolve any specification ambiguity YOURSELF before delegating (ask me only
   if the answer changes the deliverable). Codex must receive decisions, not
   open questions.
3. Build a complete brief and run:
   `"$CODEX_TOOLKIT_ROOT/scripts/codex-goal.sh" --purpose "..." --files "..." --forbid "..." --done "..." --verify "..." "<task>"`
   Every field filled; the task text self-contained (Codex has no conversation
   context).
4. Branch on the exit code:
   - 0: show me `git diff --stat`, read the final-message file, run the repo's
     own checks, then summarize what changed and what you verified.
   - 6 (two attempts failed/timed out): do not retry again — tell me, and
     either implement inline (small, unambiguous) or ask me to choose.
   - 7 (kill switch) / 3 (cost breaker): stop and surface the state; never
     override without my confirmation.
5. Never declare success from Codex's summary alone — the diff and the passing
   checks are the evidence.

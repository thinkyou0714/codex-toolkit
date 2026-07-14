---
name: codex-goal
description: Delegate an implementation task to Codex CLI with the /goal contract (purpose, target files, constraints, definition of done, verify step), a watchdog timeout, and an explicit escalate-after-2-failures rule. Use for any well-scoped implementation work you want Codex to finish autonomously; use codex-delegate for loose "run this task" hand-offs.
---

# codex-goal — goal-contract delegation to Codex

Claude plans and reviews; Codex implements. This skill is the middle step:
hand Codex a **complete brief** and get back either a finished implementation
or an unambiguous "escalate" signal — never a silent hang.

## The division of labor (why this shape)

- **Plan (you, before delegating):** resolve every specification fork yourself.
  Codex must never be the one deciding ambiguous product/design questions.
- **Implement (Codex):** code changes, fixes, tests, and the verification runs.
- **Review (you, after):** the diff is the truth. Codex's summary is intent,
  `git diff` is fact. Never report "done" from the summary alone.

## How to run

1. Preconditions (one-time per session):
   - `command -v codex` — if missing in a cloud session, run
     `"$CODEX_TOOLKIT_ROOT/scripts/codex-cloud-setup.sh"` first.
   - If the cost breaker or kill switch blocks the run, stop and tell the user;
     never override on your own.
2. Write the brief. Fill EVERY field — an unfilled field is a decision you are
   silently delegating:

   ```bash
   "$CODEX_TOOLKIT_ROOT/scripts/codex-goal.sh" \
     --purpose  "why this change exists (1-2 lines)" \
     --files    "exact paths, or 'locate yourself + report'" \
     --forbid   "what must NOT change (public API, unrelated files, deps)" \
     --done     "- condition 1
   - condition 2 (measurable, not 'works')" \
     --verify   "the exact commands to run and what they must show" \
     "what to implement (the transform itself, self-contained)"
   ```

   Codex does not share your conversation: paths, names, and edge cases must
   all be in the brief. For long briefs, write a file and use `-f brief.md`.
3. Interpret the exit code — this is the protocol:
   - `0` — inspect `git diff` + the final-message file it prints, run the
     repo's checks yourself, then report.
   - `6` — **two consecutive attempts failed or timed out (5-min watchdog).**
     Do NOT quietly retry a third time. Either implement inline yourself (if
     the task is small and unambiguous) or ask the user which way to go.
   - `7` — kill switch is ACTIVE: stop, surface the reason.
   - `3` — cost breaker tripped: stop, surface the state, let the user decide.
4. Follow-ups in the same Codex session (fix review findings without re-briefing):

   ```bash
   echo "<follow-up>" | codex exec resume --last
   ```

## Tuning

- Timeout: `--timeout 900` for large migrations (default 300s).
- Cloud/CI: `--profile cloud` (non-interactive approvals; see docs/CLOUD.md).
- Read-only dry analysis first: `--sandbox read-only` + a "report only" brief.

## Related

- OpenAI's official Claude Code plugin (`/plugin marketplace add
  openai/codex-plugin-cc`) offers `/codex:review` and `/codex:rescue`; this
  skill differs by enforcing the /goal contract, the kill-switch/cost gates,
  and the deterministic escalate rule.

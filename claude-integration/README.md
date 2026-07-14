# claude-integration — optional Claude Code drop-in

These files let **Claude Code** cooperate with the Codex CLI toolkit: a skill +
slash command to delegate work to Codex, and two hooks (PSM sync, auto-delegate
nudge). All are optional; the core toolkit works without them.

## What's here

```
claude-integration/
├─ skills/codex-delegate/SKILL.md     # /skill: hand a task to Codex CLI
├─ skills/codex-goal/SKILL.md         # /skill: /goal-contract delegation (timeout + escalate rule)
├─ commands/codex-delegate.md         # /codex-delegate slash command
├─ commands/codex-goal.md             # /codex-goal slash command
├─ hooks/
│  ├─ codex_psm_sync.py               # Stop/SessionEnd: append to ~/.codex PSM
│  └─ codex_auto_delegate.py          # UserPromptSubmit: suggest delegation
└─ scripts/
   └─ assess_plan_delegatability.py   # scoring used by the auto-delegate hook
```

`codex-delegate` is the loose hand-off ("run this task"); `codex-goal` is the
strict one: a complete brief (purpose / files / constraints / definition of
done / verify), a watchdog timeout, and a deterministic escalate-after-2-
failures exit code the orchestrator can branch on. Prefer `codex-goal` for
implementation work. In cloud sessions run `scripts/codex-cloud-setup.sh`
first (see `docs/CLOUD.md`).

## Install

The toolkit's `install.sh --claude` copies these into your project's `.claude/`
(skills → `.claude/skills/`, command → `.claude/commands/`, hooks →
`.claude/hooks/`, scripts → `.claude/scripts/`). It does **not** edit your
`settings.json` for you — registering hooks is a deliberate, reviewable step.

## Registering the hooks (important)

Add to `.claude/settings.json`. **Use absolute paths via `$CLAUDE_PROJECT_DIR`**,
never bare relative paths — a relative hook command breaks the moment the
working directory changes (this is a real failure mode that can disable every
hook at once):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [
        { "type": "command",
          "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/codex_auto_delegate.py\"" }
      ] }
    ],
    "Stop": [
      { "hooks": [
        { "type": "command",
          "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/codex_psm_sync.py\"" }
      ] }
    ]
  }
}
```

The `update-config` skill can apply this for you safely.

## Path resolution

The skill/command resolve the toolkit via `$CODEX_TOOLKIT_ROOT` (exported by
`~/.codex/env.sh` after install, or set it yourself). Never hardcode a
per-machine path such as `C:/Users/<name>/...` — that was a portability bug in
the original and is fixed here.

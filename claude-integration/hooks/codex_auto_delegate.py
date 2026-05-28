#!/usr/bin/env python3
"""codex_auto_delegate.py — Claude Code hook that nudges Claude to delegate large,
mechanical, or highly-parallel tasks to Codex CLI instead of grinding through
them inline.

It is a UserPromptSubmit hook: it inspects the submitted prompt, scores how
"delegatable" the work looks (via assess_plan_delegatability.py), and, when the
score is high, emits a non-blocking suggestion that Claude can act on. It never
blocks the prompt — it only adds context.

Root-cause fix vs. the original:
    The original embedded think-you-lab-specific paths and rules. This version
    delegates the scoring to assess_plan_delegatability.py, whose hard-patterns
    are configurable per-repo via .codex/delegate-rules.json — no hardcoded
    project assumptions.

Register (ABSOLUTE path so a `cd` can't disable it):
    {
      "hooks": {
        "UserPromptSubmit": [
          { "hooks": [
            { "type": "command",
              "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/codex_auto_delegate.py\"" }
          ] }
        ]
      }
    }
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


def read_payload() -> dict:
    raw = sys.stdin.read() if not sys.stdin.isatty() else ""
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def find_assessor() -> Path | None:
    # Prefer one shipped alongside this hook's repo, else PATH.
    here = Path(__file__).resolve().parent
    candidates = [
        here.parent / "scripts" / "assess_plan_delegatability.py",
        Path(os.environ.get("CLAUDE_PROJECT_DIR", ".")) / ".claude" / "scripts" / "assess_plan_delegatability.py",
    ]
    for c in candidates:
        if c.exists():
            return c
    return None


def main() -> int:
    try:
        payload = read_payload()
        prompt = payload.get("prompt") or payload.get("user_prompt") or ""
        if not prompt.strip():
            return 0

        assessor = find_assessor()
        if not assessor:
            return 0

        proc = subprocess.run(
            [sys.executable, str(assessor), "--stdin", "--json"],
            input=prompt,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if proc.returncode != 0 or not proc.stdout.strip():
            return 0
        result = json.loads(proc.stdout)

        if result.get("delegate"):
            reasons = "; ".join(result.get("reasons", [])) or "looks large/parallel/mechanical"
            # UserPromptSubmit: anything on stdout is added to Claude's context.
            print(
                "[codex-auto-delegate] This task looks delegatable to Codex CLI "
                f"(score {result.get('score')}): {reasons}. "
                "Consider running it via the codex-delegate skill / codex_fix.sh "
                "rather than doing it inline."
            )
    except Exception as exc:  # never block the prompt
        print(f"codex_auto_delegate: skipped ({exc})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

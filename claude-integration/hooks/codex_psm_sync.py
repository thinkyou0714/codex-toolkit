#!/usr/bin/env python3
"""codex_psm_sync.py — Claude Code hook that keeps the Persistent Session Memory
(~/.codex/session_context.md) fresh by appending a timestamped note.

Root-cause fix vs. the original:
    The original resolved the PSM via a hardcoded Windows/WSL path
    (//wsl$/Ubuntu/home/rikuto/.codex/session_context.md), which only worked on
    one machine. This version resolves it from CODEX_HOME (default ~/.codex),
    so it is portable across Linux/macOS/WSL.

Designed to run as a Claude Code Stop or SessionEnd hook. Reads the hook JSON
payload from stdin, extracts a short summary if present, and appends it under
the auto-notes marker in the PSM. Failures are non-fatal (hooks must not block
the session on a bookkeeping error).

Register (use ABSOLUTE paths via $CLAUDE_PROJECT_DIR so a `cd` can never break it):
    {
      "hooks": {
        "Stop": [
          { "hooks": [
            { "type": "command",
              "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/codex_psm_sync.py\"" }
          ] }
        ]
      }
    }
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

AUTO_MARKER = "<!-- Auto-appended notes below this line (PSM-sync hook). -->"


def psm_path() -> Path:
    home = os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))
    return Path(home) / "session_context.md"


def read_payload() -> dict:
    raw = sys.stdin.read() if not sys.stdin.isatty() else ""
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def summarize(payload: dict) -> str:
    # Best-effort: pull a human-meaningful line from common hook fields.
    for key in ("summary", "last_message", "reason", "prompt"):
        val = payload.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip().splitlines()[0][:200]
    return "session ended"


def ensure_marker(path: Path) -> str:
    if path.exists():
        text = path.read_text(encoding="utf-8")
    else:
        text = "# Session Context (PSM)\n\n"
    if AUTO_MARKER not in text:
        text = text.rstrip() + "\n\n---\n" + AUTO_MARKER + "\n"
    return text


def prune(text: str, max_notes: int) -> str:
    # Keep everything up to and including the marker, then only the last
    # `max_notes` note lines below it (PSM is working memory, not an archive).
    head, sep, tail = text.partition(AUTO_MARKER)
    if not sep:
        return text
    notes = [ln for ln in tail.splitlines() if ln.strip()]
    kept = notes[-max_notes:] if max_notes > 0 else notes
    return head + AUTO_MARKER + "\n" + "\n".join(kept) + ("\n" if kept else "")


def main() -> int:
    try:
        payload = read_payload()
        path = psm_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        text = ensure_marker(path)
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        note = f"- [{ts}] {summarize(payload)}\n"
        try:
            max_notes = int(os.environ.get("CODEX_PSM_MAX_NOTES", "50"))
        except ValueError:
            max_notes = 50
        text = prune(text.rstrip() + "\n" + note, max_notes)
        path.write_text(text, encoding="utf-8")
    except Exception as exc:  # never block the session
        print(f"codex_psm_sync: skipped ({exc})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

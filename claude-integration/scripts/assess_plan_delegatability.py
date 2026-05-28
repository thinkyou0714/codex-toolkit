#!/usr/bin/env python3
"""assess_plan_delegatability.py — score how well a task/plan suits delegation to
Codex CLI (or any autonomous coding agent) instead of doing it inline.

Heuristic and dependency-free. The signals: breadth (many files/dirs), volume
(large/bulk/all), mechanical nature (rename/migrate/format), and parallelism
(independent subtasks). Each contributes to a score in [0, 100]; >= threshold
means "delegate".

Root-cause fix vs. the original:
    Hard-coded, think-you-lab-specific paths/keywords are gone. Defaults are
    generic, and a repo can override or extend them via .codex/delegate-rules.json:

        {
          "threshold": 55,
          "hard_patterns": ["regenerate fixtures", "bump all versions"],
          "block_patterns": ["delete the database"],
          "weights": {"breadth": 25, "volume": 25, "mechanical": 25, "parallel": 25}
        }

Usage:
    assess_plan_delegatability.py --stdin            # read task from stdin
    assess_plan_delegatability.py "rename foo to bar across the repo"
    assess_plan_delegatability.py --stdin --json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

DEFAULTS = {
    # 50 = "two or more delegation signals" (each signal weighs 25). A single
    # signal stays inline; breadth+mechanical, volume+parallel, etc. delegate.
    "threshold": 50,
    "weights": {"breadth": 25, "volume": 25, "mechanical": 25, "parallel": 25},
    "hard_patterns": [],   # phrases that force delegate=True
    "block_patterns": [],  # phrases that force delegate=False (too risky to auto-delegate)
}

BREADTH = re.compile(r"\b(across|every|all (files|modules|packages|tests)|repo-wide|whole (repo|codebase)|each (file|module))\b", re.I)
VOLUME = re.compile(r"\b(bulk|batch|hundreds|dozens|many|thousands|large(?:-scale)?|massive)\b", re.I)
MECHANICAL = re.compile(r"\b(rename|migrate|reformat|format|codemod|find[- ]and[- ]replace|regenerate|bump|update imports|add (a )?(license|copyright) header)\b", re.I)
PARALLEL = re.compile(r"\b(independent|in parallel|one by one|for each|iterate over|fan[- ]?out)\b", re.I)


def load_rules() -> dict:
    rules = dict(DEFAULTS)
    rules["weights"] = dict(DEFAULTS["weights"])
    project = os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("CODEX_PROJECT_DIR") or "."
    path = Path(project) / ".codex" / "delegate-rules.json"
    if path.exists():
        try:
            user = json.loads(path.read_text(encoding="utf-8"))
            for k, v in user.items():
                if k == "weights" and isinstance(v, dict):
                    rules["weights"].update(v)
                else:
                    rules[k] = v
        except (json.JSONDecodeError, OSError):
            pass
    return rules


def score(text: str, rules: dict) -> tuple[int, list[str], bool, bool]:
    reasons: list[str] = []
    w = rules["weights"]
    total = 0
    forced = False
    blocked = False

    lower = text.lower()
    for pat in rules.get("hard_patterns", []):
        if pat.lower() in lower:
            forced = True
            reasons.append(f"matched hard pattern '{pat}'")
    for pat in rules.get("block_patterns", []):
        if pat.lower() in lower:
            blocked = True
            reasons.append(f"matched block pattern '{pat}'")

    if BREADTH.search(text):
        total += w["breadth"]; reasons.append("repo-wide breadth")
    if VOLUME.search(text):
        total += w["volume"]; reasons.append("high volume")
    if MECHANICAL.search(text):
        total += w["mechanical"]; reasons.append("mechanical/transform")
    if PARALLEL.search(text):
        total += w["parallel"]; reasons.append("parallelizable")

    total = min(total, 100)
    return total, reasons, forced, blocked


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("task", nargs="?", default="")
    ap.add_argument("--stdin", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    text = sys.stdin.read() if args.stdin else args.task
    if not text.strip():
        ap.error("no task text (pass an argument or --stdin)")

    rules = load_rules()
    s, reasons, forced, blocked = score(text, rules)
    delegate = (forced or s >= rules["threshold"]) and not blocked

    if args.json:
        print(json.dumps({
            "score": s,
            "threshold": rules["threshold"],
            "delegate": delegate,
            "forced": forced,
            "blocked": blocked,
            "reasons": reasons,
        }))
    else:
        verdict = "DELEGATE" if delegate else "keep inline"
        print(f"{verdict}  score={s}/{rules['threshold']}")
        for r in reasons:
            print(f"  - {r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

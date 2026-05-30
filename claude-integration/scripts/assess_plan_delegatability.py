#!/usr/bin/env python3
"""assess_plan_delegatability.py — score how well a task/plan suits delegation to
Codex CLI (or any autonomous coding agent) instead of doing it inline.

Heuristic and dependency-free. The signals: breadth (many files/dirs), volume
(large/bulk/all), mechanical nature (rename/migrate/format), and parallelism
(independent subtasks). Each contributes to a score in [0, 100]; >= threshold
means "delegate". Ambiguity/exploration markers ("investigate", "maybe",
"figure out") dampen the score, since vague work wants a human in the loop.

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
# Exploratory/ambiguous work suits a human-in-the-loop, not fire-and-forget
# delegation. Each distinct marker dampens the score (capped), so a task that is
# both broad AND vague no longer auto-delegates on breadth keywords alone.
AMBIGUITY = re.compile(r"\b(maybe|not sure|unsure|investigate|explore|figure out|decide|design|research|prototype|experiment|tbd|somehow)\b", re.I)

# First match in a category is worth its full weight (so two strong signals
# still clear the default threshold); each *additional distinct* keyword in the
# same category adds a small bonus, capped, so volume of evidence matters a
# little without letting one category alone dominate.
_INTRA_BONUS = 5
_INTRA_CAP = 10
_AMBIGUITY_STEP = 10
_AMBIGUITY_CAP = 20


def _distinct_hits(pat: "re.Pattern[str]", text: str) -> int:
    return len({m.group(0).lower() for m in pat.finditer(text)})


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

    for label, pat, key in (
        ("repo-wide breadth", BREADTH, "breadth"),
        ("high volume", VOLUME, "volume"),
        ("mechanical/transform", MECHANICAL, "mechanical"),
        ("parallelizable", PARALLEL, "parallel"),
    ):
        hits = _distinct_hits(pat, text)
        if hits:
            bonus = min(_INTRA_BONUS * (hits - 1), _INTRA_CAP)
            total += w[key] + bonus
            reasons.append(f"{label} (x{hits})" if hits > 1 else label)

    amb = _distinct_hits(AMBIGUITY, text)
    if amb:
        penalty = min(_AMBIGUITY_STEP * amb, _AMBIGUITY_CAP)
        total -= penalty
        reasons.append(f"ambiguity/exploration (-{penalty})")

    total = max(0, min(total, 100))
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

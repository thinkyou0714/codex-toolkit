#!/usr/bin/env python3
"""runner.py — optional batch driver for lab-research.

Reads a list of research questions (one per line, or a JSON array) and emits a
plan the agent can execute one item at a time. It does NOT call any LLM or
network itself — it just normalizes input and tracks which questions still need
a saved note in the vault, so a long research batch is resumable.

Env:
    CODEX_VAULT_DIR   where notes live (to detect already-done items)

Usage:
    runner.py questions.txt
    runner.py --json questions.json
    echo "what is X?" | runner.py -
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path


def slugify(text: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9._-]+", "-", text.strip().lower())
    return re.sub(r"-+", "-", s).strip("-")[:60]


def load_questions(src: str, as_json: bool) -> list[str]:
    raw = sys.stdin.read() if src == "-" else Path(src).read_text(encoding="utf-8")
    if as_json:
        data = json.loads(raw)
        return [str(x).strip() for x in data if str(x).strip()]
    return [line.strip() for line in raw.splitlines() if line.strip() and not line.startswith("#")]


def vault_dir() -> Path | None:
    v = os.environ.get("CODEX_VAULT_DIR")
    return Path(v) if v else None


def already_done(slug: str, vault: Path | None) -> bool:
    if not vault or not vault.exists():
        return False
    return any(p.name.endswith(f"-{slug}.md") for p in vault.glob("*.md"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("source", help="questions file, or - for stdin")
    ap.add_argument("--json", action="store_true", help="source is a JSON array")
    args = ap.parse_args()

    questions = load_questions(args.source, args.json)
    vault = vault_dir()

    pending, done = [], []
    for q in questions:
        slug = slugify(q)
        (done if already_done(slug, vault) else pending).append((slug, q))

    print(f"total: {len(questions)}  pending: {len(pending)}  done: {len(done)}")
    if vault:
        print(f"vault: {vault}")
    else:
        print("vault: (CODEX_VAULT_DIR unset; nothing treated as done)")
    print("\nPending (process one at a time, save each before the next):")
    for slug, q in pending:
        print(f"  - [{slug}] {q}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

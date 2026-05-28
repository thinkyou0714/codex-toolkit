#!/usr/bin/env python3
"""codex_review_ingest.py — parse a Codex review transcript into structured
findings and append them to a JSONL log for trend analysis.

Portable rewrite: the log path is resolved from CODEX_REVIEW_FAILURES_LOG (set by
scripts/lib/paths.sh) with a project-local fallback, instead of a hardcoded
~/.lab/codex path. Works in any repo, Claude or not.

Usage:
    codex_review_ingest.py --input review.txt --status ok --scope main...HEAD
    codex_review_ingest.py --input - --status ok          # read stdin
    codex_review_ingest.py --stats                         # summarize the log
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

SEVERITIES = ("blocker", "high", "medium", "low")
# A finding line typically looks like: "- [HIGH] path/to/file.ts:42 message"
# but we stay liberal so we capture more.
_SEV_RE = re.compile(r"\b(blocker|high|medium|low)\b", re.IGNORECASE)
_LOC_RE = re.compile(r"([\w./\-]+\.[A-Za-z0-9]+):(\d+)")


def log_path() -> Path:
    explicit = os.environ.get("CODEX_REVIEW_FAILURES_LOG")
    if explicit:
        return Path(explicit)
    log_dir = os.environ.get("CODEX_LOG_DIR")
    if log_dir:
        return Path(log_dir) / "review-failures.jsonl"
    # Last-resort fallback: project-local.
    return Path.cwd() / ".codex" / "logs" / "review-failures.jsonl"


def read_input(src: str) -> str:
    if src == "-":
        return sys.stdin.read()
    return Path(src).read_text(encoding="utf-8", errors="replace")


def parse_findings(text: str) -> list[dict]:
    findings: list[dict] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or len(line) < 4:
            continue
        sev_m = _SEV_RE.search(line)
        loc_m = _LOC_RE.search(line)
        # Only treat as a finding if it has a severity tag or a file:line ref
        # and looks like a bullet/enumerated item.
        is_item = line[0] in "-*•" or re.match(r"^\d+[.)]", line)
        if not (sev_m or loc_m) or not is_item:
            continue
        findings.append(
            {
                "severity": (sev_m.group(1).lower() if sev_m else "unknown"),
                "file": (loc_m.group(1) if loc_m else None),
                "line": (int(loc_m.group(2)) if loc_m else None),
                "message": line,
            }
        )
    return findings


def append_record(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")


def show_stats(path: Path) -> int:
    if not path.exists():
        print(f"no log yet at {path}")
        return 0
    sev_counts: Counter[str] = Counter()
    file_counts: Counter[str] = Counter()
    runs = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        runs += 1
        for f in rec.get("findings", []):
            sev_counts[f.get("severity", "unknown")] += 1
            if f.get("file"):
                file_counts[f["file"]] += 1
    print(f"log: {path}")
    print(f"runs: {runs}")
    print("findings by severity:")
    for sev in (*SEVERITIES, "unknown"):
        if sev_counts.get(sev):
            print(f"  {sev:8} {sev_counts[sev]}")
    if file_counts:
        print("hottest files:")
        for f, c in file_counts.most_common(10):
            print(f"  {c:4}  {f}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", help="review transcript file, or - for stdin")
    ap.add_argument("--status", default="ok", choices=["ok", "error"])
    ap.add_argument("--scope", default="")
    ap.add_argument("--stats", action="store_true", help="print summary and exit")
    args = ap.parse_args()

    path = log_path()

    if args.stats:
        return show_stats(path)

    if not args.input:
        ap.error("--input is required unless --stats is given")

    text = read_input(args.input)
    findings = parse_findings(text)
    record = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "status": args.status,
        "scope": args.scope,
        "n_findings": len(findings),
        "findings": findings,
    }
    append_record(path, record)
    print(f"ingested {len(findings)} finding(s) -> {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

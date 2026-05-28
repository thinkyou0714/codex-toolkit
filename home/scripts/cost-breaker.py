#!/usr/bin/env python3
"""cost-breaker.py — a simple cost circuit-breaker for Codex CLI usage.

Reconstructed from the strategy SPEC (cost-control section). It keeps a per-UTC-day
running ledger of estimated spend and refuses new work once a configurable daily
or per-call ceiling is exceeded. The goal is to make runaway agent loops
financially safe by default, while staying trivially overridable.

This is intentionally dependency-free (stdlib only) and side-effect-light: a
`check` does not record spend; only `record` mutates the ledger. Wrapper scripts
call `check` before launching work and (optionally) `record` afterwards with the
measured token usage.

Env (also set by ~/.codex/env.sh):
    CODEX_COST_DAILY_USD     daily ceiling (USD), 0 disables           [5.00]
    CODEX_COST_PER_CALL_USD  per-call ceiling (USD), 0 disables        [1.00]
    CODEX_COST_LEDGER        ledger path                  [~/.codex/cost-ledger.jsonl]
    CODEX_COST_BREAKER_OFF   "1" bypasses all checks                   [0]

Usage:
    cost-breaker.py check [--label review] [--est-usd 0.20]
        exit 0 = proceed, exit 3 = tripped (over ceiling)
    cost-breaker.py record --usd 0.18 [--label review] [--tokens 12000]
    cost-breaker.py status
    cost-breaker.py reset            # clears today's entries
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

TRIP_EXIT = 3


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


def ledger_path() -> Path:
    p = os.environ.get("CODEX_COST_LEDGER")
    if p:
        return Path(p)
    home = os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))
    return Path(home) / "cost-ledger.jsonl"


def breaker_off() -> bool:
    return os.environ.get("CODEX_COST_BREAKER_OFF", "0") == "1"


def today_key() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def read_entries(path: Path) -> list[dict]:
    if not path.exists():
        return []
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def spent_today(path: Path) -> float:
    key = today_key()
    return sum(
        float(e.get("usd", 0.0))
        for e in read_entries(path)
        if e.get("day") == key
    )


def cmd_check(args: argparse.Namespace) -> int:
    if breaker_off():
        return 0
    path = ledger_path()
    daily_cap = _env_float("CODEX_COST_DAILY_USD", 5.00)
    per_call_cap = _env_float("CODEX_COST_PER_CALL_USD", 1.00)
    est = float(args.est_usd or 0.0)

    if per_call_cap > 0 and est > per_call_cap:
        print(
            f"TRIPPED: estimated ${est:.2f} for '{args.label}' exceeds "
            f"per-call cap ${per_call_cap:.2f}",
            file=sys.stderr,
        )
        return TRIP_EXIT

    already = spent_today(path)
    if daily_cap > 0 and (already + est) > daily_cap:
        print(
            f"TRIPPED: today's spend ${already:.2f} + est ${est:.2f} exceeds "
            f"daily cap ${daily_cap:.2f}",
            file=sys.stderr,
        )
        return TRIP_EXIT
    return 0


def cmd_record(args: argparse.Namespace) -> int:
    path = ledger_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "day": today_key(),
        "label": args.label,
        "usd": round(float(args.usd), 6),
        "tokens": args.tokens,
    }
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry) + "\n")
    print(f"recorded ${entry['usd']:.4f} ({args.label})")
    return 0


def cmd_status(_args: argparse.Namespace) -> int:
    path = ledger_path()
    daily_cap = _env_float("CODEX_COST_DAILY_USD", 5.00)
    used = spent_today(path)
    remaining = (daily_cap - used) if daily_cap > 0 else float("inf")
    print(f"ledger:   {path}")
    print(f"day:      {today_key()} (UTC)")
    print(f"spent:    ${used:.4f}")
    print(f"cap:      ${daily_cap:.2f}" if daily_cap > 0 else "cap:      disabled")
    print(f"left:     ${remaining:.4f}" if daily_cap > 0 else "left:     unlimited")
    print(f"breaker:  {'OFF' if breaker_off() else 'on'}")
    return 0


def cmd_reset(_args: argparse.Namespace) -> int:
    path = ledger_path()
    if not path.exists():
        print("nothing to reset")
        return 0
    key = today_key()
    kept = [e for e in read_entries(path) if e.get("day") != key]
    with path.open("w", encoding="utf-8") as fh:
        for e in kept:
            fh.write(json.dumps(e) + "\n")
    print(f"cleared today's ({key}) entries")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_check = sub.add_parser("check")
    p_check.add_argument("--label", default="codex")
    p_check.add_argument("--est-usd", type=float, default=0.0)
    p_check.set_defaults(func=cmd_check)

    p_rec = sub.add_parser("record")
    p_rec.add_argument("--usd", type=float, required=True)
    p_rec.add_argument("--label", default="codex")
    p_rec.add_argument("--tokens", type=int, default=None)
    p_rec.set_defaults(func=cmd_record)

    sub.add_parser("status").set_defaults(func=cmd_status)
    sub.add_parser("reset").set_defaults(func=cmd_reset)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())

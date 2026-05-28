#!/usr/bin/env python3
"""quota-fallback.py — pick the next usable provider from an ordered chain.

Reconstructed from the strategy SPEC (free-stack / quota-resilience section).
When a provider is rate-limited (HTTP 429) or quota-exhausted, agent loops should
degrade to the next provider rather than hard-failing. This helper centralizes
the chain logic so scripts and CI can ask "given these providers are exhausted,
what should I use next?" without duplicating the policy.

It does NOT make network calls or hold credentials — it only reasons about the
configured chain and a set of providers reported as unavailable. Credentials live
in your environment/secret store; this just decides ordering.

Env:
    CODEX_PROVIDER_CHAIN   comma-separated, ordered  [openai,groq,openrouter,ollama]

Usage:
    quota-fallback.py next                       # first provider in chain
    quota-fallback.py next --exhausted openai    # skip exhausted ones
    quota-fallback.py next --exhausted openai,groq
    quota-fallback.py list
"""
from __future__ import annotations

import argparse
import os
import sys

DEFAULT_CHAIN = "openai,groq,openrouter,ollama"


def chain() -> list[str]:
    raw = os.environ.get("CODEX_PROVIDER_CHAIN", DEFAULT_CHAIN)
    return [p.strip() for p in raw.split(",") if p.strip()]


def cmd_next(args: argparse.Namespace) -> int:
    exhausted = {
        p.strip().lower()
        for p in (args.exhausted or "").split(",")
        if p.strip()
    }
    for provider in chain():
        if provider.lower() not in exhausted:
            print(provider)
            return 0
    print("error: all providers in CODEX_PROVIDER_CHAIN are exhausted", file=sys.stderr)
    return 1


def cmd_list(_args: argparse.Namespace) -> int:
    for i, provider in enumerate(chain(), 1):
        print(f"{i}. {provider}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_next = sub.add_parser("next")
    p_next.add_argument("--exhausted", default="", help="comma-separated exhausted providers")
    p_next.set_defaults(func=cmd_next)

    sub.add_parser("list").set_defaults(func=cmd_list)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())

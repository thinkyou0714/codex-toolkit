#!/usr/bin/env python3
"""secret_redact — single-source-of-truth secret redaction for the codex-toolkit.

8-pattern redaction covering the credentials commonly leaked into logs:
Bearer tokens, sk- keys (Anthropic/OpenAI style), xai- keys, api_key / x-api-key /
token assignments, Authorization headers, and basic-auth credentials in URLs.

Usage (module):
    from secret_redact import redact
    safe = redact(text)

Usage (CLI):
    echo "Authorization: Bearer abc123..." | python3 secret_redact.py
    python3 secret_redact.py --selftest    # offline 8/8

Why this exists: scripts (codex-run, kill-switch audit, doctor) need to write logs
without leaking credentials. One library, one pattern set, used everywhere — so
the redaction set can be hardened in one place.
"""
from __future__ import annotations

import re
import sys

# Order matters: more specific patterns first. Each pattern preserves the prefix
# so the log remains readable while the secret is replaced with `***`.
PATTERNS = [
    (re.compile(r"(?i)(authorization\s*:\s*bearer\s+)[A-Za-z0-9._\-]+"), r"\1***"),
    (re.compile(r"(?i)(bearer\s+)[A-Za-z0-9._\-]{16,}"), r"\1***"),
    (re.compile(r"\bsk-[A-Za-z0-9_\-]{16,}\b"), "sk-***"),
    (re.compile(r"\bxai-[A-Za-z0-9_\-]{16,}\b"), "xai-***"),
    (re.compile(r"(?i)(api[_\-]?key\s*[=:]\s*)[\"\047]?[A-Za-z0-9_\-]{16,}[\"\047]?"), r"\1***"),
    (re.compile(r"(?i)(x-api-key\s*[=:]\s*)[\"\047]?[A-Za-z0-9_\-]{16,}[\"\047]?"), r"\1***"),
    (re.compile(r"(?i)(token\s*[=:]\s*)[\"\047]?[A-Za-z0-9_\-\.]{20,}[\"\047]?"), r"\1***"),
    (re.compile(r"://[^@/\s]+:[^@/\s]+@"), "://***:***@"),
]


def redact(text: str) -> str:
    """Redact secrets in `text`. Empty input → empty output (never None)."""
    if not text:
        return ""
    for pattern, replacement in PATTERNS:
        text = pattern.sub(replacement, text)
    return text


def _selftest() -> int:
    cases = [
        ("Authorization: Bearer abcdef0123456789ABCDEF", "Authorization: Bearer ***"),
        ("plain Bearer abcdef0123456789ABCDEF end", "plain Bearer *** end"),
        ("key sk-abcdef0123456789ABCD end", "key sk-*** end"),
        ("tok xai-abcdef0123456789ABCD end", "tok xai-*** end"),
        ("config api_key=abcdef0123456789ABCD here", "config api_key=*** here"),
        ("header x-api-key: abcdef0123456789ABCD", "header x-api-key: ***"),
        ("env token=abcdef0123456789ABCDEFGH end", "env token=*** end"),
        ("url https://user:pass@example.com/x", "url https://***:***@example.com/x"),
    ]
    fails = 0
    for i, (raw, want) in enumerate(cases, 1):
        got = redact(raw)
        ok = got == want
        if not ok:
            fails += 1
            print(f"FAIL[{i}]: input={raw!r}\n   got={got!r}\n  want={want!r}", file=sys.stderr)
    total = len(cases)
    print(f"selftest: {total - fails}/{total} PASS")
    return 0 if fails == 0 else 1


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return _selftest()
    if "-h" in argv or "--help" in argv:
        print(__doc__)
        return 0
    # CLI mode: redact stdin → stdout.
    data = sys.stdin.read()
    sys.stdout.write(redact(data))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

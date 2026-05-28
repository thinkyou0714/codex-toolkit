#!/usr/bin/env bash
# tests/smoke.sh — fast, dependency-light validation of the toolkit.
# Exits non-zero on the first failure. Run from anywhere.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail=0
pass() { echo "  ok   $*"; }
bad()  { echo "  FAIL $*"; fail=1; }

echo "== shell syntax (bash -n) =="
while IFS= read -r -d '' f; do
  if bash -n "$f" 2>/dev/null; then pass "$f"; else bad "$f"; fi
done < <(find . -name '*.sh' -not -path './.git/*' -print0)

echo "== python compiles (py_compile) =="
if command -v python3 >/dev/null 2>&1; then
  while IFS= read -r -d '' f; do
    if python3 -m py_compile "$f" 2>/dev/null; then pass "$f"; else bad "$f"; fi
  done < <(find . -name '*.py' -not -path './.git/*' -print0)
else
  echo "  skip (no python3)"
fi

echo "== lib/paths.sh resolves =="
( set -euo pipefail
  source scripts/lib/paths.sh
  [ -n "$CODEX_HOME" ] && [ -n "$CODEX_TOOLKIT_ROOT" ] && [ -n "$CODEX_LOG_DIR" ]
) && pass "paths.sh exports CODEX_HOME/TOOLKIT_ROOT/LOG_DIR" || bad "paths.sh resolution"

echo "== cost-breaker logic =="
if command -v python3 >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  export CODEX_COST_LEDGER="$tmp/ledger.jsonl" CODEX_COST_DAILY_USD=1.00 CODEX_COST_PER_CALL_USD=0.50
  cb="home/scripts/cost-breaker.py"
  python3 "$cb" check --label t --est-usd 0.10 >/dev/null 2>&1 && pass "check under cap proceeds" || bad "check under cap"
  python3 "$cb" check --label t --est-usd 0.99 >/dev/null 2>&1 && bad "per-call cap not enforced" || pass "per-call cap enforced"
  python3 "$cb" record --usd 0.95 --label t >/dev/null 2>&1 && pass "record writes" || bad "record"
  python3 "$cb" check --label t --est-usd 0.10 >/dev/null 2>&1 && bad "daily cap not enforced" || pass "daily cap enforced after record"
  CODEX_COST_BREAKER_OFF=1 python3 "$cb" check --label t --est-usd 99 >/dev/null 2>&1 && pass "breaker-off bypass works" || bad "breaker-off bypass"
  rm -rf "$tmp"
else
  echo "  skip (no python3)"
fi

echo "== quota-fallback chain =="
if command -v python3 >/dev/null 2>&1; then
  out="$(CODEX_PROVIDER_CHAIN="a,b,c" python3 home/scripts/quota-fallback.py next --exhausted a 2>/dev/null)"
  [ "$out" = "b" ] && pass "skips exhausted provider" || bad "quota-fallback (got '$out')"
fi

echo "== delegate scorer =="
if command -v python3 >/dev/null 2>&1; then
  out="$(echo "rename foo to bar across every file in the repo" | python3 claude-integration/scripts/assess_plan_delegatability.py --stdin --json 2>/dev/null)"
  echo "$out" | grep -q '"delegate": true' && pass "scores repo-wide rename as delegate" || bad "delegate scorer (got '$out')"
fi

echo "== install.sh --all --dry-run =="
if bash install.sh --all --dry-run >/dev/null 2>&1; then pass "dry-run install"; else bad "dry-run install"; fi

echo
if [ "$fail" = 0 ]; then echo "✅ smoke PASS"; else echo "❌ smoke FAIL"; fi
exit "$fail"

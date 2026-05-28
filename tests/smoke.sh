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

echo "== PSM prune cap =="
if command -v python3 >/dev/null 2>&1; then
  out="$(python3 -c "import importlib.util as u; s=u.spec_from_file_location('m','claude-integration/hooks/codex_psm_sync.py'); m=u.module_from_spec(s); s.loader.exec_module(m); t=m.AUTO_MARKER+chr(10)+chr(10).join('- n%d'%i for i in range(10)); print(m.prune(t,3).count('- n'))" 2>/dev/null)"
  [ "$out" = "3" ] && pass "PSM prune keeps last N notes" || bad "PSM prune (got '$out')"
fi

echo "== install.sh --all --dry-run =="
if bash install.sh --all --dry-run >/dev/null 2>&1; then pass "dry-run install"; else bad "dry-run install"; fi

echo "== installed wrapper resolves its lib (symlink) =="
tmp="$(mktemp -d)"
CODEX_HOME="$tmp/.codex" CODEX_BIN_DIR="$tmp/bin" bash install.sh --home --scripts >/dev/null 2>&1
out="$(cd "$tmp" && CODEX_HOME="$tmp/.codex" "$tmp/bin/codex_review" 2>&1 || true)"
echo "$out" | grep -q "paths.sh" && bad "installed wrapper can't find lib (got: $out)" || pass "installed wrapper resolves lib"
rm -rf "$tmp"

echo "== install/uninstall round-trip (home) =="
tmp="$(mktemp -d)"
CODEX_HOME="$tmp/.codex" bash install.sh --home >/dev/null 2>&1
{ [ -f "$tmp/.codex/AGENTS.md" ] && [ -f "$tmp/.codex/config.toml" ]; } && pass "home install creates files" || bad "home install"
echo "# keep me" >> "$tmp/.codex/config.toml"
CODEX_HOME="$tmp/.codex" bash uninstall.sh --home >/dev/null 2>&1
[ ! -f "$tmp/.codex/AGENTS.md" ] && pass "uninstall removes toolkit files" || bad "uninstall left toolkit files"
grep -q "keep me" "$tmp/.codex/config.toml" 2>/dev/null && pass "uninstall preserves user config.toml" || bad "uninstall ate config.toml"
rm -rf "$tmp"

echo
if [ "$fail" = 0 ]; then echo "✅ smoke PASS"; else echo "❌ smoke FAIL"; fi
exit "$fail"

#!/usr/bin/env bash
# tests/test_safety.sh — exercises the v0.2.0 minimal safety primitives:
#   - home/lib/secret_redact.py  (8-pattern redaction lib)
#   - home/lib/SecretRedact.psm1 (PowerShell mirror; presence + syntax only — pwsh may not be installed)
#   - home/scripts/kill-switch.sh (activate / check / deactivate round-trip + audit log)
#   - scripts/codex-run.sh (offline --selftest)
#
# Sourced from tests/smoke.sh after the generic checks. Exits non-zero on any failure.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

fail=0
pass() { echo "  ok   $*"; }
bad()  { echo "  FAIL $*"; fail=1; }

echo "== secret_redact.py --selftest =="
if python3 home/lib/secret_redact.py --selftest >/tmp/codex-toolkit-redact.$$.txt 2>&1; then
  grep -q "^selftest: 8/8 PASS$" /tmp/codex-toolkit-redact.$$.txt \
    && pass "secret_redact 8/8" \
    || bad "secret_redact ran but did not report 8/8: $(tail -1 /tmp/codex-toolkit-redact.$$.txt)"
else
  bad "secret_redact selftest exited non-zero"
fi
rm -f /tmp/codex-toolkit-redact.$$.txt

echo "== SecretRedact.psm1 present + parses (skip if pwsh missing) =="
if [ -f home/lib/SecretRedact.psm1 ]; then
  if command -v pwsh >/dev/null 2>&1; then
    if pwsh -NoProfile -Command "Import-Module ./home/lib/SecretRedact.psm1 -Force; Invoke-Selftest" 2>/dev/null | grep -q "^selftest: 8/8 PASS$"; then
      pass "SecretRedact.psm1 8/8"
    else
      bad "SecretRedact.psm1 import/selftest failed"
    fi
  else
    pass "SecretRedact.psm1 present (pwsh not installed — skipping import test)"
  fi
else
  bad "home/lib/SecretRedact.psm1 missing"
fi

echo "== kill-switch round-trip =="
# Use a throwaway CODEX_HOME so we never touch the user's real state.
export CODEX_HOME="${TMPDIR:-/tmp}/codex-toolkit-test-$$"
export CODEX_LOG_DIR="$CODEX_HOME/logs"
mkdir -p "$CODEX_HOME" "$CODEX_LOG_DIR"

ks="home/scripts/kill-switch.sh"
bash "$ks" check >/dev/null 2>&1 && pass "check exit 0 when CLEAR" || bad "check should exit 0 when CLEAR"

bash "$ks" activate "smoke test reason" >/dev/null 2>&1
if bash "$ks" check >/dev/null 2>&1; then
  bad "check exit 1 expected when ACTIVE, got 0"
else
  pass "check exit 1 when ACTIVE"
fi

# Confirm the flag file + audit log entry exist.
[ -f "$CODEX_HOME/state/kill-switch.flag" ] && pass "flag file written" || bad "flag file missing"
grep -q '"event":"kill_switch","category":"activated"' "$CODEX_LOG_DIR/failures.jsonl" \
  && pass "activate audit log entry" \
  || bad "activate audit log entry missing"

bash "$ks" deactivate >/dev/null 2>&1
[ ! -f "$CODEX_HOME/state/kill-switch.flag" ] && pass "flag file removed" || bad "flag file should be gone"
grep -q '"event":"kill_switch","category":"deactivated"' "$CODEX_LOG_DIR/failures.jsonl" \
  && pass "deactivate audit log entry" \
  || bad "deactivate audit log entry missing"

# Clean throwaway state.
rm -rf "$CODEX_HOME"

echo "== codex-run.sh --selftest =="
if scripts/codex-run.sh --selftest 2>/tmp/codex-toolkit-run.$$.txt | grep -q "^selftest: 3/3 PASS$"; then
  pass "codex-run 3/3"
else
  bad "codex-run selftest failed: $(cat /tmp/codex-toolkit-run.$$.txt | head -3)"
fi
rm -f /tmp/codex-toolkit-run.$$.txt

[ $fail -eq 0 ] || exit 1

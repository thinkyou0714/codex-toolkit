#!/usr/bin/env bash
# tests/test_cloud.sh — exercises the v0.3.0 cloud + goal-delegation layer:
#   - scripts/codex-cloud-setup.sh (dry-run purity, auth wiring, profile seed)
#   - scripts/codex-goal.sh        (/goal brief rendering, watchdog timeout,
#                                   escalate exit 6, kill-switch exit 7)
#   - install.sh/uninstall.sh      (new home files round-trip)
#
# Sourced from tests/smoke.sh after the safety suite. All state is confined to
# throwaway CODEX_HOME/CODEX_LOG_DIR dirs; a stub `codex` on PATH replaces the
# real CLI. Exits non-zero on any failure.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

fail=0
pass() { echo "  ok   $*"; }
bad()  { echo "  FAIL $*"; fail=1; }

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP/bin"
# Stub codex: --version prints, `login status` reports not-logged-in,
# `login --with-api-key` records the stdin it received, `exec ...` captures the
# brief piped on stdin. Paths are baked in at write time.
cat > "$TMP/bin/codex" <<STUB
#!/usr/bin/env bash
case "\$1" in
  --version) echo "codex-cli 0.0.0-stub" ;;
  login)
    case "\${2:-}" in
      status) exit 1 ;;
      --with-api-key) cat > "$TMP/login-key.txt" ;;
    esac ;;
  exec)
    printf '%s\n' "\$*" > "$TMP/exec-args.txt"
    cat > "$TMP/brief.txt"
    echo "MOCK_CODEX_DONE" ;;
  *) cat >/dev/null ;;
esac
STUB
chmod +x "$TMP/bin/codex"
export PATH="$TMP/bin:$PATH"

echo "== codex-cloud-setup --dry-run touches nothing =="
out="$(CODEX_HOME="$TMP/home-dry" CODEX_BIN_DIR="$TMP/bin-dry" OPENAI_API_KEY=dummy-key \
      bash scripts/codex-cloud-setup.sh --dry-run --no-egress 2>&1)" && rc=0 || rc=$?
[ "${rc:-1}" = 0 ] && pass "dry-run exits 0" || bad "dry-run exited $rc (out: $out)"
{ [ ! -e "$TMP/home-dry" ] && [ ! -e "$TMP/bin-dry" ]; } \
  && pass "dry-run created no files" || bad "dry-run wrote to disk"
echo "$out" | grep -q "codex login --with-api-key" \
  && pass "dry-run plans API-key login" || bad "dry-run missing auth plan (out: $out)"

echo "== codex-cloud-setup wires auth + profile for real =="
out="$(CODEX_HOME="$TMP/home-real" CODEX_BIN_DIR="$TMP/bin-real" \
      CODEX_AUTH_JSON='{"stub":true}' \
      bash scripts/codex-cloud-setup.sh --no-egress --quiet 2>&1)" && rc=0 || rc=$?
[ "${rc:-1}" = 0 ] && pass "setup exits 0" || bad "setup exited $rc (out: $out)"
[ -f "$TMP/home-real/auth.json" ] && grep -q '"stub":true' "$TMP/home-real/auth.json" \
  && pass "auth.json written from CODEX_AUTH_JSON" || bad "auth.json missing/wrong"
perms="$(ls -l "$TMP/home-real/auth.json" 2>/dev/null | cut -c1-10)"
[ "$perms" = "-rw-------" ] && pass "auth.json is 0600" || bad "auth.json perms: $perms"
[ -f "$TMP/home-real/cloud.config.toml" ] && pass "cloud profile seeded" || bad "cloud profile missing"
[ -f "$TMP/home-real/templates/goal.md" ] && pass "goal template installed" || bad "goal template missing"
[ -L "$TMP/bin-real/codex-goal" ] && [ -L "$TMP/bin-real/codex-cloud-setup" ] \
  && pass "new wrappers symlinked" || bad "new wrapper symlinks missing"

echo "== codex-cloud-setup logs in with OPENAI_API_KEY =="
OPENAI_API_KEY="dummy-key-value" CODEX_HOME="$TMP/home-key" CODEX_BIN_DIR="$TMP/bin-key" \
  bash scripts/codex-cloud-setup.sh --no-egress --quiet >/dev/null 2>&1
grep -q "dummy-key-value" "$TMP/login-key.txt" 2>/dev/null \
  && pass "API key piped to codex login --with-api-key" || bad "login stub never saw the key"

echo "== codex-goal renders the /goal brief and delegates =="
out="$(CODEX_HOME="$TMP/goal-home" CODEX_LOG_DIR="$TMP/goal-logs" \
      bash scripts/codex-goal.sh --files "src/a.py" --done "- tests green" "rename foo to bar" 2>&1)" && rc=0 || rc=$?
[ "${rc:-1}" = 0 ] && pass "goal run exits 0" || bad "goal run exited $rc (out: $out)"
grep -q "^/goal" "$TMP/brief.txt" 2>/dev/null && pass "brief starts with /goal" || bad "brief missing /goal header"
grep -q "rename foo to bar" "$TMP/brief.txt" 2>/dev/null && pass "brief carries the task" || bad "task text missing from brief"
grep -q "完了条件" "$TMP/brief.txt" 2>/dev/null && pass "brief has definition-of-done section" || bad "DoD section missing"
grep -q "tests green" "$TMP/brief.txt" 2>/dev/null && pass "custom --done value rendered" || bad "--done value missing"
grep -qE '^exec .*-o .*goal-last-message' "$TMP/exec-args.txt" 2>/dev/null \
  && pass "exec invoked with -o last-message capture" || bad "exec args wrong: $(cat "$TMP/exec-args.txt" 2>/dev/null)"

echo "== codex-goal watchdog: timeout -> retry -> exit 6 =="
cat > "$TMP/bin/codex" <<'SLOWSTUB'
#!/usr/bin/env bash
sleep 30
SLOWSTUB
out="$(CODEX_HOME="$TMP/goal-home" CODEX_LOG_DIR="$TMP/goal-logs" \
      bash scripts/codex-goal.sh --timeout 1 --retries 1 "task" 2>&1)" && rc=0 || rc=$?
[ "${rc:-0}" = 6 ] && pass "escalates with exit 6 after all attempts" || bad "expected exit 6, got $rc"
echo "$out" | grep -q "attempt 2/2" && pass "retried before escalating" || bad "no retry attempt seen (out: $out)"
# A watchdog-killed run can't self-log via codex-run; codex-goal must record it.
grep -q '"category":"goal_timeout"' "$TMP/goal-logs/failures.jsonl" 2>/dev/null \
  && pass "timeout recorded to failures.jsonl" || bad "no goal_timeout entry in failures.jsonl"
grep -q '"category":"goal_escalate"' "$TMP/goal-logs/failures.jsonl" 2>/dev/null \
  && pass "escalation recorded to failures.jsonl" || bad "no goal_escalate entry in failures.jsonl"

echo "== codex-goal honors the kill switch (exit 7, no retry) =="
CODEX_HOME="$TMP/goal-home" CODEX_LOG_DIR="$TMP/goal-logs" \
  bash home/scripts/kill-switch.sh activate "cloud test" >/dev/null 2>&1
out="$(CODEX_HOME="$TMP/goal-home" CODEX_LOG_DIR="$TMP/goal-logs" \
      bash scripts/codex-goal.sh --timeout 5 "task" 2>&1)" && rc=0 || rc=$?
[ "${rc:-0}" = 7 ] && pass "blocked with exit 7 while ACTIVE" || bad "expected exit 7, got $rc (out: $out)"
CODEX_HOME="$TMP/goal-home" CODEX_LOG_DIR="$TMP/goal-logs" \
  bash home/scripts/kill-switch.sh deactivate >/dev/null 2>&1

echo "== uninstall keeps cloud.config.toml, removes goal template =="
CODEX_HOME="$TMP/home-real" CODEX_BIN_DIR="$TMP/bin-real" bash uninstall.sh --home --scripts >/dev/null 2>&1
[ -f "$TMP/home-real/cloud.config.toml" ] && pass "cloud.config.toml preserved (user data)" || bad "uninstall ate cloud.config.toml"
[ ! -f "$TMP/home-real/templates/goal.md" ] && pass "goal template removed" || bad "goal template left behind"
[ ! -e "$TMP/bin-real/codex-goal" ] && [ ! -e "$TMP/bin-real/codex-cloud-setup" ] \
  && pass "new wrappers unlinked" || bad "wrapper symlinks left behind"

[ $fail -eq 0 ] || exit 1

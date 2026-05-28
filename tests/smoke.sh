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
# Regression guard: CODEX_TOOLKIT_ROOT must point at the repo root (contains
# install.sh), not the scripts/ subdir. This caught a real bug in pass 5.
out="$(unset CODEX_TOOLKIT_ROOT; bash -c 'source scripts/lib/paths.sh; echo "$CODEX_TOOLKIT_ROOT"')"
[ -f "$out/install.sh" ] && pass "CODEX_TOOLKIT_ROOT points at repo root ($out)" || bad "CODEX_TOOLKIT_ROOT wrong: $out (no install.sh there)"

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

echo "== delegate scorer dampens ambiguous work =="
if command -v python3 >/dev/null 2>&1; then
  out="$(echo "maybe investigate and figure out how to rename across the repo" | python3 claude-integration/scripts/assess_plan_delegatability.py --stdin --json 2>/dev/null)"
  echo "$out" | grep -q '"delegate": false' && pass "ambiguity markers keep a broad task inline" || bad "ambiguity dampener (got '$out')"
fi

echo "== review ingest scores severity from tags only =="
if command -v python3 >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  log="$tmp/r.jsonl"
  printf -- '- [HIGH] foo.py:42 boom\n- bar.py:10 mentions a low-level cache\n- not a finding\n' \
    | CODEX_REVIEW_FAILURES_LOG="$log" python3 scripts/codex_review_ingest.py --input - >/dev/null 2>&1
  sev="$(python3 -c "import json; r=json.loads(open('$log').read().splitlines()[0]); print(','.join(f['severity'] for f in r['findings']))" 2>/dev/null)"
  [ "$sev" = "high,unknown" ] && pass "tagged=high, untagged file:line=unknown (no stray 'low')" || bad "ingest severity (got '$sev')"
  rm -rf "$tmp"
fi

echo "== VERSION is in sync with CHANGELOG =="
ver="$(tr -d '[:space:]' < VERSION)"
grep -q "## \[$ver\]" CHANGELOG.md && pass "CHANGELOG has a [$ver] section" || bad "no '## [$ver]' heading in CHANGELOG.md"

echo "== install.sh argument handling =="
bash install.sh >/dev/null 2>&1 && bad "no-arg install should exit non-zero" || pass "no-arg install exits non-zero"
bash install.sh --bogus >/dev/null 2>&1 && bad "unknown arg should exit non-zero" || pass "unknown arg exits non-zero"

echo "== install.sh --all --dry-run =="
if bash install.sh --all --dry-run >/dev/null 2>&1; then pass "dry-run install"; else bad "dry-run install"; fi

echo "== dry-run changes nothing on disk =="
tmp="$(mktemp -d)"
CODEX_HOME="$tmp/.codex" CODEX_BIN_DIR="$tmp/bin" bash install.sh --home --scripts --dry-run >/dev/null 2>&1
{ [ ! -e "$tmp/.codex" ] && [ ! -e "$tmp/bin" ]; } && pass "dry-run created no files" || bad "dry-run wrote to disk"
rm -rf "$tmp"

echo "== installed wrapper resolves its lib (symlink) =="
tmp="$(mktemp -d)"
CODEX_HOME="$tmp/.codex" CODEX_BIN_DIR="$tmp/bin" bash install.sh --home --scripts >/dev/null 2>&1
out="$(cd "$tmp" && CODEX_HOME="$tmp/.codex" "$tmp/bin/codex_review" 2>&1 || true)"
echo "$out" | grep -q "paths.sh" && bad "installed wrapper can't find lib (got: $out)" || pass "installed wrapper resolves lib"
rm -rf "$tmp"

echo "== codex_fix.sh hang workaround (openai/codex#20919) =="
grep -q '</dev/null' scripts/codex_fix.sh && pass "codex_fix.sh closes stdin via </dev/null" || bad "missing </dev/null in codex_fix.sh"

echo "== codex_review.sh uses stdin form (-) =="
grep -E -q '"\$CODEX_BIN"\s+exec\s+--model\s+"\$MODEL"\s+-' scripts/codex_review.sh && pass "codex_review.sh pipes prompt via stdin -" || bad "codex_review.sh not using stdin -"

echo "== end-to-end (mock codex) =="
if command -v git >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  # Stub codex on PATH: drains stdin and exits 0 with a marker.
  cat > "$tmp/codex" <<'STUB'
#!/usr/bin/env bash
echo "MOCK_CODEX_OK"
cat >/dev/null
STUB
  chmod +x "$tmp/codex"
  # Tiny git repo with a diff for codex_review.sh to consume. Disable signing
  # in case the host enforces it (the test must work without a signing setup).
  ( cd "$tmp" && git init -q && git config user.email t@t && git config user.name t \
    && git config commit.gpgsign false \
    && echo a > f && git add f && git commit -qm init \
    && echo b > f ) >/dev/null 2>&1
  # Isolated CODEX_HOME with the real cost-breaker copied in.
  mkdir -p "$tmp/.codex/scripts"
  cp home/scripts/cost-breaker.py "$tmp/.codex/scripts/cost-breaker.py"
  out="$(cd "$tmp" && PATH="$tmp:$PATH" CODEX_HOME="$tmp/.codex" \
        CODEX_COST_LEDGER="$tmp/.codex/ledger.jsonl" CODEX_REVIEW_EST_USD=0.05 \
        "$ROOT/scripts/codex_review.sh" 2>&1)"
  echo "$out" | grep -q MOCK_CODEX_OK && pass "wrapper invokes codex with diff piped" || bad "wrapper did not call codex (out: $out)"
  [ -s "$tmp/.codex/ledger.jsonl" ] && pass "cost-breaker recorded spend after run" || bad "ledger empty after successful run"
  rm -rf "$tmp"
fi

echo "== install/uninstall round-trip (home) =="
tmp="$(mktemp -d)"
CODEX_HOME="$tmp/.codex" bash install.sh --home >/dev/null 2>&1
{ [ -f "$tmp/.codex/AGENTS.md" ] && [ -f "$tmp/.codex/config.toml" ]; } && pass "home install creates files" || bad "home install"
echo "# keep me" >> "$tmp/.codex/config.toml"
CODEX_HOME="$tmp/.codex" bash uninstall.sh --home >/dev/null 2>&1
[ ! -f "$tmp/.codex/AGENTS.md" ] && pass "uninstall removes toolkit files" || bad "uninstall left toolkit files"
grep -q "keep me" "$tmp/.codex/config.toml" 2>/dev/null && pass "uninstall preserves user config.toml" || bad "uninstall ate config.toml"
rm -rf "$tmp"

echo "== install/uninstall round-trip (repo) =="
if command -v git >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  ( cd "$tmp" && git init -q && git config user.email t@t && git config user.name t \
    && git config commit.gpgsign false ) >/dev/null 2>&1
  ( cd "$tmp" && bash "$ROOT/install.sh" --repo ) >/dev/null 2>&1
  { [ -f "$tmp/AGENTS.md" ] && [ -f "$tmp/.github/workflows/codex-pr-review.yml" ] && [ -d "$tmp/.codex/skills/codex-doctor" ]; } \
    && pass "repo install creates expected files" || bad "repo install"
  echo "# user edit" >> "$tmp/AGENTS.md"
  ( cd "$tmp" && bash "$ROOT/uninstall.sh" --repo ) >/dev/null 2>&1
  [ ! -f "$tmp/.github/workflows/codex-pr-review.yml" ] && pass "repo uninstall removes workflow" || bad "repo uninstall left workflow"
  [ ! -d "$tmp/.codex/skills/codex-doctor" ] && pass "repo uninstall removes skills dir" || bad "skills dir not removed"
  grep -q "# user edit" "$tmp/AGENTS.md" 2>/dev/null && pass "repo uninstall preserves user-edited AGENTS.md" || bad "uninstall ate AGENTS.md"
  rm -rf "$tmp"
fi

echo "== codex-doctor --strict on a fully-wired setup =="
if command -v git >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  # Stub codex on PATH so the CLI check passes; --version prints, anything else
  # just drains stdin.
  mkdir -p "$tmp/bin"
  cat > "$tmp/bin/codex" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in --version) echo "codex 0.0.0-stub" ;; *) cat >/dev/null ;; esac
STUB
  chmod +x "$tmp/bin/codex"
  # Real global config + a scaffolded project with placeholders filled in.
  CODEX_HOME="$tmp/.codex" CODEX_BIN_DIR="$tmp/bin" bash install.sh --home --scripts >/dev/null 2>&1
  proj="$tmp/proj"; mkdir -p "$proj"
  ( cd "$proj" && git init -q && git config user.email t@t && git config user.name t \
    && git config commit.gpgsign false ) >/dev/null 2>&1
  ( cd "$proj" && bash "$ROOT/install.sh" --repo ) >/dev/null 2>&1
  # Fill every {{PLACEHOLDER}} so the doctor's placeholder check is clean.
  filled="$(mktemp)"
  sed 's/{{[A-Z0-9_]*}}/filled/g' "$proj/AGENTS.md" > "$filled" && mv "$filled" "$proj/AGENTS.md"
  out="$(CODEX_HOME="$tmp/.codex" CODEX_TOOLKIT_ROOT="$ROOT" CODEX_PROJECT_DIR="$proj" \
        OPENAI_API_KEY=x PATH="$tmp/bin:$PATH" \
        bash "$ROOT/scripts/codex-doctor.sh" --strict 2>&1)" && rc=0 || rc=$?
  [ "${rc:-1}" = 0 ] && pass "codex-doctor --strict passes when everything is wired" \
    || bad "codex-doctor --strict exited $rc (out: $out)"
  rm -rf "$tmp"
fi

echo "== safety primitives (v0.2.0: secret_redact + kill-switch + codex-run) =="
if bash "$ROOT/tests/test_safety.sh"; then
  pass "safety primitives suite"
else
  bad "safety primitives suite"
fi

echo
if [ "$fail" = 0 ]; then echo "✅ smoke PASS"; else echo "❌ smoke FAIL"; fi
exit "$fail"

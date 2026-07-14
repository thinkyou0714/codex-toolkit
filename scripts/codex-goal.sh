#!/usr/bin/env bash
# codex-goal.sh — goal-driven delegation to Codex: render a /goal brief, run
# `codex exec` non-interactively with a watchdog timeout, retry once, and give
# the orchestrator (Claude Code, CI, you) a machine-readable outcome.
#
# The /goal contract (home/templates/goal.md) forces every delegation to carry
# purpose, target files, constraints, a definition of done, and a verify step —
# so Codex finishes the implementation instead of "investigating".
#
# Usage:
#   codex-goal.sh [options] "<what to implement>"
#   codex-goal.sh [options] -f brief.md      # pre-written brief; sent as-is
#
# Options:
#   --purpose T   --files T   --forbid T   --done T   --verify T   (template fields)
#   --model M     (default $CODEX_GOAL_MODEL, then $CODEX_FIX_MODEL)
#   --profile P   (codex -p P, e.g. "cloud"; default $CODEX_GOAL_PROFILE)
#   --sandbox S   (read-only|workspace-write|danger-full-access)
#   --timeout S   (default $CODEX_GOAL_TIMEOUT_S = 300 — the "5 min, no reply,
#                  assume it's stuck" rule)
#   --retries N   (default $CODEX_GOAL_RETRIES = 1 -> two attempts total)
#   --json        (pass --json through to codex exec: JSONL events on stdout)
#   -o FILE       (write Codex's final message here;
#                  default $CODEX_LOG_DIR/goal-last-message.txt)
#   --dry-run     (print the rendered brief + command, run nothing)
#
# Exit codes (stable — orchestrators branch on these):
#   0  success                      3  cost circuit-breaker tripped
#   2  usage error                  6  ESCALATE: every attempt failed/timed out —
#   7  kill-switch ACTIVE              implement inline or ask the user
set -uo pipefail

# --- locate lib/paths.sh (same 3-way fallback as the sibling wrappers) --------
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/paths.sh" ]; then _lib="$SCRIPT_DIR/lib/paths.sh"
elif [ -n "${CODEX_TOOLKIT_ROOT:-}" ] && [ -f "$CODEX_TOOLKIT_ROOT/scripts/lib/paths.sh" ]; then _lib="$CODEX_TOOLKIT_ROOT/scripts/lib/paths.sh"
elif [ -f "$HOME/.codex/toolkit-root" ] && [ -f "$(cat "$HOME/.codex/toolkit-root")/scripts/lib/paths.sh" ]; then _lib="$(cat "$HOME/.codex/toolkit-root")/scripts/lib/paths.sh"
else echo "error: cannot locate scripts/lib/paths.sh (set CODEX_TOOLKIT_ROOT)" >&2; exit 1; fi
# shellcheck source=lib/paths.sh
source "$_lib"

# codex-run.sh is the single kill-switch + redaction + failure-log gate
# (AGENTS.md rule 7: wrap it, don't re-implement it).
RUNNER=""
for cand in "$SCRIPT_DIR/codex-run.sh" "$CODEX_TOOLKIT_ROOT/scripts/codex-run.sh"; do
  [ -f "$cand" ] && { RUNNER="$cand"; break; }
done
[ -n "$RUNNER" ] || codex_die "cannot locate codex-run.sh next to $SCRIPT_DIR"

# --- defaults ------------------------------------------------------------------
MODEL="${CODEX_GOAL_MODEL:-${CODEX_FIX_MODEL:-gpt-5-codex}}"
PROFILE="${CODEX_GOAL_PROFILE:-}"
SANDBOX=""
TIMEOUT_S="${CODEX_GOAL_TIMEOUT_S:-300}"
RETRIES="${CODEX_GOAL_RETRIES:-1}"
EST="${CODEX_GOAL_EST_USD:-0.60}"
JSON=0 DRY_RUN=0
TASK="" BRIEF_FILE=""
PURPOSE="" FILES="" FORBID="" DONE_COND="" VERIFY=""
LAST_MSG=""

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --purpose) PURPOSE="${2:?}"; shift 2 ;;
    --files)   FILES="${2:?}"; shift 2 ;;
    --forbid)  FORBID="${2:?}"; shift 2 ;;
    --done)    DONE_COND="${2:?}"; shift 2 ;;
    --verify)  VERIFY="${2:?}"; shift 2 ;;
    --model)   MODEL="${2:?}"; shift 2 ;;
    --profile) PROFILE="${2:?}"; shift 2 ;;
    --sandbox) SANDBOX="${2:?}"; shift 2 ;;
    --timeout) TIMEOUT_S="${2:?}"; shift 2 ;;
    --retries) RETRIES="${2:?}"; shift 2 ;;
    --json)    JSON=1; shift ;;
    -o)        LAST_MSG="${2:?}"; shift 2 ;;
    -f)        BRIEF_FILE="${2:?}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage 0 ;;
    --*) echo "unknown option: $1" >&2; usage 2 ;;
    *)  TASK="$1"; shift ;;
  esac
done

if [ -n "$BRIEF_FILE" ]; then
  [ -f "$BRIEF_FILE" ] || codex_die "brief file not found: $BRIEF_FILE"
elif [ -z "$TASK" ]; then
  echo "error: no task given." >&2; usage 2
fi

codex_log_dir_ensure
[ -n "$LAST_MSG" ] || LAST_MSG="$CODEX_LOG_DIR/goal-last-message.txt"

# --- render the /goal brief -----------------------------------------------------
render_brief() {
  local tpl="" content
  for cand in "$CODEX_HOME/templates/goal.md" "$CODEX_TOOLKIT_ROOT/home/templates/goal.md"; do
    [ -f "$cand" ] && { tpl="$cand"; break; }
  done
  if [ -n "$tpl" ]; then
    content="$(cat "$tpl")"
  else
    content=$'/goal\n\n以下の実装を完了してください。調査だけで終わらず、必要なコード変更・修正・確認まで行い、実装完了状態にしてください。\n\n## 目的 (Purpose)\n{{PURPOSE}}\n\n## 対象ファイル (Target files)\n{{FILES}}\n\n## 実装してほしい内容 (What to implement)\n{{TASK}}\n\n## 変更してはいけない範囲 (Out of bounds)\n{{FORBIDDEN}}\n\n## 完了条件 (Definition of done)\n{{DONE}}\n\n## テスト/確認方法 (How to verify)\n{{VERIFY}}\n\n## 出力してほしい内容 (Required final output)\n- 変更したファイル\n- 実装内容の要約\n- 確認したこと\n- 残っている懸念点があれば明記'
  fi
  content="${content//\{\{TASK\}\}/$TASK}"
  content="${content//\{\{PURPOSE\}\}/${PURPOSE:-上記タスクの完了 (complete the task above)}}"
  content="${content//\{\{FILES\}\}/${FILES:-リポジトリ内をあなたが特定すること (locate them yourself; state which you touched)}}"
  content="${content//\{\{FORBIDDEN\}\}/${FORBID:-無関係なリファクタ・フォーマット変更・依存追加はしない (no unrelated refactors, reformatting, or new dependencies)}}"
  content="${content//\{\{DONE\}\}/${DONE_COND:-- 実装が完了し、リポジトリ既存のテスト/リンタが通ること (implementation complete; existing tests and linters pass)}}"
  content="${content//\{\{VERIFY\}\}/${VERIFY:-リポジトリが提供するテスト/リント/ビルドを実行して結果を報告 (run the tests/lint/build this repo provides and report results)}}"
  printf '%s\n' "$content"
}

BRIEF_TMP="$(mktemp "${TMPDIR:-/tmp}/codex-goal.XXXXXX")"
trap 'rm -f "$BRIEF_TMP"' EXIT
if [ -n "$BRIEF_FILE" ]; then
  cat "$BRIEF_FILE" > "$BRIEF_TMP"
else
  render_brief > "$BRIEF_TMP"
fi

# --- assemble the codex exec argv (runner prepends `codex`) ----------------------
args=(exec --model "$MODEL" --cd "$CODEX_PROJECT_DIR" -o "$LAST_MSG")
[ -n "$PROFILE" ] && args+=(-p "$PROFILE")
[ -n "$SANDBOX" ] && args+=(--sandbox "$SANDBOX")
[ "$JSON" = 1 ] && args+=(--json)
args+=(-)   # read the brief from stdin

if [ "$DRY_RUN" = 1 ]; then
  echo "==> codex-goal (dry-run) — brief:"
  sed 's/^/  | /' "$BRIEF_TMP"
  echo "==> command: codex ${args[*]}  (timeout ${TIMEOUT_S}s, retries $RETRIES)"
  exit 0
fi

# --- cost gate -------------------------------------------------------------------
BREAKER="$CODEX_HOME/scripts/cost-breaker.py"
cost_check() {
  if [ ! -f "$BREAKER" ] || ! codex_have python3; then return 0; fi
  if ! python3 "$BREAKER" check --label goal --est-usd "$EST" 2>/dev/null; then
    echo "codex-goal: cost circuit-breaker tripped — delegation skipped." >&2
    [ "${CODEX_COST_BREAKER_OFF:-0}" = "1" ] || return 1
  fi
  return 0
}
cost_record() {
  if [ ! -f "$BREAKER" ] || ! codex_have python3; then return 0; fi
  python3 "$BREAKER" record --usd "$EST" --label goal >/dev/null 2>&1 || true
}

# --- watchdog runner (portable: no GNU timeout on macOS) --------------------------
run_attempt() {
  # stdin <- brief. Returns codex's exit code, or 124 on watchdog kill.
  bash "$RUNNER" "${args[@]}" < "$BRIEF_TMP" &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$TIMEOUT_S" ]; then
      # Kill the wrapper AND its codex child: a non-interactive bash defers
      # TERM until its foreground child exits, so the child needs its own kill.
      if codex_have pkill; then pkill -TERM -P "$pid" 2>/dev/null; fi
      kill -TERM "$pid" 2>/dev/null
      sleep 2
      if codex_have pkill; then pkill -KILL -P "$pid" 2>/dev/null; fi
      kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 1; waited=$((waited+1))
  done
  wait "$pid"
}

# --- attempts ---------------------------------------------------------------------
attempts=$((RETRIES + 1))
echo "==> codex-goal: model=$MODEL timeout=${TIMEOUT_S}s attempts=$attempts project=$CODEX_PROJECT_DIR"
n=0 rc=1
while [ "$n" -lt "$attempts" ]; do
  n=$((n+1))
  cost_check || exit 3
  run_attempt; rc=$?
  cost_record
  case "$rc" in
    0)  break ;;
    7)  exit 7 ;;  # kill-switch: never retry past an emergency stop
    124) echo "codex-goal: attempt $n/$attempts timed out after ${TIMEOUT_S}s." >&2 ;;
    *)  echo "codex-goal: attempt $n/$attempts failed (exit $rc)." >&2 ;;
  esac
  [ "$n" -lt "$attempts" ] && echo "codex-goal: retrying..." >&2
done

if [ "$rc" != 0 ]; then
  echo "codex-goal: ESCALATE — $attempts consecutive attempt(s) failed." >&2
  echo "  Next step per protocol: implement inline (Claude/you) or ask the user." >&2
  exit 6
fi

# --- evidence for the reviewer ------------------------------------------------------
if git -C "$CODEX_PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "==> working-tree changes (verify before trusting the summary):"
  git -C "$CODEX_PROJECT_DIR" diff --stat | sed 's/^/  /'
fi
echo "==> final message: $LAST_MSG"
exit 0

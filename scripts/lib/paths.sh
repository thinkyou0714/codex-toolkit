#!/usr/bin/env bash
# shellcheck shell=bash
# scripts/lib/paths.sh — single source of truth for every path/env the toolkit needs.
#
# Why this file exists (root-cause fix):
#   The original scripts hardcoded machine-specific paths such as
#   //wsl$/Ubuntu/<legacy-user-home>/... and ~/.lab/codex/... and depended on an
#   unversioned ~/.codex/env.sh. That made them non-portable and silently
#   broken on any other machine. Everything is now resolved here, with env-var
#   overrides and sane fallbacks, so a single `source` makes any script portable.
#
# Usage (from any script):
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/paths.sh"
#
# All variables are exported and safe to re-source (idempotent).

set -o pipefail

# --- CODEX_HOME: where global Codex config/dotfiles live -----------------------
# Replaces the old //wsl$/Ubuntu/<legacy-user-home>/.codex hardcode.
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

# --- Toolkit root (the checkout of this repo) ----------------------------------
# Resolve relative to this file (which lives at scripts/lib/paths.sh), so it
# works no matter the caller's cwd. Two levels up = the repo root.
if [ -z "${CODEX_TOOLKIT_ROOT:-}" ]; then
  _lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CODEX_TOOLKIT_ROOT="$(cd "$_lib_dir/../.." && pwd)"
  export CODEX_TOOLKIT_ROOT
  unset _lib_dir
fi

# --- Project root (the repo Codex is operating on) -----------------------------
# Prefer an explicit env, else the git toplevel, else cwd.
if [ -z "${CODEX_PROJECT_DIR:-}" ]; then
  CODEX_PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  export CODEX_PROJECT_DIR
fi

# --- Log / artifact dir --------------------------------------------------------
# Replaces the old ~/.lab/codex hardcode. Defaults inside the project so logs
# travel with the repo, but fully overridable.
export CODEX_LOG_DIR="${CODEX_LOG_DIR:-$CODEX_PROJECT_DIR/.codex/logs}"
export CODEX_REVIEW_FAILURES_LOG="${CODEX_REVIEW_FAILURES_LOG:-$CODEX_LOG_DIR/review-failures.jsonl}"

# --- The codex CLI binary ------------------------------------------------------
export CODEX_BIN="${CODEX_BIN:-codex}"

# --- Optional global env (cost breaker tunables etc.) --------------------------
# If the user installed home/env.sh to ~/.codex/env.sh, pull it in. Never fatal.
if [ -f "$CODEX_HOME/env.sh" ]; then
  # shellcheck source=/dev/null
  source "$CODEX_HOME/env.sh" || true
fi

# --- Helpers -------------------------------------------------------------------

# codex_log_dir_ensure: create the log dir on demand (callers that write logs).
codex_log_dir_ensure() {
  mkdir -p "$CODEX_LOG_DIR" 2>/dev/null || true
}

# codex_have: true if a command exists on PATH.
codex_have() { command -v "$1" >/dev/null 2>&1; }

# codex_require: exit with a clear message if a command is missing.
codex_require() {
  if ! codex_have "$1"; then
    echo "error: required command '$1' not found on PATH" >&2
    return 127
  fi
}

# codex_die: print to stderr and exit non-zero.
codex_die() { echo "error: $*" >&2; exit 1; }

# --- Cloud / CI helpers (single source of truth; used by cloud-setup + doctor) --

# codex_cloud_env: echo the environment class, one of
# github-actions | codespaces | devcontainer | claude-cloud | container | local.
# Keep this the ONLY place env detection lives so the tools never disagree.
codex_cloud_env() {
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then echo "github-actions"
  elif [ "${CODESPACES:-}" = "true" ]; then echo "codespaces"
  elif [ -n "${REMOTE_CONTAINERS:-}${DEVCONTAINER:-}" ]; then echo "devcontainer"
  elif [ -n "${CCR_AGENT_PROXY_ENABLED:-}" ] || [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then echo "claude-cloud"
  elif [ -f /.dockerenv ] || [ -n "${container:-}" ]; then echo "container"
  else echo "local"; fi
}

# The OpenAI endpoints Codex needs outbound HTTPS to. Single source of truth so
# the setup preflight and the doctor probe (and docs/CLOUD.md) never drift.
export CODEX_OPENAI_HOSTS="${CODEX_OPENAI_HOSTS:-api.openai.com auth.openai.com chatgpt.com}"

# codex_egress_probe HOST: 0 if reachable over HTTPS, 1 if blocked, 2 if no curl.
codex_egress_probe() {
  codex_have curl || return 2
  curl -sS -o /dev/null --max-time 8 "https://$1/" 2>/dev/null
}

# codex_auth_env_source: echo the first available env credential var name
# (OPENAI_API_KEY | CODEX_API_KEY | CODEX_AUTH_JSON | CODEX_AUTH_JSON_B64), else
# nothing + return 1. Shared so setup and doctor accept the same credential set.
codex_auth_env_source() {
  local v
  for v in OPENAI_API_KEY CODEX_API_KEY CODEX_AUTH_JSON CODEX_AUTH_JSON_B64; do
    if [ -n "${!v:-}" ]; then echo "$v"; return 0; fi
  done
  return 1
}

# --- Cost circuit-breaker gate (shared by codex_fix / codex_review / codex-goal) --

# codex_cost_gate LABEL EST: 0 to proceed, 1 to abort. Honors
# CODEX_COST_BREAKER_OFF and skips (allows) when the breaker or python3 is absent.
codex_cost_gate() {
  local label="$1" est="$2" breaker="$CODEX_HOME/scripts/cost-breaker.py"
  if [ ! -f "$breaker" ] || ! codex_have python3; then return 0; fi
  if python3 "$breaker" check --label "$label" --est-usd "$est" 2>/dev/null; then return 0; fi
  [ "${CODEX_COST_BREAKER_OFF:-0}" = "1" ] && return 0
  return 1
}

# codex_cost_record LABEL EST: record spend to the ledger (best effort, never fatal).
codex_cost_record() {
  local label="$1" est="$2" breaker="$CODEX_HOME/scripts/cost-breaker.py"
  if [ ! -f "$breaker" ] || ! codex_have python3; then return 0; fi
  python3 "$breaker" record --usd "$est" --label "$label" >/dev/null 2>&1 || true
}

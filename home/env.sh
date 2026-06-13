#!/usr/bin/env bash
# shellcheck shell=bash
# ~/.codex/env.sh — global Codex environment, sourced by toolkit scripts.
#
# Installed from home/env.sh. Contains NO secrets — only tunables and pointers.
# Put real secrets in your shell profile or a secrets manager and export them
# there; reference them here only by name.
#
# Re-source-safe. Everything is overridable from the outer shell.

# --- Where global Codex config lives ------------------------------------------
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

# --- CLI binary ---------------------------------------------------------------
export CODEX_BIN="${CODEX_BIN:-codex}"

# --- Default models -----------------------------------------------------------
export CODEX_REVIEW_MODEL="${CODEX_REVIEW_MODEL:-gpt-5-codex}"
export CODEX_FIX_MODEL="${CODEX_FIX_MODEL:-gpt-5-codex}"

# --- Cost circuit-breaker tunables --------------------------------------------
# Daily spend ceiling in USD; the breaker trips when the estimated running total
# for the UTC day exceeds this. Set 0 to disable the ceiling.
export CODEX_COST_DAILY_USD="${CODEX_COST_DAILY_USD:-5.00}"
# Per-invocation ceiling in USD.
export CODEX_COST_PER_CALL_USD="${CODEX_COST_PER_CALL_USD:-1.00}"
# Per-invocation spend estimate (USD) the wrappers check against and then record
# to the ledger, so the daily total reflects actual usage. Tune to your models.
export CODEX_REVIEW_EST_USD="${CODEX_REVIEW_EST_USD:-0.20}"
export CODEX_FIX_EST_USD="${CODEX_FIX_EST_USD:-0.40}"
# Where the breaker keeps its running ledger.
export CODEX_COST_LEDGER="${CODEX_COST_LEDGER:-$CODEX_HOME/cost-ledger.jsonl}"
# Set to 1 to bypass the breaker entirely (emergencies only).
export CODEX_COST_BREAKER_OFF="${CODEX_COST_BREAKER_OFF:-0}"

# --- Free-stack quota fallback ------------------------------------------------
# Ordered, comma-separated provider chain the quota-fallback helper walks when a
# provider returns 429 / quota-exhausted. Names are advisory labels.
export CODEX_PROVIDER_CHAIN="${CODEX_PROVIDER_CHAIN:-openai,groq,openrouter,ollama}"

# --- Optional integrations (graceful skip when unset) -------------------------
# export CODEX_VAULT_DIR="$HOME/vault"          # research notes destination
# export CODEX_SLACK_WEBHOOK_URL="..."          # set in your secret store
# export CODEX_N8N_WEBHOOK_URL="..."            # set in your secret store
# export HUB_BASE_URL="http://localhost:3000"   # codex-hub UI, if running

# --- Logs ---------------------------------------------------------------------
export CODEX_LOG_DIR="${CODEX_LOG_DIR:-$CODEX_HOME/logs}"

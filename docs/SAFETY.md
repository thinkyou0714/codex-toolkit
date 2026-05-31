# Safety primitives — v0.2.0 (and what's deferred)

This toolkit invokes a coding agent with shell access and an API key. The
primitives in v0.2.0 cover the two highest-leverage safety controls; the rest
are explicitly deferred to a later release.

## What's in v0.2.0

### 1. Secret redaction — `home/lib/secret_redact.py` (+ `SecretRedact.psm1`)
- Single 8-pattern set used by every wrapper that writes to a log:
  `Authorization: Bearer ...`, `Bearer <token>`, `sk-...`, `xai-...`,
  `api_key=...`, `x-api-key: ...`, `token=...`, `https://user:pass@host`.
- Importable as a module, runnable as a CLI (`python3 secret_redact.py < file`),
  and self-testing (`--selftest` → `8/8 PASS`).
- One library, one regex set: harden in one place and every caller benefits.
  AGENTS.md rule 6 makes this mandatory for any new wrapper.

### 2. Kill switch — `home/scripts/kill-switch.sh`
A file-flag based emergency stop. Works across shells, survives reboots,
no daemon.

```bash
# ACTIVATE — all codex-run invocations refuse until deactivated
kill-switch activate "investigating cost spike on review job"

# CHECK — exit 0 = clear, exit 1 = ACTIVE. Wrappers use this.
kill-switch check

# STATUS — human-friendly
kill-switch status
# → ACTIVE since 2026-05-28T14:11:02Z: investigating cost spike on review job

# DEACTIVATE — when the incident is resolved
kill-switch deactivate
```

State file: `$CODEX_HOME/state/kill-switch.flag` (JSON `{ts, reason, by}`).
Every activate / deactivate is audit-logged to `$CODEX_LOG_DIR/failures.jsonl`
with `event: "kill_switch"`.

AGENTS.md rule 7 requires every codex wrapper to honor the switch.
`scripts/codex-run.sh` is the reference: gate → redact args → invoke `codex`
→ redact-and-log any failure.

### 3. `codex-doctor` checks
`scripts/codex-doctor.sh` reports on the safety primitives at the end of its
run: redact-lib present + 8/8 PASS, kill-switch executable, current switch
state (warns if ACTIVE > 24h — likely forgotten).

## When to flip the kill switch
- Cost spike (`cost-breaker` reports unexpected daily total).
- Suspected credential leak (rotate the key, *then* deactivate).
- Codex CLI regression that produces bad diffs across many repos.
- You're about to do a delicate manual operation and want zero chance an
  agent runs during it.

The 24-hour soft norm: deactivate as soon as the incident is resolved.
`codex-doctor` warns past 24 h so a forgotten switch surfaces in the next
session.

## What's explicitly deferred (v0.3.0+)
These exist as full implementations in the upstream LAB Phase 64–70 work, but
they add real complexity (paths, hooks, settings) and are out of scope for the
"minimal core" of v0.2.0:

| Primitive | Why it's deferred |
|---|---|
| Bernstein composition chain (`codex_safe` → `codex_logged` → `codex_observed`) | Multi-layer wrapper composition; needs a stable cross-shell convention before generalizing. |
| Egress allowlist + DNS pinning | Useful against SSRF / metadata-IP exfil; requires a configurable allowlist and DNS-cache logic. |
| Iteration guard (doom-loop detection) | Needs `codex exec --json` parsing or post-hoc rollout-log scanning; non-trivial. |
| SLO percentile checker | Needs a stable observability schema and runtime characterization. |

If you need any of these now, the LAB originals (`~/.claude/scripts/codex_*.{ps1,sh}`,
`~/.claude/hooks/codex_*`) are MIT and copy-friendly, but they reference
LAB-specific paths and would need genericizing first.

## Failure-log schema

All v0.2.0 components append to `$CODEX_LOG_DIR/failures.jsonl` (one JSON object
per line, UTC ISO 8601 timestamps):

```json
{"ts":"2026-05-28T14:11:02Z","hook":"codex-toolkit","event":"kill_switch","category":"activated","detail":{"reason":"cost spike","by":"alice"}}
{"ts":"2026-05-28T14:15:33Z","hook":"codex-run","category":"kill_switch_blocked","exit_code":7,"detail":"blocked by kill-switch: ACTIVE since 2026-05-28T14:11:02Z: cost spike"}
{"ts":"2026-05-28T14:22:00Z","hook":"codex-run","category":"invoke","exit_code":0,"detail":"codex exec --model gpt-5-codex - "}
```

Rotate this file yourself (the toolkit doesn't bundle a rotator yet); the LAB
ships a generic 5MB rotator if you need a pattern.

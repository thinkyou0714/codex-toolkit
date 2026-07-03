---
name: run-checks
description: Run codex-toolkit's checks (smoke test, shell lint, python lint, spell). Use when asked to test, lint, or verify the toolkit.
---

Run the repo checks and report results concisely.

1. Ensure lint tools are present (SessionStart bootstrap pip-installs `ruff`+`codespell`; `shellcheck` is usually pre-installed on web).
2. Fast path: `make test` (smoke test — no extra deps). Full gate: `make check` (= `lint` shellcheck + `lint-py` ruff + `spell` codespell + `test`).
3. Summarize: which target passed/failed and the first offending file/line per failure.
4. Do not edit scripts unless asked. For a health check of an install use `make doctor`.

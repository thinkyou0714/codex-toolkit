# Global Agent Instructions — Full Reference

This is the expanded companion to the compressed `~/.codex/AGENTS.md`. The CLI
loads the compressed file for everyday work (smaller = cheaper + better cache
hit rate); read this when you need the reasoning behind a rule.

## Why a compressed + full split?

Prompt caching rewards a byte-stable prefix. The compressed `AGENTS.md` is kept
small and its top section never changes, so the provider can cache it across
calls. Detail and rationale live here, out of the hot path. See
`docs/PROMPT-PATTERNS.md` for the caching model in depth.

## 1. Understand before acting

Most agent failures are not bad edits — they are confident edits to the wrong
place. Read the file, trace the call site, check for an existing helper, confirm
the path exists. A 30-second read prevents a 30-minute wrong turn.

## 2. Smallest change that solves it

A bug fix does not need surrounding cleanup. A one-shot script does not need a
plugin system. Three similar lines beat a premature abstraction. Don't build for
hypothetical futures; build for the task.

## 3. Match existing conventions

Consistency is a feature. Mirror the surrounding code's naming, error handling,
import style, and test layout even if you would personally do it differently.

## 4. Validate only at boundaries

Internal functions can trust their callers and framework guarantees. Reserve
validation for genuine boundaries: user input, network responses, file parsing,
external APIs. Defensive checks for impossible states are noise.

## 5. Verify your work

"Done" means you ran what the repo provides — tests, type-check, linter, build —
and it passed. For UI, exercise the feature, don't just compile it. If you can't
verify, say so explicitly instead of implying success.

## 6. Safety & reversibility

Weigh blast radius and reversibility. Local, reversible edits are free; actions
that touch shared state or are hard to undo need confirmation. When you hit an
obstacle, find the root cause — don't reach for `--no-verify`, `reset --hard`,
or deleting the lock file to make it go away.

## 7. Cost discipline

Agent loops can burn money fast. The cost breaker enforces daily/per-call
ceilings; treat a trip as a signal to stop and rethink, not an obstacle to
override. Prefer one good call over ten cheap retries.

## 8. Resilience

Treat provider quota/429 as expected, not exceptional. Degrade along the
configured provider chain; never crash a long task because the first provider
was busy.

## 9. Persistent Session Memory (PSM)

`~/.codex/session_context.md` is small, curated working memory that survives
across sessions and repos. Read it at start; append durable lessons; prune it so
it stays small enough to keep in context cheaply.

## 10. Override order

Effective instructions = global static rules, then global dynamic notes, then
the repo's own `AGENTS.md`, then the explicit task. The most specific wins on
conflict; the repo `AGENTS.md` always beats this file.

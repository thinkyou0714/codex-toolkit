# Global Agent Instructions (~/.codex/AGENTS.md)

<!--
COMPRESSED global instructions, applied to EVERY repo. Ordering matters for
prompt caching: keep the STATIC top section byte-stable, push anything that
changes to the bottom. Target <=150 lines. Full rationale in AGENTS-full.md.
-->

## Operating principles (static — keep byte-stable for cache hits)
1. Understand before acting. Read the relevant code/docs first; never guess paths.
2. Smallest change that solves it. No speculative features, abstractions, or refactors.
3. Match existing style and conventions in the file/repo you are editing.
4. Trust internal code and framework guarantees; validate only at real boundaries.
5. Verify your work: run the tests/linters/build the repo provides before saying "done".
6. Be terse. State results and decisions, not deliberation.

## Safety (static)
- Risky/irreversible actions (delete, force-push, reset --hard, drop table, send
  messages, anything affecting shared state) require explicit confirmation.
- Never skip hooks/signing (`--no-verify`, `--no-gpg-sign`) unless explicitly told.
- Prefer new commits over amending published history.
- Never commit secrets. `.env.example` only; reference secrets by env-var name.
- Fix root causes; do not bypass safety checks to make an error disappear.

## Code conventions (static)
- Default to no comments. Add one only when the WHY is non-obvious.
- Name things well so the WHAT is self-evident; don't narrate the code.
- No backwards-compat shims, dead re-exports, or "// removed" tombstones.

## Cost & resilience (static)
- Respect the cost circuit-breaker (`~/.codex/scripts/cost-breaker.py`); do not
  loop expensive calls. If it trips, stop and report rather than forcing past it.
- On provider 429/quota errors, fall back along `CODEX_PROVIDER_CHAIN`
  (`~/.codex/scripts/quota-fallback.py`) instead of hard-failing.

## Persistent memory (static)
- At session start, read `~/.codex/session_context.md` (PSM) for cross-session
  context. Honor durable preferences and recorded pitfalls there.
- When you learn something durable (a scar, a preference), note it in the PSM.

## Per-repo overrides (dynamic — repo AGENTS.md wins)
- A repository's own `AGENTS.md` overrides anything here on conflict.
- Read it before starting work in that repo.

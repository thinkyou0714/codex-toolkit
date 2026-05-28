# Strategy & rationale

Condensed notes on *why* the toolkit is shaped the way it is. This is the
durable thinking behind the code, not a roadmap.

## The problem it solves

Ad-hoc agent setups decay:
- **Path rot** — scripts hardcode one machine (`//wsl$/...`, `C:/Users/...`),
  so they break for everyone else and on every new machine.
- **Lost config** — the global `~/.codex` setup is unversioned; if the laptop
  dies, the carefully-tuned config dies with it.
- **Leaky secrets** — webhooks/tokens get pasted into scripts.
- **Runaway cost** — autonomous loops can burn money with no ceiling.
- **Fragile automation** — relative hook paths silently stop firing after a
  `cd`, disabling safety guards without warning.

The toolkit turns each of these into a versioned, portable, env-driven solution.

## Design tenets

1. **Portable or it doesn't exist.** Every path flows through one resolver
   (`scripts/lib/paths.sh`) with env override + fallback. Adding a new path
   without going through it is a bug.
2. **Config is code.** The global `~/.codex` files live in `home/` and are
   reinstallable. The machine is now disposable.
3. **Secrets never touch the repo.** `.example`/`.template` only; integrations
   degrade gracefully when their env var is missing.
4. **Safe by default, override on purpose.** The cost breaker trips by default;
   bypassing it is an explicit, logged choice.
5. **Layered, not monolithic.** Global / tools / repo-template / claude — install
   only what you need. The toolkit stays small; big app surfaces are referenced
   by env (`HUB_BASE_URL`), never bundled.
6. **Self-documenting & self-checking.** `AGENTS.md`, `docs/`, `codex-doctor`,
   and `tests/smoke.sh` keep the toolkit honest.

## Extraction policy

This toolkit was extracted **by copy, not move** — the originating repo was left
untouched. That makes the extraction non-destructive and reversible, and lets
the two evolve independently.

## Adoption path

1. Install global + scripts; tune cost ceilings.
2. Scaffold one repo; fill in its `AGENTS.md`; enable the PR-review workflow.
3. Add Claude delegation if you use Claude Code.
4. Iterate: as you find a new hardcode or a missing guardrail, fix it *in the
   toolkit* so every repo benefits.

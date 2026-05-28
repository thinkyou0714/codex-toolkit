# Prompt patterns

Reusable patterns that make Codex/agent runs cheaper, more reliable, and more
reviewable. These inform the toolkit's design (compressed AGENTS.md, review
prompt, delegation skill).

## 1. Cache-friendly instruction ordering

Model providers cache a stable prompt *prefix*. Put the bytes that never change
first; push anything dynamic to the end.

```
[ static system rules ]   <- byte-stable, cached
[ static repo facts    ]
[ dynamic: this task   ]   <- changes every call, not cached
```

This is why `home/AGENTS.md` keeps its top section byte-stable and the detail
lives in `AGENTS-full.md`. Don't reorder or reword the static block casually —
a one-byte change busts the cache.

## 2. Self-contained delegation

A delegated agent does NOT share your conversation. A delegation prompt must
carry everything: exact paths, the precise transform, and the definition of
done. "Fix the thing we discussed" fails; "In `src/auth.ts`, replace the regex
on line 40 with `…`, then run `npm test`" succeeds.

## 3. Diff-scoped review

Review prompts should constrain the model to the diff and forbid commentary on
pre-existing code. Group findings by severity, demand `file:line`, and require a
one-line verdict. See `repo-template/.github/codex/review-prompt.md`.

## 4. Structured output when a machine reads it

If tooling consumes the output, give the model a JSON schema and ask it to match
(see `review-schema.json`). For humans, markdown is fine.

## 5. Verify-before-done

Bake "run the tests/lint/build the repo provides, then report" into the task.
The agent's prose is intent; the passing command and the diff are evidence.

## 6. Terse by default

Ask for results and decisions, not narration. Long agent monologues cost tokens
and bury the signal.

## 7. Cost-aware loops

Don't retry a failing call in a tight loop. One well-formed call beats ten cheap
ones, and the cost breaker will (correctly) stop a runaway loop. On quota/429,
fall back along the provider chain rather than hammering one provider.

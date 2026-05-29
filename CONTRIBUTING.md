# Contributing

Thanks for improving the toolkit. It's small on purpose — keep it that way.

## Ground rules (enforced by `AGENTS.md` and CI)

1. **No machine-specific paths.** Anything resembling `//wsl$/...`,
   `C:/Users/<name>/...`, or `~/.lab/...` is a bug. Resolve paths via env vars
   and `scripts/lib/paths.sh`, always with a sane fallback.
2. **No secrets.** Ship `.example`/`.template` files only; reference secrets by
   env-var name. Integrations must degrade gracefully when their env is unset.
3. **Bash:** `set -euo pipefail`, source `lib/paths.sh`, stay shellcheck-clean
   at `-S warning`.
4. **Python:** stdlib only (no third-party deps); must `python3 -m py_compile`
   cleanly.
5. **Claude hooks** are documented/registered with absolute `$CLAUDE_PROJECT_DIR`
   paths — never bare relative paths.
6. **Keep `home/AGENTS.md` small** and its top section byte-stable (prompt-cache
   friendliness); rationale goes in `AGENTS-full.md`.

## Dev loop

```bash
make test      # smoke.sh
make lint      # shellcheck -S warning (if installed)
make check     # lint + test (what CI runs)
```

## Before opening a PR

- `make check` passes locally.
- New/changed behavior is covered in `tests/smoke.sh` where feasible.
- Update `CHANGELOG.md` (Unreleased section) and bump `VERSION` if releasing.
- Conventional Commits, imperative mood (e.g. `fix: …`, `feat: …`).

## Releasing

```bash
make bump V=minor      # bump VERSION + seed a CHANGELOG section
# fill in the new CHANGELOG section, then:
make release-check     # assert VERSION and CHANGELOG agree
make check             # lint + smoke
git commit -am "release: vX.Y.Z"
git tag -a vX.Y.Z -m vX.Y.Z && git push --follow-tags
```

Pushing the `vX.Y.Z` tag triggers `release.yml`, which re-checks the tag
against `VERSION`/`CHANGELOG`, runs the smoke suite, and publishes the matching
CHANGELOG section as the GitHub release notes (via `gh`, no third-party action).

## Adding a new path or env var

Add it to `scripts/lib/paths.sh` (or `home/env.sh`), document it in
`.env.example`, and reference it from `docs/`. Don't read a path directly in a
script — go through the resolver so every component stays portable.

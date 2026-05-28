---
name: lab-research
description: Run a structured research task (web search + synthesis) and save the result as a dated note to a knowledge vault. Use when asked to research a topic, gather sources, or produce a referenced brief that should be archived for later reuse.
---

# lab-research

Turn an open question into a referenced, archived research note.

## Inputs
- A research question or topic.
- Optional: depth (`quick` | `standard` | `deep`), and a destination vault.

## Configuration (env-driven — no hardcoded machine paths)
- `CODEX_VAULT_DIR` — where notes are saved. **If unset, the skill saves into
  `./research/` in the current repo and says so** (graceful fallback; the
  original hardcoded one user's vault path — fixed here).
- `CODEX_SLACK_WEBHOOK_URL` / `CODEX_N8N_WEBHOOK_URL` — optional; if set, a link
  to the saved note is posted there. If unset, that step is skipped silently.

## Procedure
1. Clarify the question if ambiguous (one round, then proceed).
2. Gather sources (web search/fetch). Prefer primary sources; capture URLs.
3. Synthesize: a short answer up top, then supporting detail, then a sources
   list. Use the structure in `references/note-template.md`.
4. Save via the helper, which handles the vault path + optional notification:

   ```bash
   scripts/save-to-vault.sh "<slug>" "<path-to-note.md>"
   ```

5. Report the saved path back to the user.

## Notes
- Cite every non-obvious claim. No fabricated URLs.
- Keep notes self-contained so they're useful months later.
- See `references/runner-usage.md` for the optional `runner.py` batch mode.

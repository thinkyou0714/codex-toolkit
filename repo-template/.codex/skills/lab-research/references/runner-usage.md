# lab-research runner — usage

`runner.py` is an optional helper for processing a batch of research questions
resumably. It does no network/LLM work itself; it normalizes the input and tells
the agent which questions still lack a saved vault note.

## Typical flow

```bash
# 1. List the questions, one per line (blank lines and #comments ignored).
cat > questions.txt <<'EOF'
What are the tradeoffs of SQLite vs Postgres for a single-node app?
How does prompt caching billing work for Claude?
EOF

# 2. See what's pending (set CODEX_VAULT_DIR so done items are detected).
export CODEX_VAULT_DIR="$HOME/vault/research"
python3 scripts/runner.py questions.txt

# 3. For each pending item, the agent researches it and saves with:
scripts/save-to-vault.sh "<slug-from-runner>" note.md

# 4. Re-run runner.py; completed items drop out of "pending" automatically.
```

## JSON input
```bash
python3 scripts/runner.py --json questions.json   # questions.json = ["q1","q2"]
```

## Notes
- "Done" detection matches `*-<slug>.md` in `CODEX_VAULT_DIR`. Without that env
  var, nothing is treated as done (everything stays pending).
- Process one question at a time and save before moving on, so a long batch is
  always resumable.

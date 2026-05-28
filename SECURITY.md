# Security

## Threat model (what this toolkit can do)

By design, this toolkit gives a language model real capabilities. Use it with
that in mind:

- **It can edit files in your repo.** `codex_fix.sh` and any Claude-delegated
  Codex run can modify, add, or delete files inside the workspace. The Codex
  CLI sandbox (`sandbox_mode = "workspace-write"`) bounds this to the workspace
  by default; do not relax to `danger-full-access` without thinking.
- **It can run commands.** With the default sandbox, commands run inside the
  workspace; outside that requires an approval per `approval_policy`. Never
  use `approval_policy = "never"` combined with a relaxed sandbox unless the
  whole environment is disposable (e.g. an isolated CI runner).
- **It sends code to OpenAI.** Every review/fix call ships the relevant code
  (the diff, the prompt, files Codex chooses to read) to the configured model
  provider. The PR-review GitHub Action sends the full PR diff. If your code
  is sensitive, weigh that before enabling.

## Secrets

- **No secret ever lives in this repo.** All examples and templates carry
  placeholders or env-var references; install scripts never write secret
  values. The Codex `config.toml` references API keys by env-var (e.g.
  `${OPENAI_API_KEY}`); fill them in your shell or secret store.
- **The cost-ledger and PSM are not secret but may be sensitive.** The cost
  ledger contains call labels/timestamps; the PSM (`~/.codex/session_context.md`)
  may contain free-form notes. Both stay local; nothing in the toolkit uploads
  them anywhere.
- **Webhook URLs** (Slack/n8n) are read from env vars and only used when set.
  If unset, the integration silently skips — no half-configured exfiltration.

## CI workflow (`codex-pr-review.yml`)

- Triggered by `pull_request`, NOT `pull_request_target`. This means:
  - Fork PRs do not get repo secrets; the workflow's `OPENAI_API_KEY` check
    skips cleanly when the secret is unavailable.
  - The job never checks out or executes untrusted PR code; it only reads
    the diff text via the GitHub API.
- The action does post the PR diff to OpenAI. If the repo is private, that is
  a deliberate choice. Disable the workflow or remove `OPENAI_API_KEY` to
  opt out.

## Hooks

- Claude Code hooks ship under `claude-integration/` and run on your machine
  with your privileges. They are deliberately small and side-effect-light
  (PSM append, suggestion text). Inspect before adopting; never source hooks
  from untrusted parties.
- Hook registrations should use absolute `$CLAUDE_PROJECT_DIR` paths. A
  relative path can be silently disabled by a `cd`, which removes a safety
  layer you may have been relying on.

## Cost safety

- The cost circuit-breaker (`cost-breaker.py`) enforces per-call and per-day
  USD ceilings before each Codex invocation and records spend after. A trip
  is the right time to stop and rethink, not to set
  `CODEX_COST_BREAKER_OFF=1` and push through.

## Supply chain

- Python: stdlib only, no third-party packages — nothing to be pinned or
  audited beyond Python itself.
- Bash: shellcheck-clean at `-S warning` in CI.
- The PR-review workflow installs `@openai/codex` from npm at run time; pin
  the version (`npm install -g @openai/codex@x.y.z`) if you want
  deterministic CI behavior.

## Reporting a vulnerability

If you find a security issue in this toolkit, please open a private issue or
a GitHub Security Advisory on this repository. Do not post details publicly
until the maintainer has confirmed a fix. For prompt-injection or model-
behavior issues in Codex/OpenAI itself, report to OpenAI directly.

# Codex CLI in cloud environments

> **TL;DR (ja):** クラウドセッション(Claude Code on the web / GitHub Actions /
> Codespaces / devcontainer / 任意のコンテナ)で `scripts/codex-cloud-setup.sh`
> を1回実行すると、Codex CLI のインストール → 認証 → クラウド用プロファイル →
> egress 検査まで自動で整います。あとは `codex-goal` で実装タスクを委譲するだけ。
> 前提は「環境のネットワークポリシーが OpenAI ドメインを許可していること」のみ。

Ephemeral containers reset on every session: no `~/.codex`, no CLI, no auth.
This toolkit makes "Codex works here" a one-command property of the *repo*
instead of a manual property of the machine.

## One-command bootstrap

```bash
scripts/codex-cloud-setup.sh              # do everything, best effort
scripts/codex-cloud-setup.sh --check     # report readiness, change nothing
scripts/codex-cloud-setup.sh --dry-run   # print the plan
```

What it does, in order:

1. **Detect** the environment (`github-actions`, `codespaces`, `devcontainer`,
   `claude-cloud`, `container`, `local`).
2. **Install the CLI** when missing: `npm install -g @openai/codex`
   (pin with `CODEX_CLI_VERSION`).
3. **Wire auth** without writing secrets into the repo (see the matrix below).
4. **Install the toolkit layer** (`install.sh --home --scripts`) so the
   wrappers, cost breaker, kill switch, and redaction lib are on PATH.
5. **Seed the cloud profile** `~/.codex/cloud.config.toml` (non-interactive:
   `approval_policy = "never"`, `sandbox_mode = "workspace-write"`,
   network on inside the sandbox). Use it with `codex exec -p cloud …`.
6. **Preflight egress** to the OpenAI endpoints and name any blocked domain.

In this repo, `.claude/bootstrap.sh` (the Claude Code `SessionStart` hook) runs
it automatically in web sessions — opt out with `CODEX_CLOUD_BOOTSTRAP=0`.

## Auth matrix (headless)

Set exactly one of these in the environment's secret store:

| Secret | Effect | Billing |
|---|---|---|
| `OPENAI_API_KEY` | setup pipes it to `codex login --with-api-key` (stdin; never in argv/logs) | API |
| `CODEX_API_KEY` | read directly by `codex exec` only; nothing written to disk | API |
| `CODEX_AUTH_JSON_B64` | `base64 -w0 ~/.codex/auth.json` from a machine where you ran `codex login`; setup restores it (0600) | your ChatGPT plan |
| none (interactive box) | `codex login --device-auth` | your ChatGPT plan |

Notes:
- The `OPENAI_API_KEY` env var **by itself no longer authenticates** current
  CLIs — that is exactly why the setup pipes it into
  `codex login --with-api-key`. Only `CODEX_API_KEY` works env-only, and only
  for `codex exec`.
- Treat `auth.json` as a password. On **persistent** self-hosted runners seed
  it *only if missing* — unconditionally restoring the secret clobbers
  refreshed tokens and eventually breaks auth (official CI/CD auth guidance).
  `codex-cloud-setup.sh` already skips auth wiring when a login is present.
- ChatGPT-plan usage shares your interactive rate limits (5-hour rolling +
  weekly). For unattended automation prefer an API key.

## Network policy (the usual blocker)

Codex needs egress to:

```
api.openai.com        # Responses API
auth.openai.com       # login/token refresh
chatgpt.com           # ChatGPT-plan auth + Codex cloud
```

In Claude Code on the web, allow these in the environment's network policy —
a blocked domain shows up as `CONNECT tunnel failed, response 403` from the
proxy, and `codex doctor` reports the endpoints unreachable. Verify with:

```bash
scripts/codex-doctor.sh --network     # per-domain egress report
```

Behind a TLS-intercepting proxy also make sure `HTTPS_PROXY` and
`SSL_CERT_FILE` (the proxy's CA bundle) are exported; the CLI honors both.

## Sandboxing inside a container

- Default to `workspace-write`: Codex's own Linux sandbox works in most cloud
  containers (verified in Claude Code web containers). Quick test:
  `codex sandbox -- echo ok`.
- Newer CLI builds sandbox via user namespaces (bubblewrap), which default
  Docker seccomp/AppArmor profiles may block. If the quick test fails, the
  container itself is your boundary:
  use `--sandbox danger-full-access`, or
  `--dangerously-bypass-approvals-and-sandbox` for fully unattended runs.
  Never on a shared machine.
- Approvals: there is no human in CI. `approval_policy = "never"` (the cloud
  profile sets it) so failures return to the model instead of hanging.

## GitHub Actions

Two options:

1. **Official action** — `openai/codex-action@v1`: installs the CLI, holds the
   API key behind a local proxy (never in process args), exposes the final
   message as a step output. Use `safety-strategy: drop-sudo` (default) or
   `unprivileged-user`; gate triggers with `allow-users`; never expose the key
   to fork PRs.
2. **This toolkit** — for parity with local runs (kill switch, cost breaker,
   redaction, /goal contract):

   ```yaml
   - uses: actions/checkout@v6
   - run: bash scripts/codex-cloud-setup.sh --no-egress
     env: { OPENAI_API_KEY: "${{ secrets.OPENAI_API_KEY }}" }
   - run: |
       scripts/codex-goal.sh --profile cloud \
         --done "- tests pass: make test" \
         --verify "make test" \
         "Fix the failing CI job (see the log below)…"
   ```

The repo template also ships `.github/workflows/codex-pr-review.yml` for
diff-scoped PR review.

## Delegating work in the cloud (/goal)

`codex-goal.sh` is the delegation contract (see `claude-integration/skills/codex-goal/`):
a complete brief (purpose / files / constraints / definition of done / verify),
a watchdog timeout (default 300s — `codex exec` has **no built-in timeout**),
one retry, then a deterministic outcome the orchestrator can branch on:

| exit | meaning | orchestrator action |
|---|---|---|
| 0 | done | review `git diff`, run the checks, then report |
| 6 | 2 consecutive failures/timeouts | implement inline or ask the user |
| 7 | kill switch ACTIVE | stop, surface the reason |
| 3 | cost breaker tripped | stop, surface the state |

Follow-ups reuse the same Codex session: `echo "…" | codex exec resume --last`.

## Known headless gotchas (upstream)

- `codex exec "<prompt>"` **hangs** when stdin is an open, silent pipe — close
  it (`</dev/null`) or pass the prompt via stdin with an explicit `-`. The
  toolkit wrappers already do this (openai/codex#20919).
- A killed run writes **nothing** to `-o`; treat an empty last-message file as
  failure, not as an empty answer.
- Codex may leave orphaned child processes when killed; `codex-goal.sh` kills
  the process group best-effort (`pkill -P`).
- `--ephemeral` sessions cannot be resumed — resuming silently starts fresh.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `codex: command not found` | run `codex-cloud-setup.sh`; needs Node 18+ |
| `CONNECT tunnel failed, response 403` | domain missing from the network policy (see above) |
| `codex login status` → not logged in | no secret configured; see the auth matrix |
| exec exits 1 outside a repo | add `--skip-git-repo-check` |
| run hangs forever | stdin left open, or genuinely stuck — the /goal watchdog handles both |

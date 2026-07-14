# Codex を個人開発の実装担当として最大限活用する 100 のアイデア

深堀調査(OpenAI 公式ドキュメント / openai/codex ソース / OpenAI Cookbook /
コミュニティ実践、2026-07 時点)に基づく実践カタログ。オーケストレータ
(Claude Code 等)が設計・検証し、Codex が実装する分業を前提とする。

**ステータス凡例**
- ✅ **実装済み** — このツールキットに動くコード/設定として同梱
- 🔶 **一部実装** — 中核はツールキットにあり、残りは手順
- 📖 **レシピ** — 記載の手順・コマンドでそのまま使える(公式機能/外部ツール)

> 検証済みの環境事実: Codex CLI は Claude Code on the web のコンテナに
> `npm i -g @openai/codex` で導入でき、Landlock サンドボックスも動作する。
> 唯一の前提は環境のネットワークポリシーが `api.openai.com` /
> `auth.openai.com` / `chatgpt.com` を許可していること(→ `docs/CLOUD.md`)。

## A. クラウド環境基盤 (1–10)

1. ✅ **ワンコマンド・ブートストラップ** — 新しいコンテナを1コマンドで
   「codex exec が動く」状態に。`scripts/codex-cloud-setup.sh`
2. ✅ **CLI バージョンピン** — エフェメラル環境で毎回同じ挙動にする。
   `CODEX_CLI_VERSION=x.y.z`
3. ✅ **SessionStart フックで自動化** — Claude Code web セッション開始時に
   ブートストラップを自動実行。`.claude/bootstrap.sh`(`CODEX_CLOUD_BOOTSTRAP=0` で無効)
4. ✅ **環境の自動判別** — github-actions / codespaces / devcontainer /
   claude-cloud / container を検出し挙動を変える(例: `$GITHUB_PATH` へ PATH 追記)
5. ✅ **クラウド専用プロファイル** — `~/.codex/cloud.config.toml` を
   `codex exec -p cloud` で重ね掛け(approval never / workspace-write / network on)
6. 📖 **サンドボックス実地検査** — コンテナで Landlock が生きているかを
   `codex sandbox -- echo ok` で確認してから sandbox_mode を決める
7. ✅ **PATH 自動配線** — `~/.local/bin` の wrapper 群をセッションから即使えるように
8. ✅ **egress プリフライト** — ブロックされているドメインを名指しで報告し、
   ネットワークポリシーの直し方まで提示(`codex-cloud-setup` / `codex-doctor --network`)
9. 📖 **devcontainer/Codespaces 組込** — `postCreateCommand` に
   `codex-cloud-setup.sh` を書けば新規 Codespace が最初から Codex 可
10. 📖 **codex-universal イメージ** — `ghcr.io/openai/codex-universal` で
    Codex cloud と同等の実行環境をローカル/CI に再現

## B. 認証・シークレット (11–20)

11. ✅ **API キーは stdin 渡しでログイン** — `printenv OPENAI_API_KEY |
    codex login --with-api-key`。argv・ログ・履歴にキーを出さない
12. ✅ **実行スコープキー** — `CODEX_API_KEY` は `codex exec` だけが読む。
    ディスクに何も書かない CI 向けの最小権限
13. ✅ **auth.json のシークレット化** — ローカルで `codex login` した
    `~/.codex/auth.json` を `CODEX_AUTH_JSON_B64` として保存し、ChatGPT プランを
    CI で再利用(0600 で復元)
14. ✅ **「無ければ seed」原則** — ログイン済み環境では認証に触らない。
    永続ランナーで refresh 済みトークンを上書きすると認証が壊れる(公式 CI/CD ガイド)
15. 📖 **デバイス認証** — ブラウザのないボックスは `codex login --device-auth`
16. ✅ **秘密のログ混入防止** — 8 パターン redaction(`secret_redact.py`)を
    全 wrapper がログ書込前に通す
17. 📖 **fork PR にキーを渡さない** — codex-action の `allow-users` ゲート、
    GitLab では fork MR を `when: never` でスキップ(公式 Cookbook)
18. ✅ **プロキシ/CA 配線** — `HTTPS_PROXY` と `SSL_CERT_FILE` を doctor が可視化。
    TLS 検証は絶対に無効化しない
19. ✅ **漏えいの継続検知** — gitleaks + secrets-scan ワークフローを標準装備
20. 📖 **キーを持たない実行** — `openai/codex-action@v1` はキーをローカル
    プロキシに隔離し、CLI プロセスには渡さない

## C. /goal 委譲プロトコル (21–30)

21. ✅ **/goal 契約テンプレート** — 目的 / 対象ファイル / 禁止範囲 / 完了条件 /
    検証方法 / 必須出力を強制(`home/templates/goal.md` + `codex-goal.sh`)
22. ✅ **ゴール=完了条件** — 公式 Goals 設計と同じ思想:「ゴール文は開始
    プロンプトであり完了判定基準」。テンプレートがそれを体現
23. ✅ **自律性スニペット** — 「調査で終わらせない・確認待ちで止まらない」を
    ブリーフに常時注入(公式 prompting guide の最重要推奨)
24. ✅ **ブロック時停止条件** — 詰まったら「何が原因で、何があれば進めるか」を
    報告して終了、をテンプレートで義務化
25. ✅ **5 分ウォッチドッグ** — `codex exec` に組込タイムアウトは無い(ソース
    確認済)。外部 watchdog で kill + プロセスグループ掃除(`--timeout`)
26. ✅ **2 連続失敗→エスカレート** — exit 6 を返し「inline 実装 or ユーザー
    確認」へ分岐。黙って 3 回目を撃たない
27. 📖 **完了条件は測定可能に** — 「動く」ではなく「`make test` が通る」
    「p95 が 120ms を切る」。弱い目標は強い目標に書き直してから渡す
28. ✅ **仕様分岐は渡す前に潰す** — Codex に曖昧さを判断させない。
    skill が「決定を渡せ、質問を渡すな」を明文化
29. ✅ **長文ブリーフのファイル渡し** — `codex-goal.sh -f brief.md`
30. ✅ **要約でなく diff を信じる** — 完了時に `git diff --stat` と
    last-message ファイルを提示。「要約は意図、diff は事実」

## D. プロンプト / AGENTS.md 設計 (31–40)

31. ✅ **グローバル AGENTS.md** — 全リポジトリ共通の作業規範を
    `~/.codex/AGENTS.md` に(ツールキットが配布・バージョン管理)
32. ✅ **byte-stable 先頭でキャッシュ最適化** — 静的な規則を先頭に固定し
    プロンプトプレフィックスキャッシュを効かせる(`docs/PROMPT-PATTERNS.md`)
33. ✅ **リポジトリ AGENTS.md テンプレ + placeholder 検査** — 未記入
    `{{PLACEHOLDER}}` を doctor が fail として検出
34. 📖 **32KiB 予算の配分** — 結合された指示ファイルは `project_doc_max_bytes`
    (既定 32KiB)で切られる。グローバルは 5KiB 以下に抑える
35. 📖 **「地図を渡す」原則** — AGENTS.md は約 100 行の地図にし、詳細は
    参照先ファイルへ(OpenAI Harness Engineering の教訓)
36. ✅ **正確なコマンドを書く** — ビルド/テスト/リントはコピペ可能な形で
    AGENTS.md に(テンプレートが要求)
37. 📖 **階層 override** — root→leaf の順で深い AGENTS.md が上書き。
    ディレクトリ固有規則はそのディレクトリに置く
38. 📖 **スキルへの移行** — 旧 `~/.codex/prompts/` スラッシュプロンプトは
    CLI 0.117 で廃止。反復指示は SKILL.md 形式(`$CODEX_HOME/skills` /
    リポジトリ `.agents/skills`)へ移す
39. ✅ **スキル化** — 反復ワークフローは SKILL.md で固定化(repo-template に
    codex-doctor / lab-research を同梱。公式の自動発見パスは `.agents/skills`)
40. 📖 **メタプロンプティング** — 遅い/冗長なターンの後、Codex 自身に
    「自分への指示の改善案」を出させて AGENTS.md に反映

## E. 非対話実行 `codex exec` の使いこなし (41–50)

41. 📖 **exec を自動化の基本形に** — 進捗は stderr、最終メッセージだけ stdout。
    パイプ処理はこの前提で組む
42. ✅ **stdin ハング対策** — プロンプト引数だけ渡すと開いた stdin を待って
    無限ハング(openai/codex#20919)。`</dev/null` を必ず付ける(wrapper +
    回帰テスト済み)
43. ✅ **プロンプトは `-` で stdin 渡し** — クォート事故を根絶(review/goal
    wrapper の標準形)
44. ✅ **`-o` で結果をファイル受け** — stdout のノイズと分離し、次工程へ渡す
45. 🔶 **`--json` で機械可読に** — JSONL イベント(`thread.started` /
    `turn.completed` / `item.completed`)。`codex-goal --json` でパススルー、
    jq レシピ: `select(.type=="item.completed" and .item.type=="agent_message") | .item.text`
46. 📖 **`--output-schema` で構造化出力** — JSON Schema は
    `additionalProperties:false` + 全プロパティ required が必須
47. 📖 **セッション継続** — `codex exec resume --last`(cwd でフィルタ)/
    ID 指定。文脈とプロンプトキャッシュを保ったまま追修正
48. 📖 **`--ephemeral` の罠** — 再開不可。resume すると黙って新規セッションになる
49. 📖 **リポジトリ外実行** — `--skip-git-repo-check`(docs 生成など)
50. 📖 **単発オーバーライド** — `-c sandbox_workspace_write.network_access=true`
    のように config.toml を編集せず一時変更

## F. レビュー・品質ループ (51–60)

51. ✅ **diff スコープレビュー** — 差分のみ・file:line 必須・severity タグ付き
    (`codex_review.sh` + review-prompt/schema)
52. 📖 **専用レビューサブコマンド** — `codex exec review --uncommitted |
    --base <br> | --commit <sha>`(P1–P4 で構造化報告、ツリー無変更)
53. ✅ **レビュー結果の構造化蓄積** — JSONL に取込み
    `codex_review_ingest.py --stats` で傾向分析
54. ✅ **自動レビューループ** — `codex_auto_review.sh` でレビュー→取込を一括
55. 📖 **クロスモデルレビュー** — Claude 実装 → Codex レビュー(またはその逆)。
    ベンダー間で失敗モードが相関しないため検出面が広がる
56. 📖 **敵対的レビュー** — 公式プラグイン `openai/codex-plugin-cc` の
    `/codex:adversarial-review` で設計判断ごと攻めさせる
57. 📖 **反復修復ループ** — レビュー→最小修正→実コマンド検証を回し、
    「validation delta が縮んでいるか」を継続判定に使う(公式 Cookbook)
58. 📖 **プリコミットフック** — read-only の `codex exec review --uncommitted`
    で P0 検出時 exit 1。重いレビューは CI へ
59. ✅ **PR レビュー CI テンプレ** — `.github/workflows/codex-pr-review.yml`
    を repo-template で配布
60. ✅ **検証は別フェーズの実コマンドで** — 編集エージェントの自己申告を
    信じない(verify-before-done、`docs/PROMPT-PATTERNS.md` §5)

## G. CI/CD・GitHub 自動化 (61–70)

61. 📖 **公式 GitHub Action** — `openai/codex-action@v1`(`safety-strategy:
    drop-sudo`、`permission-profile`、`final-message` 出力)
62. 📖 **CI 失敗の自動修正** — `workflow_run` failure → 失敗 SHA を checkout →
    「全テストを通す最小変更」→ 素の `npm test` で再検証 → 自動 PR(公式 Cookbook)
63. 📖 **issue→PR パイプライン** — ラベル/Automation から `workflow_dispatch`
    に課題文を渡し、実装 → `codex/<ticket>` ブランチ → PR → チケット遷移
64. 📖 **@codex review** — Codex cloud の自動 PR レビュー(P0/P1 のみ、
    AGENTS.md の `## Review guidelines` に従う)。CI 不要で導入最速
65. 📖 **依存更新トリアージ** — dependabot PR を read-only で差分+changelog
    評価しテスト実行、構造化出力で approve/comment を分岐
66. 📖 **Codex cloud をスクリプトから** — `codex cloud exec --env <ID>` で
    投入、`list --json` / `diff` / `apply` で回収
67. 📖 **夜間 cron 棚卸し** — `on: schedule` で stale issue のラベリング、
    TODO 掃除、ドキュメント同期などの低リスク作業を無人実行
68. 📖 **権限分離** — 編集は Codex、ネットワーク副作用(push / PR / API)は
    スコープ済み `GITHUB_TOKEN` を持つワークフロー側で
69. 📖 **codex-action は job の最後に** — エージェントがホストを触った後に
    信頼できるステップを置かない(公式 security ガイド)
70. 📖 **インジェクション面の管理** — PR 本文・コミットメッセージ・fork 由来
    AGENTS.md・スクリーンショットは攻撃面。`${{ }}` 直挿しでなく `env:` 渡し

## H. 並列化・マルチエージェント (71–80)

71. 📖 **git worktree フリート** — タスク毎に worktree + バックグラウンド
    `codex exec`、レビューして merge、`git worktree prune`
72. ✅ **ハブ&ワーカー分業** — Claude Code がハブ(設計・検証)、Codex が
    実装ワーカー(claude-integration 全体がこの形)
73. ✅ **自動委譲判定** — タスクの広さ/機械性/曖昧さをスコアリングし
    「委譲すべきか」をフックで提案(`assess_plan_delegatability.py`)
74. 📖 **Codex を MCP ツール化** — `codex mcp-server` を Claude Code に登録
    (`codex` / `codex-reply` の 2 ツール、threadId で継続)
75. ✅ **Codex を MCP クライアントに** — `codex mcp add` / config.toml の
    `[mcp_servers.*]`(設定例同梱)で外部ツールを Codex に与える
76. 📖 **公式プラグイン連携** — `/plugin marketplace add openai/codex-plugin-cc`
    → `/codex:rescue`(委譲)、`/codex:review`、`--background` ジョブ管理
77. 📖 **ファイルベース・サブエージェント** — 一時ディレクトリにペルソナ
    AGENTS.md を書き、profile 付き `codex exec` で使い捨て専門家を作る
78. 📖 **並列度はレビュー律速** — レビューが追いつく数まで。未レビュー
    ブランチの滞留は正味マイナス(コミュニティで一致した知見)
79. 📖 **長時間タスクの detach** — tmux / ジョブマネージャで切り離し、
    ログは `-o` とセッションファイルから回収
80. 📖 **ExecPlan / PLANS.md** — 長期作業は「初心者でも再開できる自己完結
    計画ファイル」に永続化。クラッシュしてもファイルだけから再開(公式)

## I. 安全・コスト制御 (81–90)

81. ✅ **コストサーキットブレーカ** — 日次 + per-call 上限、実行前 check /
    実行後 record。委譲(goal)にも適用済み
82. ✅ **キルスイッチ** — `kill-switch activate "<理由>"` で全 wrapper を
    一括停止(exit 7)。緊急停止を 1 コマンドに
83. ✅ **ログ前 redaction の強制** — 全 wrapper が 8 パターン redaction を
    通してから failures.jsonl へ
84. ✅ **最小権限サンドボックス** — read-only → workspace-write →
    danger-full-access を用途で使い分け(config 例 + CLOUD.md 指針)
85. ✅ **サンドボックス内ネットワークの明示制御** — workspace-write は既定
    network off。必要時のみ profile で on
86. ✅ **429 フォールバックチェーン** — `quota-fallback.py` がプロバイダ
    チェーンを辿り、ハンマリングを防ぐ
87. 📖 **実測コスト追跡** — `--json` の `turn.completed.usage`
    (input/cached/output/reasoning tokens)を集計して見積りを実測で補正
88. 🔶 **モデルルーティング** — バルク作業は mini 系、レビューは
    フラッグシップ。profiles + `CODEX_*_MODEL` 環境変数で切替(判断は手動)
89. 🔶 **暴走ループ防止** — 反復上限は wrapper 側で(watchdog + breaker 実装
    済)。`tool_output_token_limit` 等の config key はレシピ
90. ✅ **監査ログ** — 全 invoke・失敗・ブロックを `failures.jsonl` に記録し
    インシデント調査可能に

## J. セッション・メモリ・計測 (91–100)

91. ✅ **PSM(永続セッションメモリ)** — `~/.codex/session_context.md` に
    教訓・好みを蓄積、Claude 側 Stop フックで自動追記(prune 上限付き)
92. 📖 **セッションの資産化** — `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
    を検索・再開・fork(`codex resume` / `codex fork`)
93. 📖 **session id の機械取得** — `--json` の先頭イベント `thread.started`
    から `thread_id` を取り、後続の `exec resume <id>` に渡す
94. ✅ **結果のチェーン** — `-o` で受けた最終メッセージを次タスクのブリーフに
    接続(codex-goal の標準出力設計)
95. ✅ **健康診断の習慣化** — `codex-doctor`(cloud readiness 込み)を随時、
    `--strict` を CI で
96. ✅ **失敗トレンド分析** — `codex_review_ingest.py --stats` で頻出カテゴリ
    を把握し、対策を AGENTS.md の規則に昇格
97. 📖 **「繰り返しミス→規則化」ループ** — 同じ指摘が 2 回出たら AGENTS.md に
    1 行追加。基本から始めて実害ベースで育てる(公式推奨)
98. 📖 **キャッシュ効率の計測** — `cached_input_tokens` を監視し、AGENTS.md
    の並び替え等でキャッシュ率を改善
99. ✅ **オフライン検証基盤** — mock codex + 隔離 CODEX_HOME で wrapper を
    API なしでテスト(smoke + safety + cloud スイート)
100. ✅ **ツールキット自体を改善先に** — 新しいハードコードやガードレール
     欠落を見つけたら個別リポジトリでなくツールキット側で直し、全リポジトリに
     配る(`docs/STRATEGY.md` の運用原則)

## 集計

| ステータス | 件数 |
|---|---|
| ✅ 実装済み(このツールキット) | 43 |
| 🔶 一部実装 | 4 |
| 📖 レシピ(即使用可の手順) | 53 |

主要ソース: OpenAI Codex 公式ドキュメント(noninteractive / auth / agents-md /
prompting)、OpenAI Cookbook(using_goals_in_codex / codex_exec_plans /
iterative repair loops / autofix CI / build code review / Jira-GitHub /
GitLab quality)、openai/codex ソース(exec CLI・イベントスキーマ・rollout
recorder)、openai/codex-action、openai/codex-plugin-cc、コミュニティ実践
(worktree フリート、codex-first スキル、MCP オーケストレータ各種)。

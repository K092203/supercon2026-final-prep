# Claude × Codex セカンドオピニオン・パイプライン

> 目的: **Codex CLI(OpenAI)を「セカンドオピニオン / 検証台」として Claude から呼べる**ようにする。
> ねらいは ①独立レビューで見落としを減らす ②正誤・性能の検証を別エンジンで確かめる
> ③**トークン消費の分散**(レビュー/検証を Codex 側=別課金に逃がす)。

## 設計原則

- **情報の対称性**: Claude も Codex も**同じファイルだけを読む** — リポジトリ本体・`docs/`・
  富岳スナップショット `results/<jobid>/`(最新 `results/latest/`)。Codex の入口は `AGENTS.md`
  に集約し、Claude の入口(README/docs)と一致させてある。
- **Codex は read-only**: `codex exec` は既定で read-only サンドボックス。`tools/codex-review.sh`
  も `--sandbox read-only` を明示。Codex は**読んで指摘するだけでソースを編集しない**(検証台に徹する)。
- **富岳には入らない**: Claude と同じ責務分離。Codex も手元(WSL)のファイルのみ読む。

## セットアップ(WSL2)

```bash
# 1. インストール (Node>=16。本機 node v18 で可。npm prefix はユーザー領域=sudo不要)
npm install -g @openai/codex
#   代替: curl -fsSL https://chatgpt.com/codex/install.sh | sh   (Rust単体バイナリ)

# 2. 認証 (どちらか)
codex login                       # ChatGPT アカウントで対話ログイン
export CODEX_API_KEY=sk-...       # または API キー (codex exec 限定。.bashrc 等に)

# 3. 確認
codex --version
```

> ⚠️ API キーをジョブ/CI のグローバル環境変数に置かない(漏洩防止。公式注意)。手元シェルの
> 環境変数か `codex login` を使う。

## 使い方

```bash
tools/codex-review.sh diff             # 現在の git 作業差分を Codex がレビュー
tools/codex-review.sh result           # results/latest/ のスナップショットを Codex が分析
tools/codex-review.sh "stencil_blocked.cpp のタイル境界に off-by-one が無いか確認して"
```

各実行は Codex の最終回答を `results/codex/<timestamp>-<mode>.md` に保存する。
**Claude はこのファイルを読んで二次判断に使う**(= パイプライン)。

## 典型フロー(Claude 主導)

```
Claude が実装/修正
   │
   ▼
tools/codex-review.sh diff        ← Codex(read-only)が独立レビュー → results/codex/*.md
   │
   ▼
Claude が results/codex/*.md を読み、指摘を取り込んで修正
```

富岳実行後なら `tools/fugaku-run.sh …` → `tools/codex-review.sh result` で、
Codex にスナップショットを読ませて「なぜ遅い/失敗したか」をセカンドオピニオンさせる。

## 補足

- 出力 `results/codex/` は `.gitignore` 済み(`results/*`)。
- モデルや既定挙動を固定したい場合は `~/.codex/config.toml`(または `.codex/config.toml`)で設定可。
  モデル名は変わりやすいので本リポジトリには固定設定を置かない方針。
- Codex を**編集にも使いたい**場合は `codex exec --sandbox workspace-write …` だが、本パイプラインは
  検証台用途のため read-only 固定。編集は Claude 側で行う。

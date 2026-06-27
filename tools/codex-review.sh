#!/usr/bin/env bash
# =====================================================================
# codex-review.sh — Codex CLI を「セカンドオピニオン/検証台」として呼ぶ (read-only)
#   Claude が実装、Codex が独立レビュー/検証 → トークン消費を分散し、見落としを減らす。
#   Codex は read-only サンドボックスで動くのでソースは編集しない(純粋に読んで指摘)。
#
# 使い方:
#   tools/codex-review.sh diff            # 現在の git 作業差分をレビュー
#   tools/codex-review.sh result          # results/latest/ のスナップショットを分析
#   tools/codex-review.sh "<任意の質問>"  # 自由プロンプト
#
# 出力: results/codex/<timestamp>-<mode>.md (Claude が読んで二次判断に使う) + 標準出力
# 認証: 事前に `codex login`(ChatGPT) か `export CODEX_API_KEY=...`(exec限定)
# =====================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v codex >/dev/null 2>&1; then
  echo "ERROR: codex 未インストール。"
  echo "  npm install -g @openai/codex   (詳細・認証は docs/codex-pipeline.md)"
  exit 1
fi

MODE="${1:-diff}"
case "$MODE" in
  diff)
    PROMPT="このリポジトリの現在の git 作業差分(git diff および git status の内容)をレビューしてください。\
バグ・見落とし・整合性の問題・改善点を、重要度順に日本語で簡潔に指摘してください。憶測は『推測』と明記すること。"
    TAG="diff" ;;
  result)
    PROMPT="results/latest/ にある富岳ジョブのスナップショット(meta.json, build.log, stdout.txt, stderr.txt, \
resource.txt, status.txt)を読み、ジョブが成功/失敗した理由・性能上のボトルネック・次の一手を日本語で分析してください。"
    TAG="result" ;;
  *)
    PROMPT="$MODE"; TAG="ask" ;;
esac

mkdir -p results/codex
OUT="results/codex/$(date +%Y%m%d-%H%M%S)-${TAG}.md"
echo "=== codex exec (read-only) mode=$MODE → $OUT"
# --sandbox read-only: 検証台として編集させない。進捗は stderr、最終回答のみ stdout。
codex exec --sandbox read-only "$PROMPT" | tee "$OUT"
echo ""
echo ">>> 保存: $OUT  (Claude はこのファイルを読んで二次判断に使える)"

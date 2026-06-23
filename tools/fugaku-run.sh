#!/usr/bin/env bash
# WSL2↔富岳 開発ループ ワンショット実行
# 使い方: tools/fugaku-run.sh <target> [budget_sec]
#   target:     skeleton | stencil | search
#   budget_sec: 時間予算 (秒)。デフォルト 1750 (本選 30分 - 10秒マージン)
#
# 実行フロー:
#   [1] rsync + ログインノードビルド  (fugaku-sync.sh)
#   [2] pjsub 投入                   (fugaku-submit.sh)
#   [3] pjstat ポーリング            (fugaku-wait.sh)
#   [4] rsync 結果回収               (fugaku-fetch.sh)
#   [5] results/latest/ に概要表示   (AI 解析のエントリポイント)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TARGET="${1:-skeleton}"
BUDGET_SEC="${2:-1750}"

echo "======================================================"
echo " SuperCon2026 富岳実行ループ"
echo " target=$TARGET  budget=${BUDGET_SEC}s"
echo "======================================================"

# [1] sync + build
"$SCRIPT_DIR/fugaku-sync.sh" "$BUDGET_SEC"

# [2] submit → JOBID
SUBMIT_OUT=$("$SCRIPT_DIR/fugaku-submit.sh" "$TARGET" "$BUDGET_SEC")
JOBID=$(echo "$SUBMIT_OUT" | grep 'JOBID=' | grep -oP '\d+')
echo "$SUBMIT_OUT"
echo ">>> JOBID=$JOBID"

# [3] wait
"$SCRIPT_DIR/fugaku-wait.sh" "$JOBID"

# [4] fetch
"$SCRIPT_DIR/fugaku-fetch.sh" "$JOBID" "$TARGET" "$BUDGET_SEC"

# [5] サマリ表示 (AI が読む)
echo ""
echo "======================================================"
echo " 実行結果サマリ: results/$JOBID/"
echo "======================================================"
echo "--- meta.json ---"
cat "$REPO_ROOT/results/$JOBID/meta.json"
echo ""
echo "--- stdout (末尾 20行) ---"
tail -20 "$REPO_ROOT/results/$JOBID/stdout.txt" 2>/dev/null || echo "(stdout なし)"
echo ""
echo "--- stderr (末尾 5行) ---"
tail -5  "$REPO_ROOT/results/$JOBID/stderr.txt" 2>/dev/null || echo "(stderr なし)"
echo ""
echo ">>> AI 解析: results/latest/ を読んでください"

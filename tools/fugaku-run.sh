#!/usr/bin/env bash
# WSL2↔富岳 開発ループ ワンショット実行
# 使い方: tools/fugaku-run.sh <target> [budget_sec]
#   target:     skeleton | stencil | search
#   budget_sec: 時間予算 (秒)。デフォルト 1750 (本選 30分=1800 - 50秒マージン。値は当日確認)
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 本戦初日セットアップ (初回のみ。以降は不要)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. SSH config 追記
#      cat docs/fugaku-ssh-template.txt >> ~/.ssh/config
#      # HostName と User を実際の値に書き換える
#
# 2. アカウント設定ファイルを作成 (4項目を埋める)
#      cp tools/fugaku-config.env.template tools/fugaku-config.env
#      # FUGAKU_USER   … 富岳アカウント名
#      # FUGAKU_GROUP  … PJM グループ
#      # FUGAKU_RSCGRP … リソースグループ (例: small)
#      # FUGAKU_REMOTE_DIR … /home/your_account/supercon2026/final-prep
#
# 3. 富岳側ディレクトリ作成
#      ssh fugaku "mkdir -p ~/supercon2026/final-prep/results"
#
# 4. ControlMaster を確立 (OTP がある場合はここで入力。以降 4h 不要)
#      ssh fugaku "echo 'connection OK'"
#
# 5. 動作確認 (sync + build のみ、ジョブ投入なし)
#      tools/fugaku-sync.sh 5
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# 通常の開発ループ (上記セットアップ完了後):
#   tools/fugaku-run.sh skeleton 1750
#   → results/latest/stdout.txt と meta.json を Claude Code に読ませる
#   → src/ を修正して再実行
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
echo "--- 状態サマリ (build / 実行 / 資源) ---"
grep -oE '"(outcome|build_status|wall_sec|max_rss_kb|git_commit|git_dirty)": [^,}]*' \
  "$REPO_ROOT/results/$JOBID/meta.json" 2>/dev/null | tr -d '"' | sed 's/^/  /'
echo ""
echo ">>> AI 解析: results/latest/ を読む (meta.json / build.log / resource.txt / status.txt / stdout / stderr)"

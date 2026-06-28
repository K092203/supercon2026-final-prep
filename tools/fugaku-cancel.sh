#!/usr/bin/env bash
# 富岳ジョブを削除 (暴走・入力ミス・時間指定ミスを見つけた瞬間に即停止)
# 使い方: tools/fugaku-cancel.sh [jobid]
#   jobid 省略時は results/.last-jobid (直近投入ジョブ) を使う
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/fugaku-config.env"
source "$SCRIPT_DIR/fugaku-validate.sh"   # config 値の fail-closed 検証

JOBID="${1:-$(cat "$REPO_ROOT/results/.last-jobid" 2>/dev/null || echo '')}"
if [ -z "$JOBID" ]; then
  echo "ERROR: JOBID を指定するか results/.last-jobid が必要です"
  echo "  使い方: tools/fugaku-cancel.sh <jobid>"
  exit 1
fi

echo "=== pjdel $JOBID → $FUGAKU_HOST"
ssh "$FUGAKU_HOST" "pjdel $JOBID"
echo "=== 削除要求を送信しました (pjstat で確認してください)"

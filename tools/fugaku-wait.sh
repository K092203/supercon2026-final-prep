#!/usr/bin/env bash
# pjstat をポーリングしてジョブ完了を待つ
# 使い方: tools/fugaku-wait.sh <jobid>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/fugaku-config.env"
source "$SCRIPT_DIR/fugaku-validate.sh"   # config 値の fail-closed 検証
mkdir -p "$ROOT/results"

JOBID="${1:-$(cat "$(cd "$SCRIPT_DIR/.." && pwd)/results/.last-jobid" 2>/dev/null || echo '')}"
if [ -z "$JOBID" ]; then
  echo "ERROR: JOBID を指定するか results/.last-jobid が必要です"
  exit 1
fi

INTERVAL="${FUGAKU_POLL_INTERVAL:-30}"
# 未知の非空ステータスを「完了」と即断しないための上限(連続到達で打切り)。
UNKNOWN_MAX="${FUGAKU_UNKNOWN_MAX:-10}"
unknown_seen=0
echo "=== waiting: JOBID=$JOBID (poll every ${INTERVAL}s)"
# ⚠️ Day1: 富岳 pjstat -j の ST 列フォーマットを実機確認すること。
#    下の case は汎用名 + 富士通短縮コード(ACC/QUE/RUN/EXT/CCL/RJT/ERR/HLD…)の両対応。

while true; do
  STATUS=$(ssh "$FUGAKU_HOST" "pjstat -j $JOBID 2>/dev/null | awk 'NR==2{print \$3}'" 2>/dev/null || echo "UNKNOWN")
  TIMESTAMP=$(date '+%H:%M:%S')
  echo "[$TIMESTAMP] JOBID=$JOBID STATUS=${STATUS:-<empty>}"

  case "$STATUS" in
    QUEUED|HOLD|UNKNOWN|QUE|HLD|ACC)
      ssh "$FUGAKU_HOST" "pjstat -v $JOBID" > "$ROOT/results/.last-jobinfo" 2>/dev/null || true ;;
  esac

  case "$STATUS" in
    COMPLETED|EXT)
      echo "COMPLETED" > "$ROOT/results/.last-status"
      echo "=== COMPLETED"; exit 0 ;;
    REJECTED|ERROR|CANCELLED|RJT|ERR|CCL)
      echo "$STATUS" > "$ROOT/results/.last-status"
      echo "=== FAILED: STATUS=$STATUS"; exit 1 ;;
    QUEUED|RUNNING|COMPLETING|HOLD|UNKNOWN|ACC|QUE|RUN|RNA|RNO|RNE|RNP|RNR|HLD)
      unknown_seen=0
      sleep "$INTERVAL" ;;
    "")
      # pjstat にジョブが無い = 履歴から消滅 = 完了とみなす
      echo "GONE" > "$ROOT/results/.last-status"
      echo "=== pjstat にジョブ無し (完了とみなす)"; exit 0 ;;
    *)
      # 未知の非空ステータス: 完了と即断しない。警告して待機継続(上限到達で打切り)。
      unknown_seen=$((unknown_seen + 1))
      echo "[$TIMESTAMP] WARNING: 未知のステータス '$STATUS' (${unknown_seen}/${UNKNOWN_MAX})。pjstat フォーマットを要確認。" >&2
      if [ "$unknown_seen" -ge "$UNKNOWN_MAX" ]; then
        echo "UNKNOWN($STATUS)" > "$ROOT/results/.last-status"
        echo "=== 未知ステータスが上限到達。手動で pjstat を確認のこと(fetch は別途)。" >&2
        exit 0
      fi
      sleep "$INTERVAL" ;;
  esac
done

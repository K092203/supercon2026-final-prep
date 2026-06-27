#!/usr/bin/env bash
# pjstat をポーリングしてジョブ完了を待つ
# 使い方: tools/fugaku-wait.sh <jobid>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/fugaku-config.env"
mkdir -p "$ROOT/results"

JOBID="${1:-$(cat "$(cd "$SCRIPT_DIR/.." && pwd)/results/.last-jobid" 2>/dev/null || echo '')}"
if [ -z "$JOBID" ]; then
  echo "ERROR: JOBID を指定するか results/.last-jobid が必要です"
  exit 1
fi

INTERVAL="${FUGAKU_POLL_INTERVAL:-30}"
echo "=== waiting: JOBID=$JOBID (poll every ${INTERVAL}s)"

while true; do
  STATUS=$(ssh "$FUGAKU_HOST" "pjstat -j $JOBID 2>/dev/null | awk 'NR==2{print \$3}'" 2>/dev/null || echo "UNKNOWN")
  TIMESTAMP=$(date '+%H:%M:%S')
  echo "[$TIMESTAMP] JOBID=$JOBID STATUS=$STATUS"

  case "$STATUS" in
    COMPLETED)
      echo "COMPLETED" > "$ROOT/results/.last-status"
      echo "=== COMPLETED"
      exit 0
      ;;
    REJECTED|ERROR|CANCELLED)
      echo "$STATUS" > "$ROOT/results/.last-status"
      echo "=== FAILED: STATUS=$STATUS"
      exit 1
      ;;
    QUEUED|RUNNING|COMPLETING|HOLD|UNKNOWN)
      sleep "$INTERVAL"
      ;;
    *)
      # pjstat が空 (ジョブ履歴から消えた場合) → 完了とみなす
      echo "GONE" > "$ROOT/results/.last-status"
      echo "=== STATUS 取得不可 (ジョブ完了済みの可能性)"
      exit 0
      ;;
  esac
done

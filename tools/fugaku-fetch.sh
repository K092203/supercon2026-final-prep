#!/usr/bin/env bash
# 富岳から実行結果を回収し results/{JOBID}/ に保存する
# 使い方: tools/fugaku-fetch.sh <jobid> <target> <budget_sec>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/fugaku-config.env"

JOBID="${1:-$(cat "$REPO_ROOT/results/.last-jobid" 2>/dev/null || echo '')}"
TARGET="${2:-unknown}"
BUDGET_SEC="${3:-unknown}"

if [ -z "$JOBID" ]; then
  echo "ERROR: JOBID を指定してください"
  exit 1
fi

LOCAL_DIR="$REPO_ROOT/results/$JOBID"
mkdir -p "$LOCAL_DIR"

echo "=== fetch: $FUGAKU_HOST:$FUGAKU_REMOTE_DIR/results/$JOBID/ → $LOCAL_DIR/"
rsync -avz \
  "$FUGAKU_HOST:$FUGAKU_REMOTE_DIR/results/$JOBID/" \
  "$LOCAL_DIR/"

# AI 解析用 meta.json を生成 (ローカル側で作成)
EXIT_CODE=$(cat "$LOCAL_DIR/exit_code.txt" 2>/dev/null || echo "unknown")
cat > "$LOCAL_DIR/meta.json" << METAEOF
{
  "jobid": "$JOBID",
  "target": "$TARGET",
  "budget_sec": $BUDGET_SEC,
  "nodes": ${FUGAKU_NODE_COUNT},
  "mpi_ranks": ${FUGAKU_MPI_RANKS},
  "omp_threads": ${FUGAKU_OMP_THREADS},
  "total_cores": $((FUGAKU_MPI_RANKS * FUGAKU_OMP_THREADS)),
  "rscgrp": "${FUGAKU_RSCGRP}",
  "elapse_limit": "${FUGAKU_ELAPSE}",
  "exit_code": $EXIT_CODE,
  "fetched_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
METAEOF

# results/latest シンボリックリンクを更新
ln -sfn "$JOBID" "$REPO_ROOT/results/latest"

echo "=== 回収完了: results/$JOBID/"
echo "    meta.json: $(cat "$LOCAL_DIR/meta.json" | tr -d '\n')"

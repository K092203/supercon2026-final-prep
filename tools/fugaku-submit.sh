#!/usr/bin/env bash
# 富岳にジョブを投入し JOBID を返す
# 使い方: tools/fugaku-submit.sh <target> [budget_sec]
#   target: skeleton | stencil | search
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/fugaku-config.env"

TARGET="${1:-skeleton}"
BUDGET_SEC="${2:-${BUDGET_SEC:-1750}}"

# ジョブスクリプトを動的生成 (pjsub ディレクティブは変数展開不可のためここで埋め込む)
JOB_SCRIPT=$(cat << ENDJOB
#!/bin/bash
#PJM -L rscgrp=${FUGAKU_RSCGRP}
#PJM -L node=${FUGAKU_NODE_COUNT}
#PJM -L elapse=${FUGAKU_ELAPSE}
#PJM -g ${FUGAKU_GROUP}
#PJM -j
#PJM -S

export OMP_NUM_THREADS=${FUGAKU_OMP_THREADS}
export OMP_PROC_BIND=close
export OMP_PLACES=cores

RESULTS="${FUGAKU_REMOTE_DIR}/results/\${PJM_JOBID}"
mkdir -p "\${RESULTS}"

echo "target=${TARGET} budget=${BUDGET_SEC} ranks=${FUGAKU_MPI_RANKS} threads=${FUGAKU_OMP_THREADS}" > "\${RESULTS}/meta.txt"
date -u +%Y-%m-%dT%H:%M:%SZ >> "\${RESULTS}/meta.txt"

mpiexec -n ${FUGAKU_MPI_RANKS} \\
  "${FUGAKU_REMOTE_DIR}/build/fugaku/${TARGET}" \\
  > "\${RESULTS}/stdout.txt" 2> "\${RESULTS}/stderr.txt"

EXIT_CODE=\$?
echo "\${EXIT_CODE}" > "\${RESULTS}/exit_code.txt"
echo "completed" >> "\${RESULTS}/meta.txt"
date -u +%Y-%m-%dT%H:%M:%SZ >> "\${RESULTS}/meta.txt"
exit \${EXIT_CODE}
ENDJOB
)

echo "=== submitting: target=$TARGET budget=${BUDGET_SEC}s → $FUGAKU_HOST"
TMP_JOB="/tmp/supercon_$$_${TARGET}.job"
SUBMIT_OUT=$(echo "$JOB_SCRIPT" | ssh "$FUGAKU_HOST" \
  "cat > $TMP_JOB && pjsub $TMP_JOB && rm -f $TMP_JOB" 2>&1)
echo "$SUBMIT_OUT"

# JOBID 抽出: "pjsub Job 123456 submitted." から数字を取る
JOBID=$(echo "$SUBMIT_OUT" | grep -oP '(?<=Job )\d+' | head -1)
if [ -z "$JOBID" ]; then
  echo "ERROR: JOBID を取得できませんでした。pjsub 出力を確認してください。"
  exit 1
fi

mkdir -p "$REPO_ROOT/results"
echo "$JOBID" > "$REPO_ROOT/results/.last-jobid"
echo "JOBID=$JOBID"

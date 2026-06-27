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
# ビルドlog は別ディレクトリ(_build)なので個別に回収 → このジョブの build.log とする
rsync -az "$FUGAKU_HOST:$FUGAKU_REMOTE_DIR/results/_build/build-latest.log" \
  "$LOCAL_DIR/build.log" 2>/dev/null || true

# --- スナップショットから状態を抽出 (meta.json 1つで全体を掴めるように) ---
EXIT_CODE=$(cat "$LOCAL_DIR/exit_code.txt" 2>/dev/null || echo "")
[[ "$EXIT_CODE"  =~ ^-?[0-9]+$ ]] || EXIT_CODE=null
[[ "$BUDGET_SEC" =~ ^[0-9]+$ ]]   || BUDGET_SEC=null
COMMIT=$(sed -n 's/.*commit=\([^ ]*\).*/\1/p' "$LOCAL_DIR/meta.txt"  2>/dev/null | head -1); COMMIT="${COMMIT:-unknown}"
DIRTY=$(sed -n 's/.*dirty=\([0-9]*\).*/\1/p'  "$LOCAL_DIR/meta.txt"  2>/dev/null | head -1); DIRTY="${DIRTY:-0}"
WALL=$(sed -n 's/.*wall_sec=\([0-9]*\).*/\1/p' "$LOCAL_DIR/status.txt" 2>/dev/null | head -1); WALL="${WALL:-null}"
MAXRSS=$(awk -F': ' '/Maximum resident set size/{print $2; exit}' "$LOCAL_DIR/resource.txt" 2>/dev/null)
[[ "$MAXRSS" =~ ^[0-9]+$ ]] || MAXRSS=null   # 非数値(time異常終了等)は null にして不正JSONを防ぐ
BUILD_STATUS=ok; grep -qiE 'error:' "$LOCAL_DIR/build.log" 2>/dev/null && BUILD_STATUS=error
SCHED=$(cat "$REPO_ROOT/results/.last-status" 2>/dev/null || echo "")
# outcome: status.txt があれば正常完了系、無ければ PJM kill 等で未完
if [ -f "$LOCAL_DIR/status.txt" ]; then
  if   [ "$EXIT_CODE" = "0" ];   then OUTCOME=completed
  elif [ "$EXIT_CODE" = "124" ]; then OUTCOME=timeout
  else OUTCOME=failed; fi
else OUTCOME=killed-or-incomplete; fi

# 入力の同一性 + parsed #TUNE (どの入力で・何点だったかを meta だけで追える)
INPUT_SHA=$(head -1 "$LOCAL_DIR/input.sha256" 2>/dev/null);
if [ -n "$INPUT_SHA" ]; then INPUT_SHA_J="\"$INPUT_SHA\""; else INPUT_SHA_J=null; fi
INPUT_BYTES=$(wc -c < "$LOCAL_DIR/input.dat" 2>/dev/null | tr -d ' '); [[ "$INPUT_BYTES" =~ ^[0-9]+$ ]] || INPUT_BYTES=null
TLINE=$(grep '^#TUNE' "$LOCAL_DIR/stderr.txt" 2>/dev/null | tail -1)
T_EL=$(sed -n 's/.*elapsed=\([0-9.eE+-]*\).*/\1/p' <<<"$TLINE"); [[ "$T_EL" =~ ^[0-9.eE+-]+$ ]] || T_EL=null
T_SC=$(sed -n 's/.*score=\([0-9.eE+-]*\).*/\1/p'   <<<"$TLINE"); [[ "$T_SC" =~ ^[0-9.eE+-]+$ ]] || T_SC=null
T_CO=$(sed -n 's/.*correct=\([0-9]*\).*/\1/p'      <<<"$TLINE"); [[ "$T_CO" =~ ^[0-9]+$ ]] || T_CO=null

# AI 解析用 meta.json を生成 (= そのジョブの検死報告書のヘッダ)
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
  "git_commit": "$COMMIT",
  "git_dirty": $DIRTY,
  "build_status": "$BUILD_STATUS",
  "exit_code": $EXIT_CODE,
  "wall_sec": $WALL,
  "max_rss_kb": $MAXRSS,
  "outcome": "$OUTCOME",
  "sched_status": "$SCHED",
  "input_sha256": $INPUT_SHA_J,
  "input_bytes": $INPUT_BYTES,
  "tune": { "elapsed": $T_EL, "score": $T_SC, "correct": $T_CO },
  "fetched_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
METAEOF

# results/latest シンボリックリンクを更新
ln -sfn "$JOBID" "$REPO_ROOT/results/latest"

echo "=== 回収完了: results/$JOBID/"
echo "    meta.json: $(cat "$LOCAL_DIR/meta.json" | tr -d '\n')"

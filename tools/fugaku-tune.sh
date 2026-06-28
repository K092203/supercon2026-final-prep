#!/usr/bin/env bash
# =====================================================================
# fugaku-tune.sh — 富岳バッチ掃引 (fugaku-run.sh の N 構成版)
#   configs.tsv を渡すと: sync+build → configs/tune-sweep を送付 → tune ジョブ投入
#   → 完了待ち → results.csv 回収 → incumbent 更新、までを 1 発で回す。
#
# 使い方:
#   tools/fugaku-tune.sh <configs.tsv> [budget_sec] [objective] [input_file]
#     budget_sec : ソルバ 1 回の予算 (既定 1750。--budget で全構成に適用)
#     objective  : min-elapsed(既定) | max-score | score-per-sec
#     input_file : solver が stdin から問題入力を読む場合に渡す (富岳へ送付して全構成に与える)
#
# 前提: tools/fugaku-config.env (= fugaku-run.sh と同じ) と ControlMaster 確立済み。
# ⚠️ 本選前はローカル(tools/tune-local.sh)で全経路を検証する。本スクリプトの
#    実機初通しは Day1。今は `bash -n` 構文チェックまで。
# =====================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/fugaku-config.env"
source "$SCRIPT_DIR/fugaku-validate.sh"   # config 値の fail-closed 検証 (sed 置換前に)

CONFIGS="${1:?usage: fugaku-tune.sh <configs.tsv> [budget_sec] [objective] [input_file]}"
BUDGET="${2:-1750}"
OBJECTIVE="${3:-min-elapsed}"
INPUT="${4:-}"
[ -f "$CONFIGS" ] || { echo "ERROR: configs が無い: $CONFIGS"; exit 1; }

# ---- ラウンド番号 (既存 round-NNN の数で採番) ----
mkdir -p "$REPO_ROOT/results/tune"
N=$(find "$REPO_ROOT/results/tune" -maxdepth 1 -type d -name 'round-[0-9]*' | wc -l)
ROUND=$(printf "round-%03d" "$N")
LOCAL_RDIR="$REPO_ROOT/results/tune/$ROUND"
mkdir -p "$LOCAL_RDIR"
cp "$CONFIGS" "$LOCAL_RDIR/configs.tsv"

# elapse → 秒 (anytime 判定用)。HH:MM:SS / MM:SS / 秒 のいずれでも壊れない。
ELAPSE_SEC=$(awk -F: 'NF==3{print $1*3600+$2*60+$3} NF==2{print $1*60+$2} NF==1{print $1+0}' <<<"$FUGAKU_ELAPSE")

echo "======================================================"
echo " 富岳バッチ掃引: $ROUND  budget=${BUDGET}s  objective=$OBJECTIVE"
echo " configs=$(grep -vc '^id' "$CONFIGS") 構成  elapse=$FUGAKU_ELAPSE (${ELAPSE_SEC}s)"
echo "======================================================"

# [1] sync + build (src/Makefile → build/fugaku/*)
"$SCRIPT_DIR/fugaku-sync.sh" "$BUDGET"

# [2] tune-sweep.sh と configs.tsv を富岳へ送付
ssh "$FUGAKU_HOST" "mkdir -p $FUGAKU_REMOTE_DIR/tools $FUGAKU_REMOTE_DIR/results/tune/$ROUND"
rsync -avz "$SCRIPT_DIR/tune-sweep.sh"  "$FUGAKU_HOST:$FUGAKU_REMOTE_DIR/tools/"
rsync -avz "$LOCAL_RDIR/configs.tsv"    "$FUGAKU_HOST:$FUGAKU_REMOTE_DIR/results/tune/$ROUND/configs.tsv"
# 入力ファイル (solver が stdin から読む課題用)。無ければ /dev/null。
REMOTE_INPUT="/dev/null"
if [ -n "$INPUT" ]; then
    [ -f "$INPUT" ] || { echo "ERROR: 入力ファイルが無い: $INPUT"; exit 1; }
    rsync -avz "$INPUT" "$FUGAKU_HOST:$FUGAKU_REMOTE_DIR/results/tune/$ROUND/input.dat"
    REMOTE_INPUT="$FUGAKU_REMOTE_DIR/results/tune/$ROUND/input.dat"
fi

# opt-in な PJM ノブ / module (config 未設定なら空 → 生成ジョブは現状と一致=ゼロ回帰)。
# submit と同じ式で算出し、単発 submit と tune の実行環境を揃える。
PJM_LLIO="";  [ -n "${FUGAKU_LLIO_VOL:-}" ]   && PJM_LLIO="#PJM -x PJM_LLIO_GFSCACHE=${FUGAKU_LLIO_VOL}"
PJM_FREQ="";  [ -n "${FUGAKU_FREQ:-}" ]       && PJM_FREQ="#PJM -L \"freq=${FUGAKU_FREQ}\""
PJM_THR="";   [ -n "${FUGAKU_THROTTLING:-}" ] && PJM_THR="#PJM -L \"throttling_state=${FUGAKU_THROTTLING}\""
PJM_SPATH=""; [ -n "${FUGAKU_SPATH:-}" ]      && PJM_SPATH="#PJM --spath \"${FUGAKU_SPATH}\""
MODLOAD_JOB=""; [ -n "${FUGAKU_MODULES:-}" ]  && MODLOAD_JOB="module load ${FUGAKU_MODULES}"

# [3] テンプレのトークンを埋めてジョブ生成
JOB=$(sed \
  -e "s|__RSCGRP__|${FUGAKU_RSCGRP}|g" \
  -e "s|__NODE__|${FUGAKU_NODE_COUNT}|g" \
  -e "s|__RANKS__|${FUGAKU_MPI_RANKS}|g" \
  -e "s|__ELAPSE__|${FUGAKU_ELAPSE}|g" \
  -e "s|__ELAPSE_SEC__|${ELAPSE_SEC}|g" \
  -e "s|__GROUP__|${FUGAKU_GROUP}|g" \
  -e "s|__REMOTE_DIR__|${FUGAKU_REMOTE_DIR}|g" \
  -e "s|__ROUND__|${ROUND}|g" \
  -e "s|__BUDGET__|${BUDGET}|g" \
  -e "s|__INPUT__|${REMOTE_INPUT}|g" \
  -e "s|__PJM_LLIO__|${PJM_LLIO}|g" \
  -e "s|__PJM_FREQ__|${PJM_FREQ}|g" \
  -e "s|__PJM_THR__|${PJM_THR}|g" \
  -e "s|__PJM_SPATH__|${PJM_SPATH}|g" \
  -e "s|__MODLOAD__|${MODLOAD_JOB}|g" \
  "$REPO_ROOT/jobs/tune.pjm.template")

# [4] 投入 → JOBID
TMP_JOB="/tmp/supercon_tune_$$.job"
SUBMIT_OUT=$(echo "$JOB" | ssh "$FUGAKU_HOST" "cat > $TMP_JOB && pjsub $TMP_JOB && rm -f $TMP_JOB" 2>&1)
echo "$SUBMIT_OUT"
JOBID=$(echo "$SUBMIT_OUT" | grep -oP '(?<=Job )\d+' | head -1)
[ -z "$JOBID" ] && { echo "ERROR: JOBID 取得失敗"; exit 1; }
echo "$JOBID" > "$REPO_ROOT/results/.last-jobid"
echo ">>> JOBID=$JOBID ($ROUND)"

# [5] 完了待ち
"$SCRIPT_DIR/fugaku-wait.sh" "$JOBID"

# [6] round ディレクトリ回収 (results.csv 含む)
rsync -avz "$FUGAKU_HOST:$FUGAKU_REMOTE_DIR/results/tune/$ROUND/" "$LOCAL_RDIR/"
ln -sfn "tune/$ROUND" "$REPO_ROOT/results/latest-tune"

# [7] incumbent 更新
echo ""
echo "--- results.csv ---"; cat "$LOCAL_RDIR/results.csv" 2>/dev/null || echo "(results.csv なし)"
"$SCRIPT_DIR/update_incumbent.py" "$LOCAL_RDIR" --objective "$OBJECTIVE" \
  --state "$REPO_ROOT/state/incumbent.json"
echo ""
echo ">>> incumbent: state/incumbent.json / 結果: results/$ROUND/ (latest-tune)"

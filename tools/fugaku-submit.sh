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
INPUT="${3:-}"
<<<<<<< Updated upstream
FUGAKU_ELAPSE_MARGIN_SEC="${FUGAKU_ELAPSE_MARGIN_SEC:-30}"

elapse_to_sec() {
    local s="$1"
    if [[ "$s" =~ ^([0-9]+):([0-5][0-9]):([0-5][0-9])$ ]]; then
        echo $((10#${BASH_REMATCH[1]} * 3600 + 10#${BASH_REMATCH[2]} * 60 + 10#${BASH_REMATCH[3]}))
        return 0
    fi
    if [[ "$s" =~ ^([0-9]+):([0-5][0-9])$ ]]; then
        echo $((10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]}))
        return 0
    fi
    return 1
}

check_budget_elapse() {
    local budget="$1"
    local elapse="${2:-}"
    local margin="$3"
    local elapse_sec required

    if [ -z "$budget" ]; then
        echo "WARNING: BUDGET_SEC が未設定のため、PJM elapse との整合チェックをスキップします。" >&2
        return 0
    fi
    if ! [[ "$budget" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "WARNING: BUDGET_SEC を数値化できないため、PJM elapse との整合チェックをスキップします: $budget" >&2
        return 0
    fi
    if [ -z "$elapse" ]; then
        echo "WARNING: FUGAKU_ELAPSE が未設定のため、PJM elapse との整合チェックをスキップします。" >&2
        return 0
    fi
    if ! elapse_sec=$(elapse_to_sec "$elapse"); then
        echo "WARNING: FUGAKU_ELAPSE を秒換算できないため、PJM elapse との整合チェックをスキップします: $elapse" >&2
        return 0
    fi
    if ! [[ "$margin" =~ ^[0-9]+$ ]]; then
        echo "WARNING: FUGAKU_ELAPSE_MARGIN_SEC を数値化できないため、PJM elapse との整合チェックをスキップします: $margin" >&2
        return 0
    fi

    required=$(awk -v b="$budget" -v m="$margin" 'BEGIN { s = b + m; printf "%d", int(s) + (s > int(s)) }')
    if [ "$required" -gt "$elapse_sec" ]; then
        echo "ERROR: 実行予算が PJM elapse を超えています。BUDGET_SEC=${budget}s + 余裕マージン=${margin}s = ${required}s, FUGAKU_ELAPSE=${elapse} (${elapse_sec}s)。BUDGET_SEC を下げるか FUGAKU_ELAPSE を延ばしてください。" >&2
        exit 1
    fi
}

check_budget_elapse "$BUDGET_SEC" "${FUGAKU_ELAPSE:-}" "$FUGAKU_ELAPSE_MARGIN_SEC"
=======
case "$TARGET" in stencil-blocked) TARGET=stencil_blocked ;; esac
case "$TARGET" in
  skeleton|stencil|stencil_blocked|search|contest) ;;
  *) echo "ERROR: unknown target: $TARGET (skeleton|stencil|stencil_blocked|search|contest)" >&2; exit 2 ;;
esac
>>>>>>> Stashed changes

# 実入力ファイルを remote の固定パスへ送る (JOBID は submit 後にしか分からないため
# inputs/current.dat に置き、ジョブ側で stdin にリダイレクト + 結果へ複製する)。
REMOTE_INPUT="/dev/null"
if [ -n "$INPUT" ]; then
    [ -f "$INPUT" ] || { echo "ERROR: input not found: $INPUT" >&2; exit 1; }
    ssh "$FUGAKU_HOST" "mkdir -p $FUGAKU_REMOTE_DIR/inputs" >&2
    rsync -azq "$INPUT" "$FUGAKU_HOST:$FUGAKU_REMOTE_DIR/inputs/current.dat" >&2
    REMOTE_INPUT="$FUGAKU_REMOTE_DIR/inputs/current.dat"
fi

# ソース来歴 (WSL 側で取得 → meta に埋め、結果がどのコードのものか AI が相関できる)
GIT_COMMIT=$(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo nogit)
GIT_DIRTY=$(cd "$REPO_ROOT" && git status --short 2>/dev/null | wc -l | tr -d ' ')

# opt-in な PJM ノブ / module (config 未設定なら空文字 → 生成ジョブは現状と一致=ゼロ回帰)
PJM_LLIO="";  [ -n "${FUGAKU_LLIO_VOL:-}" ]    && PJM_LLIO="#PJM -x PJM_LLIO_GFSCACHE=${FUGAKU_LLIO_VOL}"
PJM_FREQ="";  [ -n "${FUGAKU_FREQ:-}" ]        && PJM_FREQ="#PJM -L \"freq=${FUGAKU_FREQ}\""
PJM_THR="";   [ -n "${FUGAKU_THROTTLING:-}" ]  && PJM_THR="#PJM -L \"throttling_state=${FUGAKU_THROTTLING}\""
PJM_SPATH=""; [ -n "${FUGAKU_SPATH:-}" ]       && PJM_SPATH="#PJM --spath \"${FUGAKU_SPATH}\""
MODLOAD_JOB="";[ -n "${FUGAKU_MODULES:-}" ]    && MODLOAD_JOB="module load ${FUGAKU_MODULES}"

# ジョブスクリプトを動的生成 (pjsub ディレクティブは変数展開不可のためここで埋め込む)
JOB_SCRIPT=$(cat << ENDJOB
#!/bin/bash
#PJM -L rscgrp=${FUGAKU_RSCGRP}
#PJM -L node=${FUGAKU_NODE_COUNT}
#PJM --mpi "max-proc-per-node=${FUGAKU_MPI_RANKS}"
#PJM -L elapse=${FUGAKU_ELAPSE}
#PJM -g ${FUGAKU_GROUP}
#PJM -j
#PJM -S
${PJM_LLIO}
${PJM_FREQ}
${PJM_THR}
${PJM_SPATH}

# 1 ランク = 1 CMG (12 コア) に固定。これがないと 4 ランクが CMG をまたいで配置され、
# first-touch で確保した CMG ローカル HBM への局所性が崩れて帯域が出ない。
export OMP_NUM_THREADS=${FUGAKU_OMP_THREADS}
export OMP_PROC_BIND=close
export OMP_PLACES=cores
# ラージページ (TLB ミス削減: 大配列で効く)。実行環境で対応状況を初日に確認すること:
#   export XOS_MMM_L_PAGING_POLICY=demand:demand:demand
#   export XOS_MMM_L_HPAGE_TYPE=hugetlbfs

RESULTS="${FUGAKU_REMOTE_DIR}/results/\${PJM_JOBID}"
mkdir -p "\${RESULTS}"

echo "target=${TARGET} budget=${BUDGET_SEC} ranks=${FUGAKU_MPI_RANKS} threads=${FUGAKU_OMP_THREADS}" > "\${RESULTS}/meta.txt"
echo "commit=${GIT_COMMIT} dirty=${GIT_DIRTY}" >> "\${RESULTS}/meta.txt"
date -u +%Y-%m-%dT%H:%M:%SZ >> "\${RESULTS}/meta.txt"

# 実行の再現情報を保存 (どの入力・引数・環境・ジョブで出た結果か)
echo "mpiexec -n ${FUGAKU_MPI_RANKS} build/fugaku/${TARGET} < ${REMOTE_INPUT}" > "\${RESULTS}/argv.txt"
env | grep -E '^(OMP_|PJM_)' | sort > "\${RESULTS}/env.txt" 2>/dev/null || true
cp "\$0" "\${RESULTS}/job.sh" 2>/dev/null || true
if [ "${REMOTE_INPUT}" != "/dev/null" ]; then
  cp "${REMOTE_INPUT}" "\${RESULTS}/input.dat" 2>/dev/null || true
  sha256sum "${REMOTE_INPUT}" 2>/dev/null | awk '{print \$1}' > "\${RESULTS}/input.sha256" || true
fi

${MODLOAD_JOB}
# 資源計測: /usr/bin/time の -v -o が実際に動く時だけラップする。
#   存在チェックだけでは BSD time 等で -v 不明 → ラップ失敗 → ソルバ未実行で本番ジョブが死ぬ。
#   probe (true で試す) に通った時だけ採用。ダメなら素通り=本計算を絶対に壊さない。
TIMED=""
if /usr/bin/time -v -o /dev/null true >/dev/null 2>&1; then
  TIMED="/usr/bin/time -v -o \${RESULTS}/resource.txt"
fi
START=\$(date +%s)
\${TIMED} mpiexec -n ${FUGAKU_MPI_RANKS} \\
  "${FUGAKU_REMOTE_DIR}/build/fugaku/${TARGET}" \\
  < "${REMOTE_INPUT}" > "\${RESULTS}/stdout.txt" 2> "\${RESULTS}/stderr.txt"
EXIT_CODE=\$?
WALL=\$(( \$(date +%s) - START ))

echo "\${EXIT_CODE}" > "\${RESULTS}/exit_code.txt"
# status.txt は「正常完了の印」。PJM に kill されるとここに到達せず=未完を示す。
echo "completed exit=\${EXIT_CODE} wall_sec=\${WALL}" > "\${RESULTS}/status.txt"
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

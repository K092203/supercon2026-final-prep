#!/usr/bin/env bash
# =====================================================================
# tune-local.sh — ローカル通しリハ (富岳経路の予行演習)
#   configs.tsv → 掃引 → results.csv → incumbent の全経路を、富岳と同一の
#   tools/tune-sweep.sh で回す。launcher=mpirun / bindir=build/mpi だけが違う。
#   → 本選前は実機が無いので、ここで経路のバグを全部出しておく。
#
# 使い方:
#   tools/tune-local.sh <configs.tsv> [budget_sec] [objective] [elapse_sec] [input_file]
#     budget_sec : ソルバ 1 回の予算 (既定 2。ローカルは短く)
#     objective  : min-elapsed(既定) | max-score | score-per-sec
#     elapse_sec : 掃引全体の壁時計上限 (既定 600。anytime 打切り判定)
#     input_file : solver が stdin から問題入力を読む場合に渡す (既定: 入力なし)
# 要 OpenMPI: sudo apt-get install -y openmpi-bin libopenmpi-dev
# =====================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

CONFIGS="${1:?usage: tune-local.sh <configs.tsv> [budget_sec] [objective] [elapse_sec] [input_file]}"
BUDGET="${2:-2}"
OBJECTIVE="${3:-min-elapsed}"
ELAPSE="${4:-600}"
INPUT="${5:-/dev/null}"
[ -f "$CONFIGS" ] || { echo "ERROR: configs が無い: $CONFIGS"; exit 1; }

echo "== build local-mpi (build/mpi/*) =="
make local-mpi >/dev/null 2>&1 || { echo "ERROR: make local-mpi 失敗 (OpenMPI 要)"; exit 1; }

ROUND="round-local"
RDIR="results/tune/$ROUND"
mkdir -p "$RDIR"
cp "$CONFIGS" "$RDIR/configs.tsv"

echo "== sweep (launcher=mpirun, bindir=build/mpi, budget=${BUDGET}s) =="
SWEEP_RC=0
bash "$SCRIPT_DIR/tune-sweep.sh" \
  "$RDIR/configs.tsv" "$RDIR/results.csv" \
  "mpirun --oversubscribe" "build/mpi" "$BUDGET" "$ELAPSE" "$INPUT" || SWEEP_RC=$?
# tune-sweep が非ゼロで終わるのは致命的設定エラー(重複id等)のみ → 失敗を伝播して中断。
# (anytime な部分掃引は tune-sweep 内で rc=0。ここに来るのは「測れていない」失敗のみ)
if [ "$SWEEP_RC" -ne 0 ]; then
  echo "❌ tune-sweep が rc=$SWEEP_RC で失敗 (重複id/設定エラー等)。incumbent 更新せず終了。"
  exit "$SWEEP_RC"
fi

echo ""
echo "--- results.csv ---"
cat "$RDIR/results.csv"
echo ""
"$SCRIPT_DIR/update_incumbent.py" "$RDIR" --objective "$OBJECTIVE" --state state/incumbent.json
echo ""
echo ">>> incumbent: state/incumbent.json"
cat state/incumbent.json 2>/dev/null || echo "(incumbent 未更新)"

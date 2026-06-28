#!/usr/bin/env bash
# =====================================================================
# check-mpi.sh — 富岳へ投げる前にローカル 4 ランクで MPI 経路を検証する
#   富岳キューを消費せずに以下のバグを事前に潰すのが目的:
#     - stencil : ハロ交換 (Irecv/Isend) の領域分割境界の誤り
#     - skeleton: MPI_Allreduce の集約漏れ
#     - search  : MPI_MAXLOC + Bcast のデッドロック / データ型不一致
#
# 要 OpenMPI:  sudo apt-get install -y openmpi-bin libopenmpi-dev
# 使い方:      make test-mpi   (または bash tools/check-mpi.sh)
# =====================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"

if ! command -v mpic++ >/dev/null || ! command -v mpirun >/dev/null; then
    echo "ERROR: OpenMPI が見つかりません。"
    echo "  sudo apt-get install -y openmpi-bin libopenmpi-dev"
    exit 1
fi

# root 実行時 (コンテナ等) は --allow-run-as-root が要る。ローカル不足コア用に --oversubscribe。
ROOTFLAG=""; [ "$(id -u)" = "0" ] && ROOTFLAG="--allow-run-as-root"
MPIRUN="mpirun --oversubscribe $ROOTFLAG"
FLAGS="-std=c++17 -O2 -fopenmp -DUSE_MPI -Isrc"
export OMP_NUM_THREADS=2   # ローカルはコアが少ないのでランクあたり 2 スレッド

mkdir -p build/mpi
echo "== compiling (mpic++) =="
# stencil は 200 steps を必ず完了させたいので予算を大きく、計測系は短く
mpic++ $FLAGS -DBUDGET_SEC=120 src/stencil.cpp         -o build/mpi/stencil         || exit 1
mpic++ $FLAGS -DBUDGET_SEC=120 src/stencil_blocked.cpp -o build/mpi/stencil_blocked || exit 1
mpic++ $FLAGS -DBUDGET_SEC=3   src/skeleton.cpp        -o build/mpi/skeleton        || exit 1
mpic++ $FLAGS -DBUDGET_SEC=3   src/search.cpp          -o build/mpi/search          || exit 1

extract3(){ # 出力文字列 → "sum sumsq chk"
  printf '%s %s %s' \
    "$(grep -oP 'sum=\K[0-9.eE+-]+'   <<<"$1")" \
    "$(grep -oP 'sumsq=\K[0-9.eE+-]+' <<<"$1")" \
    "$(grep -oP 'chk=\K[0-9.eE+-]+'   <<<"$1")"
}
close3(){ # "$1"=3値 "$2"=3値、全要素 相対誤差<1e-3 なら exit 0
  python3 - "$1" "$2" <<'PY'
import sys
a, b = sys.argv[1].split(), sys.argv[2].split()
if len(a) != 3 or len(b) != 3: sys.exit(1)
for x, y in zip(a, b):
    try: fx, fy = float(x), float(y)
    except ValueError: sys.exit(1)
    if abs(fx - fy) / max(abs(fx), 1e-30) >= 1e-3: sys.exit(1)
sys.exit(0)
PY
}

FAIL=0

echo ""
echo "== [1/4] stencil: ハロ交換の正しさ (n=1 と n=4 の最終 sum/sumsq/chk 一致) =="
O1=$($MPIRUN -n 1 build/mpi/stencil)
O4=$($MPIRUN -n 4 build/mpi/stencil)
V1=$(extract3 "$O1")
V4=$(extract3 "$O4")
ST1=$(grep -oP 'steps=\K[0-9]+/[0-9]+' <<<"$O1")
ST4=$(grep -oP 'steps=\K[0-9]+/[0-9]+' <<<"$O4")
echo "  n=1: sum/sumsq/chk=$V1 steps=$ST1"
echo "  n=4: sum/sumsq/chk=$V4 steps=$ST4"
if [ -n "$V1" ] && close3 "$V1" "$V4"; then
    echo "  [PASS] ハロ交換 OK (分割数によらず結果が一致)"
else
    echo "  [FAIL] sum/sumsq/chk 不一致 → ハロ交換 / 領域分割にバグ"; FAIL=1
fi

echo ""
echo "== [2/4] stencil_blocked: 温度ブロッキングが plain と一致するか (n=4) =="
OB=$($MPIRUN -n 4 build/mpi/stencil_blocked)
VB=$(extract3 "$OB")
echo "  plain n=4 sum/sumsq/chk=$V4 / blocked n=4 sum/sumsq/chk=$VB"
if close3 "$V4" "$VB"; then
    echo "  [PASS] 温度ブロッキング OK (plain と同一結果)"
else
    echo "  [FAIL] blocked が plain と不一致 → タイル/deep-halo にバグ"; FAIL=1
fi

echo ""
echo "== [3/4] skeleton: MPI_Allreduce (n=4 で台数効果 ~4x) =="
C1=$($MPIRUN -n 1 build/mpi/skeleton | grep -oP 'in_circle=\K[0-9]+')
C4=$($MPIRUN -n 4 build/mpi/skeleton | grep -oP 'in_circle=\K[0-9]+')
echo "  n=1: count=$C1"
echo "  n=4: count=$C4"
if [ -n "$C1" ] && [ -n "$C4" ] && [ "$C4" -gt "$C1" ]; then
    echo "  [PASS] Allreduce OK (4 ランク分が集約されている)"
else
    echo "  [FAIL] Allreduce 異常 (集約漏れ or クラッシュ)"; FAIL=1
fi

echo ""
echo "== [4/4] search: MPI_MAXLOC + Bcast (n=4 デッドロックせず result.txt 出力) =="
rm -f result.txt
OS=$($MPIRUN -n 4 build/mpi/search)
echo "  $OS"
if [ -f result.txt ] && grep -q 'best=' <<<"$OS"; then
    echo "  [PASS] MAXLOC+Bcast OK (全体ベスト同期 + 出力成功)"
else
    echo "  [FAIL] MAXLOC/Bcast 異常 (デッドロック or 出力なし)"; FAIL=1
fi
rm -f result.txt

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "✅ ALL PASS — MPI 経路は健全。富岳へ投入可能。"
else
    echo "❌ FAILURES あり (上記 [FAIL] を参照)。富岳投入前に修正すること。"
fi
exit $FAIL

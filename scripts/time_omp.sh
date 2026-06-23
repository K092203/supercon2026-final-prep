#!/usr/bin/env bash
# time_omp.sh — OMP_NUM_THREADS 別ベンチマーク
# 使い方: scripts/time_omp.sh [入力ファイル] [制限秒数] [スレッド数リスト...]
#   例: scripts/time_omp.sh tests/sample_01.in 5 1 2 4 8 12 24 48
#   省略時: 1 2 4 8 12 を計測
set -euo pipefail

INPUT="${1:-tests/sample_01.in}"
BUDGET="${2:-5}"
shift 2 2>/dev/null || true
THREADS="${*:-1 2 4 8 12}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p build

echo "[time_omp] Building src/main.cpp (BUDGET_SEC=$BUDGET, -O2) ..."
g++ -std=c++17 -O2 -fopenmp -Isrc \
    -DBUDGET_SEC="$BUDGET" \
    src/main.cpp -o build/contest_bench

echo ""
printf "%-12s  %-12s  %-20s\n" "OMP_THREADS" "Elapsed(s)" "Stderr"
printf -- "%-12s  %-12s  %-20s\n" "-----------" "----------" "------"

for NTH in $THREADS; do
    START=$(date +%s%N 2>/dev/null || echo 0)
    STDERR=$(OMP_NUM_THREADS="$NTH" \
             OMP_PROC_BIND=close \
             OMP_PLACES=cores \
             ./build/contest_bench < "$INPUT" 2>&1 1>/dev/null)
    END=$(date +%s%N 2>/dev/null || echo 0)
    if [ "$START" != "0" ] && [ "$END" != "0" ]; then
        ELAPSED=$(awk "BEGIN{printf \"%.3f\", ($END-$START)/1e9}")
    else
        ELAPSED="N/A"
    fi
    # stderr の最後の行 (性能情報) を抜き出す
    LAST=$(echo "$STDERR" | tail -1)
    printf "%-12s  %-12s  %-20s\n" "$NTH" "$ELAPSED" "$LAST"
done

echo ""
echo "[time_omp] 富岳本番 (A64FX 4CMG 48core) での推奨: OMP_NUM_THREADS=12 (4ランク×12スレッド)"

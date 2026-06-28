#!/usr/bin/env bash
# time_omp.sh — OMP_NUM_THREADS 別ベンチマーク
# 使い方: scripts/time_omp.sh [target] [入力ファイル] [制限秒数] [スレッド数リスト...]
#   例: scripts/time_omp.sh contest tests/sample_01.in 5 1 2 4 8 12 24 48
#   省略時: target=contest / threads= 1 2 4 8 12 (src/main.cpp は廃止)
set -euo pipefail

TARGET="${1:-contest}"
INPUT="${2:-tests/sample_01.in}"
BUDGET="${3:-5}"
shift 3 2>/dev/null || true
THREADS="${*:-1 2 4 8 12}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -f "src/$TARGET.cpp" ] || { echo "ERROR: src/$TARGET.cpp が無い (target=$TARGET)"; exit 1; }

mkdir -p build
BIN="build/${TARGET}_bench"

echo "[time_omp] Building src/$TARGET.cpp (BUDGET_SEC=$BUDGET, -O2) ..."
g++ -std=c++17 -O2 -fopenmp -Isrc \
    -DBUDGET_SEC="$BUDGET" \
    "src/$TARGET.cpp" -o "$BIN"

echo ""
printf "%-12s  %-12s  %-20s\n" "OMP_THREADS" "Elapsed(s)" "Stderr"
printf -- "%-12s  %-12s  %-20s\n" "-----------" "----------" "------"

for NTH in $THREADS; do
    START=$(date +%s%N 2>/dev/null || echo 0)
    STDERR=$(OMP_NUM_THREADS="$NTH" \
             OMP_PROC_BIND=close \
             OMP_PLACES=cores \
             "$BIN" < "$INPUT" 2>&1 1>/dev/null)
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

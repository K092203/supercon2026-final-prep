#!/usr/bin/env bash
# runner.sh — 高速ローカルテストランナー
# 使い方: tools/runner.sh [target] [入力ファイル] [制限秒数]
#   例: tools/runner.sh contest tests/sample_01.in 5
#
# 動作:
#   1. src/<target>.cpp をビルド (既定 contest。src/main.cpp は廃止済)
#   2. 指定入力で実行 (OMP_NUM_THREADS は CPU コア数を使用)
#   3. 実行時間と出力の先頭を表示
set -euo pipefail

TARGET="${1:-contest}"
INPUT="${2:-tests/sample_01.in}"
BUDGET="${3:-5}"
NTH="${OMP_NUM_THREADS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -f "src/$TARGET.cpp" ] || { echo "ERROR: src/$TARGET.cpp が無い (target=$TARGET)"; exit 1; }

mkdir -p build

echo "[runner] Building src/$TARGET.cpp (BUDGET_SEC=$BUDGET)..."
g++ -std=c++17 -O2 -fopenmp -Isrc \
    -DBUDGET_SEC="$BUDGET" \
    "src/$TARGET.cpp" -o "build/$TARGET"

echo "[runner] Running build/$TARGET with input=$INPUT OMP_NUM_THREADS=$NTH"
START=$(date +%s%N 2>/dev/null || echo 0)

OMP_NUM_THREADS="$NTH" \
OMP_PROC_BIND=close \
OMP_PLACES=cores \
    "./build/$TARGET" < "$INPUT" 2>&1 | tee /tmp/runner_out.txt

END=$(date +%s%N 2>/dev/null || echo 0)
if [ "$START" != "0" ] && [ "$END" != "0" ]; then
    ELAPSED_MS=$(( (END - START) / 1000000 ))
    echo "[runner] elapsed=${ELAPSED_MS}ms"
fi

echo "[runner] done. stdout preview:"
head -3 /tmp/runner_out.txt

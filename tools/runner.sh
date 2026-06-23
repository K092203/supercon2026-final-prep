#!/usr/bin/env bash
# runner.sh — 高速ローカルテストランナー
# 使い方: tools/runner.sh [入力ファイル] [制限秒数]
#   例: tools/runner.sh tests/sample_01.in 5
#
# 動作:
#   1. src/main.cpp をビルド
#   2. 指定入力で実行 (OMP_NUM_THREADS は CPU コア数を使用)
#   3. 実行時間と出力の先頭を表示
set -euo pipefail

INPUT="${1:-tests/sample_01.in}"
BUDGET="${2:-5}"
NTH="${OMP_NUM_THREADS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p build

echo "[runner] Building src/main.cpp (BUDGET_SEC=$BUDGET)..."
g++ -std=c++17 -O2 -fopenmp -Isrc \
    -DBUDGET_SEC="$BUDGET" \
    src/main.cpp -o build/contest

echo "[runner] Running with input=$INPUT OMP_NUM_THREADS=$NTH"
START=$(date +%s%N 2>/dev/null || echo 0)

OMP_NUM_THREADS="$NTH" \
OMP_PROC_BIND=close \
OMP_PLACES=cores \
    ./build/contest < "$INPUT" 2>&1 | tee /tmp/runner_out.txt

END=$(date +%s%N 2>/dev/null || echo 0)
if [ "$START" != "0" ] && [ "$END" != "0" ]; then
    ELAPSED_MS=$(( (END - START) / 1000000 ))
    echo "[runner] elapsed=${ELAPSED_MS}ms"
fi

echo "[runner] done. stdout preview:"
head -3 /tmp/runner_out.txt

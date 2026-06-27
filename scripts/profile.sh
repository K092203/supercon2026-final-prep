#!/usr/bin/env bash
# profile.sh — gprof / perf によるプロファイリング自動化
# 使い方: scripts/profile.sh [target] [入力ファイル] [方法: gprof|perf|valgrind]
#   例: scripts/profile.sh contest tests/sample_01.in gprof  (src/main.cpp は廃止)
set -euo pipefail

TARGET="${1:-contest}"
INPUT="${2:-tests/sample_01.in}"
METHOD="${3:-gprof}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -f "src/$TARGET.cpp" ] || { echo "ERROR: src/$TARGET.cpp が無い (target=$TARGET)"; exit 1; }

mkdir -p build/prof

case "$METHOD" in
  gprof)
    echo "[profile] Building with -pg ..."
    g++ -std=c++17 -O2 -fopenmp -pg -Isrc \
        "src/$TARGET.cpp" -o build/prof/contest_pg
    echo "[profile] Running ..."
    OMP_NUM_THREADS=1 ./build/prof/contest_pg < "$INPUT" > /dev/null 2>&1 || true
    gprof build/prof/contest_pg gmon.out > build/prof/gprof_report.txt
    echo "[profile] Report: build/prof/gprof_report.txt"
    head -40 build/prof/gprof_report.txt
    ;;

  perf)
    echo "[profile] Building with -g -fno-omit-frame-pointer ..."
    g++ -std=c++17 -O2 -fopenmp -g -fno-omit-frame-pointer -Isrc \
        "src/$TARGET.cpp" -o build/prof/contest_perf
    echo "[profile] Running with perf stat ..."
    OMP_NUM_THREADS="$(nproc)" \
    perf stat -e cache-misses,cache-references,instructions,cycles,branch-misses \
        ./build/prof/contest_perf < "$INPUT" > /dev/null 2>&1
    ;;

  valgrind)
    echo "[profile] Building with -g -O1 ..."
    g++ -std=c++17 -O1 -fopenmp -g -Isrc \
        "src/$TARGET.cpp" -o build/prof/contest_vg
    echo "[profile] Running with callgrind (OMP_NUM_THREADS=1) ..."
    OMP_NUM_THREADS=1 \
    valgrind --tool=callgrind --callgrind-out-file=build/prof/callgrind.out \
        ./build/prof/contest_vg < "$INPUT" > /dev/null 2>&1
    echo "[profile] Report: build/prof/callgrind.out"
    echo "          Visualize with: kcachegrind build/prof/callgrind.out"
    ;;

  *)
    echo "Unknown method: $METHOD (gprof|perf|valgrind)"
    exit 1
    ;;
esac

#!/usr/bin/env bash
# =====================================================================
# day1-smoke.sh — 本選 Day1 の最初に走らせる一括健全性確認
#   課題を読み始める前に「環境破損・toolchain 不足・コード構文崩れ」を分離して炙り出す。
# 使い方: bash tools/day1-smoke.sh
# =====================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"; cd "$ROOT"
FAIL=0
step(){ echo ""; echo "== $* =="; }

step "make clean && make contest"
make clean >/dev/null 2>&1
if make contest >/tmp/d1_make.log 2>&1; then echo "[OK] contest build"; else echo "[FAIL] contest build"; tail -20 /tmp/d1_make.log; FAIL=1; fi

step "judge (tests/)"
if [ -x build/contest ]; then bash tests/judge.sh tests || { echo "[FAIL] judge"; FAIL=1; }; else echo "[SKIP] build/contest なし"; fi

step "python compile (tools/*.py)"
if python3 -m py_compile tools/*.py 2>/tmp/d1_py.log; then echo "[OK] py_compile"; else echo "[FAIL] py_compile"; cat /tmp/d1_py.log; FAIL=1; fi

step "shell syntax (bash -n)"
ok=1
for f in tools/*.sh scripts/*.sh tests/*.sh; do
  [ -f "$f" ] || continue
  bash -n "$f" || { echo "[FAIL] $f"; ok=0; FAIL=1; }
done
[ "$ok" = 1 ] && echo "[OK] 全 .sh 構文"

step "MPI local smoke (任意)"
if command -v mpic++ >/dev/null && command -v mpirun >/dev/null; then
  make test-mpi || { echo "[FAIL] test-mpi"; FAIL=1; }
else
  echo "[WARN] mpic++/mpirun なし → MPI スモークを skip (WSL/Linux では本選前に確認すること)"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then echo "✅ day1-smoke ALL OK — 課題に着手してよい"; else echo "❌ day1-smoke で問題あり (上記 [FAIL] を確認)"; fi
exit "$FAIL"

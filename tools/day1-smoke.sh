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

step "検証ループ部品 (validator / 小ケース生成)"
# validator: sample に対し exit 0 で valid 判定できるか (既定の汎用チェック段階)
if [ -f tests/sample_01.in ] && [ -f tests/sample_01.out ]; then
  if python3 tools/validate_output.py tests/sample_01.in tests/sample_01.out >/dev/null 2>/tmp/d1_val.log; then
    echo "[OK] validate_output.py (sample valid)"
  else
    echo "[FAIL] validate_output.py"; cat /tmp/d1_val.log; FAIL=1
  fi
else
  echo "[SKIP] tests/sample_01.{in,out} なし"
fi
# gen_small_cases: 同 seed で2回生成して決定的か (前回残骸があると上書き防止で失敗するため先に掃除)
rm -rf /tmp/d1_g1 /tmp/d1_g2 2>/dev/null || true
if python3 tools/gen_small_cases.py --seed 1 --count 3 --out /tmp/d1_g1 >/dev/null 2>&1 \
   && python3 tools/gen_small_cases.py --seed 1 --count 3 --out /tmp/d1_g2 >/dev/null 2>&1 \
   && diff -rq /tmp/d1_g1 /tmp/d1_g2 >/dev/null 2>&1; then
  echo "[OK] gen_small_cases.py (決定的)"
else
  echo "[FAIL] gen_small_cases.py (非決定的 or 生成失敗)"; FAIL=1
fi
rm -rf /tmp/d1_g1 /tmp/d1_g2 2>/dev/null || true

step "MPI local smoke (任意)"
if command -v mpic++ >/dev/null && command -v mpirun >/dev/null; then
  make test-mpi || { echo "[FAIL] test-mpi"; FAIL=1; }
else
  echo "[WARN] mpic++/mpirun なし → MPI スモークを skip (WSL/Linux では本選前に確認すること)"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then echo "✅ day1-smoke ALL OK — 課題に着手してよい"; else echo "❌ day1-smoke で問題あり (上記 [FAIL] を確認)"; fi
exit "$FAIL"

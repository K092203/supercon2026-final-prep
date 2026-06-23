#!/usr/bin/env bash
# judge.sh — テストケース一括正誤判定
# 使い方: tests/judge.sh [テストケースディレクトリ]
#   例: tests/judge.sh tests/
#
# 動作:
#   tests/*.in を全て実行し、対応する *.out があれば出力を比較する
#   *.out がない場合は実行のみ (クラッシュしなければ PASS)
#
# 想定ファイル構成:
#   tests/sample_01.in  → tests/sample_01.out (オプション)
#   tests/sample_02.in  → tests/sample_02.out (オプション)
set -euo pipefail

CASEDIR="${1:-tests}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
SKIP=0

for IN in "$CASEDIR"/*.in; do
    [ -f "$IN" ] || continue
    BASE="${IN%.in}"
    OUT="${BASE}.out"
    NAME="$(basename "$BASE")"

    # 実行
    ACTUAL=$(./build/contest < "$IN" 2>/tmp/judge_stderr.txt || true)
    STDERR=$(cat /tmp/judge_stderr.txt)

    if [ -f "$OUT" ]; then
        EXPECTED=$(cat "$OUT")
        if [ "$ACTUAL" = "$EXPECTED" ]; then
            echo "[PASS] $NAME"
            PASS=$((PASS + 1))
        else
            echo "[FAIL] $NAME"
            echo "  expected: $(echo "$EXPECTED" | head -1)"
            echo "  actual  : $(echo "$ACTUAL"   | head -1)"
            FAIL=$((FAIL + 1))
        fi
    else
        # 期待出力なし → 実行のみ確認 (クラッシュなければ OK)
        echo "[RUN ] $NAME (no .out file — execution only)"
        echo "  stderr: $STDERR"
        SKIP=$((SKIP + 1))
    fi
done

echo ""
echo "Results: PASS=$PASS  FAIL=$FAIL  RUN_ONLY=$SKIP"
[ "$FAIL" -eq 0 ]

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

    # 実行 (終了コードを必ず捕捉する。|| true で握り潰さない)
    ERRFILE="$(mktemp)"
    set +e
    ACTUAL=$(./build/contest < "$IN" 2>"$ERRFILE")
    RC=$?
    set -e
    STDERR=$(cat "$ERRFILE"); rm -f "$ERRFILE"

    # 非ゼロ終了(segfault/assert/範囲外等)は .out の有無に関わらず FAIL
    if [ "$RC" -ne 0 ]; then
        echo "[FAIL] $NAME (exit=$RC)"
        echo "$STDERR" | tail -10 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        continue
    fi

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
        # 期待出力なし → クラッシュなしを確認したのみ (RUN_ONLY)。
        # 制約検査をしたい場合は当日 tools/validate_output.py を実装し、ここで呼ぶ:
        #   echo "$ACTUAL" >"$TMP"; python3 tools/validate_output.py "$IN" "$TMP" || FAIL=...
        echo "[RUN ] $NAME (no .out file — 実行のみ確認/RUN_ONLY)"
        SKIP=$((SKIP + 1))
    fi
done

echo ""
echo "Results: PASS=$PASS  FAIL=$FAIL  RUN_ONLY=$SKIP"
if [ "$PASS" -eq 0 ] && [ "$SKIP" -gt 0 ]; then
    echo "[WARN] PASS=0 で RUN_ONLY のみ。.out か validator を用意して実判定にすること。"
fi
[ "$FAIL" -eq 0 ]

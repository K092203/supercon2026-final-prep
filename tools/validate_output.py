#!/usr/bin/env python3
# =====================================================================
# validate_output.py — 出力の「形式・制約」検査 + スコア計算の雛形
#   完全一致テスト(judge.sh)では拾えない、最適化/構築系課題向け:
#   「制約を満たすか」「提出可能な形式か」を検査し、score を出す。
#
#   使い方:
#     python3 tools/validate_output.py <input_file> <output_file>
#     exit 0 = valid (stdout に "score=<値>")、exit 1 = invalid (理由を stderr)
#
#   ⚠️ 本選当日に read_input / parse_output / 制約・score を problem 固有に書き換える。
#      下記は「枠」と最低限の汎用チェック(空出力・非数値トークン・debug混入)だけ。
# =====================================================================
import sys


def fail(msg):
    print(f"INVALID: {msg}", file=sys.stderr)
    sys.exit(1)


def read_tokens(path):
    with open(path, encoding="utf-8") as f:
        return f.read().split()


def main():
    if len(sys.argv) != 3:
        print("usage: validate_output.py <input_file> <output_file>", file=sys.stderr)
        sys.exit(2)
    in_path, out_path = sys.argv[1], sys.argv[2]

    in_tokens = read_tokens(in_path)
    with open(out_path, encoding="utf-8") as f:
        out_text = f.read()
    out_tokens = out_text.split()

    # ---- 汎用チェック(当日 problem 固有チェックに置き換え/追記する) ----
    if not out_tokens:
        fail("出力が空")
    # debug 出力の混入検知 (代表的な単語。課題に応じて調整)
    for bad in ("DEBUG", "debug", "TODO", "nan", "inf", "[search]", "[stencil]", "#TUNE"):
        if bad in out_text:
            fail(f"出力に不正トークン混入: {bad!r}")

    # ---- ここから problem 固有 (当日記述) ----
    # 例:
    #   n = int(in_tokens[0])
    #   ans = [int(t) for t in out_tokens]          # 形式 parse
    #   if len(ans) != n: fail(f"行数不一致 {len(ans)}!={n}")
    #   if any(not (0 <= x < n) for x in ans): fail("index 範囲外")
    #   score = compute_score(in_tokens, ans)       # 制約満たすか + スコア
    # 既定(未実装)では形式が空でなければ valid 扱い、score は出さない。
    score = None

    # ---- 結果出力 ----
    if score is not None:
        print(f"score={score}")
    else:
        print("score=NA (problem 固有の検査/採点は未実装。tools/validate_output.py を編集)")
    sys.exit(0)


if __name__ == "__main__":
    main()

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
#   ⚠️ 本選当日は下記4関数を problem 固有に書き換える(差し替え点を関数で分離済み):
#       read_input(path)        … 入力を parse して問題インスタンスを返す
#       parse_output(path)      … 出力を parse して解を返す (+ 汎用形式チェック)
#       validate(inst, ans)     … 制約を満たすか検査 (NG は fail() で exit 1)
#       score(inst, ans)        … スコアを返す (不要なら None)
#      既定は「枠」と最低限の汎用チェック(空出力・debug混入)だけ。
# =====================================================================
import argparse
import sys

# ⚠️ 当日 validate()/score() を problem 固有に実装したら True にする。
#    False の間は「雛形のまま」= 形式チェックしかしていないことを警告する(誤認防止)。
CUSTOMIZED = False

# --- デバッグ/不正トークン検知 (部分一致は誤検知するためトークン単位で判定) ---
# 単独トークンとして現れたら不正とみなすデバッグ語 ("debugger" 等は誤検知しない)
BAD_EXACT = {"DEBUG", "debug", "TODO"}
# 非有限の数値 (大文字小文字・符号ゆれを吸収。"infinite"/"nanny" は誤検知しない)
NONFINITE = {"nan", "inf", "+inf", "-inf", "infinity", "+infinity", "-infinity"}
# デバッグ行の先頭マーカー (この接頭辞で始まるトークンは混入とみなす)
BAD_PREFIXES = ("#TUNE", "[search]", "[stencil]", "[result]", "[env]")


def fail(msg):
    """検査 NG。理由を stderr に出して exit 1。"""
    print(f"INVALID: {msg}", file=sys.stderr)
    sys.exit(1)


def read_input(path):
    """入力を parse して問題インスタンスを返す。
    ⚠️ 当日: 例 `n=int(t[0]); a=list(map(int,t[1:1+n])); return {"n":n,"a":a}`。
    既定は空白区切りトークン列を返すだけ。"""
    with open(path, encoding="utf-8") as f:
        return f.read().split()


def parse_output(path):
    """出力を parse して解を返す。汎用形式チェック(空/debug混入)もここで行う。
    ⚠️ 当日: トークン列 → 整数/実数/index 列などへ変換し範囲チェック。
    既定はトークン列を返す。"""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    tokens = text.split()
    if not tokens:
        fail("出力が空")
    for tok in tokens:
        if tok in BAD_EXACT:
            fail(f"出力にデバッグトークン混入: {tok!r}")
        if tok.lower() in NONFINITE:
            fail(f"出力に非有限数値: {tok!r}")
        if tok.startswith(BAD_PREFIXES):
            fail(f"出力にデバッグ行混入: {tok!r}")
    return tokens


def validate(inst, ans):
    """制約を満たすか検査。NG は fail() で exit 1。
    ⚠️ 当日: 例 行数一致 / index 範囲 / 重複なし / 容量制約 など。
    既定は no-op(形式が空でなければ valid 扱い)。"""
    # 例:
    #   n = int(inst[0])
    #   if len(ans) != n: fail(f"行数不一致 {len(ans)}!={n}")
    #   idx = [int(x) for x in ans]
    #   if any(not (0 <= x < n) for x in idx): fail("index 範囲外")
    return


def score(inst, ans):
    """スコアを返す(大きいほど良い等は課題依存)。不要/未実装なら None。
    ⚠️ 当日: 制約を満たした上での目的関数値を計算。"""
    # 例: return compute_objective(inst, ans)
    return None


def main():
    ap = argparse.ArgumentParser(description="出力の形式/制約検査 + スコア計算 (当日 problem 固有に実装)")
    ap.add_argument("input_file")
    ap.add_argument("output_file")
    ap.add_argument("--strict", action="store_true",
                    help="雛形のまま(CUSTOMIZED=False)なら exit 3 で失敗させる(検証ループで誤認防止)")
    a = ap.parse_args()

    inst = read_input(a.input_file)
    ans = parse_output(a.output_file)   # 汎用形式チェック込み
    validate(inst, ans)                 # 制約チェック (NG は exit 1)
    s = score(inst, ans)

    # 雛形のまま使うと「形式 OK = valid」と誤認しやすいので明示的に警告する。
    if not CUSTOMIZED:
        print("WARNING: validate_output.py は雛形のままです(validate/score 未実装=形式チェックのみ)。"
              "当日 4関数を実装し CUSTOMIZED=True にしてください。", file=sys.stderr)
        if a.strict:
            print("INVALID: --strict 指定だが validator が未カスタマイズ", file=sys.stderr)
            sys.exit(3)

    if s is not None:
        print(f"score={s}")
    else:
        print("score=NA (problem 固有の検査/採点は未実装。tools/validate_output.py の4関数を編集)")
    sys.exit(0)


if __name__ == "__main__":
    main()

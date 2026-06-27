#!/usr/bin/env python3
# =====================================================================
# gen_small_cases.py — seed 固定の「小ケース」生成器 (検証ループの入口)
#   naive と fast の比較 / validator の検査 / 境界条件の確認に使う小入力を、
#   再現可能(seed 固定)に量産する。stress.py もこの gen_case() を import して共有。
#
#   使い方:
#     python3 tools/gen_small_cases.py --seed 1 --count 100 --out tests/generated
#     python3 tools/gen_small_cases.py --seed 1 --corners --out tests/generated
#     python3 tools/gen_small_cases.py --seed 1 --single > /tmp/case.in
#
#   ⚠️ 本選当日: gen_case() と corner_cases() を課題の入力形式に書き換える。
#      この file が「ケース生成ロジックの正本」(stress.py が import する)。
#   依存: Python 標準ライブラリのみ。
# =====================================================================
import argparse
import os
import random
import sys


def gen_case(rng):
    """1 ケース分の入力文字列を返す (末尾改行込み)。rng は random.Random で決定的。
    ⚠️ 当日: 課題の入力形式に合わせて書き換える。"""
    n = rng.randint(1, 8)
    a = [rng.randint(0, 10) for _ in range(n)]
    return f"{n}\n" + " ".join(map(str, a)) + "\n"


def corner_cases():
    """明示的に出したい境界ケースの (name, 入力文字列) リストを返す。
    ⚠️ 当日: 課題の境界(最小/最大近傍/全要素同値/空近傍/境界index)に合わせて書き換える。"""
    return [
        ("min",        "1\n0\n"),                 # 最小サイズ
        ("all_same",   "5\n7 7 7 7 7\n"),         # 全要素同値
        ("all_zero",   "4\n0 0 0 0\n"),           # 空に近い (全0)
        ("max_vals",   "3\n10 10 10\n"),          # 値が上限
        ("near_max_n", "8\n1 2 3 4 5 6 7 8\n"),   # 最大サイズ近傍
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--count", type=int, default=100, help="生成するランダムケース数")
    ap.add_argument("--out", default="tests/generated", help="出力ディレクトリ")
    ap.add_argument("--corners", action="store_true", help="境界ケースも出力する")
    ap.add_argument("--single", action="store_true", help="1 ケースを stdout に出して終了")
    a = ap.parse_args()

    rng = random.Random(a.seed)

    if a.single:
        sys.stdout.write(gen_case(rng))
        return

    os.makedirs(a.out, exist_ok=True)
    written = 0

    if a.corners:
        for name, case in corner_cases():
            path = os.path.join(a.out, f"seed{a.seed:06d}_corner_{name}.in")
            with open(path, "w", encoding="utf-8") as f:
                f.write(case)
            written += 1

    for i in range(a.count):
        path = os.path.join(a.out, f"seed{a.seed:06d}_case{i:03d}.in")
        with open(path, "w", encoding="utf-8") as f:
            f.write(gen_case(rng))
        written += 1

    print(f"[gen_small_cases] {written} ケースを {a.out}/ に生成 (seed={a.seed})", file=sys.stderr)


if __name__ == "__main__":
    main()

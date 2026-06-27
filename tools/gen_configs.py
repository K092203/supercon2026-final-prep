#!/usr/bin/env python3
# =====================================================================
# gen_configs.py — 探索空間(space.tsv)から configs.tsv を生成する。
#   LHS / grid で点を撒き、decode で整数・2のべきを丸め、重複構成を除去する。
#   出力は tune-sweep.sh が読む configs.tsv (id target bin ranks omp rep args)。
#   ※ これは「configs を作る側」のプラグインの一つ。将来 trustbo-gp(Rust)に
#      差し替えても、出力フォーマットが同じなら後段(掃引/incumbent)は不変。
#
# space.tsv の書式 (1 行 1 ノブ, # コメント可):
#   <name> float <low> <high>      連続値
#   <name> int   <low> <high>      整数 (最近傍へ丸め)
#   <name> pow2  <low> <high>      2 のべき集合から選ぶ (例 1..16 → {1,2,4,8,16})
#   <name> choice <v1> <v2> ...    カテゴリ (外側で列挙=2層モデルの外側)
#   name が target/bin/ranks/omp なら configs の該当列に入る (例: bin choice で
#   リビルド済みバイナリを切り替え)。それ以外は --name value として args に入る。
#
# 使い方:
#   tools/gen_configs.py spaces/search.tsv --n 6 --method lhs \
#       --target search --bin search --ranks 4 --omp 12 --rep 3 > configs.tsv
# 依存: Python 標準ライブラリのみ。
# =====================================================================
import argparse, itertools, random, sys

SPECIAL = {"target", "bin", "ranks", "omp", "rep"}   # configs の列に直接入るキー
VALID_TYPES = ("float", "int", "pow2", "choice")


def read_space(path):
    knobs = []
    with open(path, encoding="utf-8") as f:
        for lineno, ln in enumerate(f, 1):
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            p = ln.split()
            if len(p) < 2:
                sys.exit(f"[gen_configs] {path}:{lineno} name と type が必要: {ln!r}")
            name, typ, rest = p[0], p[1], p[2:]
            if typ not in VALID_TYPES:
                sys.exit(f"[gen_configs] {path}:{lineno} 未知の type '{typ}' (有効: {VALID_TYPES}): {ln!r}")
            if typ in ("float", "int", "pow2") and len(rest) < 2:
                sys.exit(f"[gen_configs] {path}:{lineno} {typ} は low high が必要: {ln!r}")
            if typ == "choice" and not rest:
                sys.exit(f"[gen_configs] {path}:{lineno} choice は値が1つ以上必要: {ln!r}")
            knobs.append((name, typ, rest))         # (name, type, rest)
    return knobs


def pow2_set(lo, hi):
    s, k = [], 1
    while k <= hi:
        if k >= lo:
            s.append(k)
        k *= 2
    return s or [max(1, int(lo))]


def decode_cont(typ, rest, u):
    """u in [0,1) を実値へ。int/pow2 は最近傍へ丸める。"""
    lo, hi = float(rest[0]), float(rest[1])
    if typ == "float":
        return f"{lo + u * (hi - lo):.6g}"
    if typ == "int":
        return str(int(round(lo + u * (hi - lo))))
    if typ == "pow2":
        s = pow2_set(lo, hi)
        return str(s[min(int(u * len(s)), len(s) - 1)])
    raise ValueError(f"unknown cont type: {typ}")


def latin_hypercube(m, d, rng):
    """m サンプル × d 次元の LHS ([0,1))。各次元を層化して 1 点ずつ。"""
    cols = []
    for _ in range(d):
        perm = list(range(m))
        rng.shuffle(perm)
        cols.append([(perm[i] + rng.random()) / m for i in range(m)])
    return [[cols[j][i] for j in range(d)] for i in range(m)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("space")
    ap.add_argument("--n", type=int, default=8, help="生成したい構成数 (目安)")
    ap.add_argument("--method", choices=["lhs", "grid"], default="lhs")
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--target", default="search")
    ap.add_argument("--bin", default="search")
    ap.add_argument("--ranks", default="4")
    ap.add_argument("--omp", default="12")
    ap.add_argument("--rep", default="3")
    a = ap.parse_args()

    rng = random.Random(a.seed)
    knobs = read_space(a.space)
    cont = [(n, t, r) for (n, t, r) in knobs if t in ("float", "int", "pow2")]
    cats = [(n, t, r) for (n, t, r) in knobs if t == "choice"]

    # カテゴリは外側で列挙 (cartesian)。連続/整数は各分岐内で LHS/grid。
    cat_lists = [[(n, v) for v in r] for (n, t, r) in cats]
    combos = list(itertools.product(*cat_lists)) if cat_lists else [()]
    per = max(1, -(-a.n // len(combos)))   # ceil(n / 分岐数)

    rows, seen = [], set()
    for combo in combos:
        if a.method == "lhs":
            samples = latin_hypercube(per, len(cont), rng)
        else:  # grid: 各連続次元を 2 水準 (両端) の cartesian
            base = list(itertools.product([0.0, 0.999999], repeat=len(cont))) if cont else [()]
            samples = [list(x) for x in base]
        for s in samples:
            row = {"target": a.target, "bin": a.bin, "ranks": a.ranks,
                   "omp": a.omp, "rep": a.rep}
            argd = {}
            for idx, (n, t, r) in enumerate(cont):
                val = decode_cont(t, r, s[idx] if idx < len(s) else 0.0)
                (row if n in SPECIAL else argd)[n] = val
            for (n, v) in combo:
                (row if n in SPECIAL else argd)[n] = v
            args = " ".join(f"--{n} {argd[n]}" for n in argd)
            key = (row["target"], row["bin"], row["ranks"], row["omp"], args)
            if key in seen:       # decode 後が同一の構成は二度測らない
                continue
            seen.add(key)
            row["args"] = args
            rows.append(row)

    print("id\ttarget\tbin\tranks\tomp\trep\targs")
    for i, row in enumerate(rows):
        print(f"{i:03d}\t{row['target']}\t{row['bin']}\t{row['ranks']}\t"
              f"{row['omp']}\t{row['rep']}\t{row['args']}")


if __name__ == "__main__":
    main()

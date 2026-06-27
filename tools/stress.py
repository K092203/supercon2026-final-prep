import subprocess
import random
import sys

# CUSTOMIZE: gen_case() を本選の課題入力形式に合わせて書き換えること。
# FAST  = build/fast (= build/skeleton のシム) — MPI なしで動く最適解
# NAIVE = build/naive — 愚直 O(N²) 実装。出力が一致するか比較する。

FAST = "./build/fast"
NAIVE = "./build/naive"

def gen_case():
    # CUSTOMIZE: 課題の入力形式に合わせてここを書き換える
    n = random.randint(1, 8)
    a = [random.randint(0, 10) for _ in range(n)]
    return str(n) + "\n" + " ".join(map(str, a)) + "\n"

def run(cmd, inp):
    # (returncode, output) を返す。timeout/クラッシュを「空出力一致で PASS」と誤判定しないため。
    try:
        res = subprocess.run(
            [cmd],
            input=inp.encode(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2
        )
    except subprocess.TimeoutExpired:
        return 124, "TIMEOUT"
    if res.returncode != 0:
        return res.returncode, res.stderr.decode().strip()
    return 0, res.stdout.decode().strip()

def main():
    for t in range(10000):
        inp = gen_case()
        rc_fast, out_fast = run(FAST, inp)
        rc_naive, out_naive = run(NAIVE, inp)

        if rc_fast != 0 or rc_naive != 0:
            print("crash/timeout at test", t, "(fast_rc", rc_fast, "naive_rc", rc_naive, ")")
            print("input:"); print(inp)
            print("fast:");  print(out_fast)
            print("naive:"); print(out_naive)
            sys.exit(1)

        if out_fast != out_naive:
            print("WA found at test", t)
            print("input:")
            print(inp)
            print("fast:")
            print(out_fast)
            print("naive:")
            print(out_naive)
            sys.exit(1)

        if t % 1000 == 0:
            print("passed", t)

    print("all passed")

if __name__ == "__main__":
    main()

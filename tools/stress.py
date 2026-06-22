import subprocess
import random
import sys

FAST = "./build/fast"
NAIVE = "./build/naive"

def gen_case():
    n = random.randint(1, 8)
    a = [random.randint(0, 10) for _ in range(n)]
    return str(n) + "\n" + " ".join(map(str, a)) + "\n"

def run(cmd, inp):
    res = subprocess.run(
        [cmd],
        input=inp.encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=2
    )
    return res.stdout.decode().strip()

def main():
    for t in range(10000):
        inp = gen_case()
        out_fast = run(FAST, inp)
        out_naive = run(NAIVE, inp)

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

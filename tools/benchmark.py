#!/usr/bin/env python3
# benchmark.py — solver の実行時間を計測する。
#   crash/timeout を「成功」と誤認しないよう returncode を検査する。
#   使い方: python3 tools/benchmark.py [--bin ./build/fast] [--case cases/sample.in]
#                                      [--repeat 10] [--timeout 10]
import argparse
import hashlib
import os
import statistics
import subprocess
import sys
import time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", default="./build/fast")
    ap.add_argument("--case", default="cases/sample.in")
    ap.add_argument("--repeat", type=int, default=10)
    ap.add_argument("--timeout", type=float, default=10.0)
    a = ap.parse_args()

    if not os.path.exists(a.case):
        print(f"{a.case} not found", file=sys.stderr)
        sys.exit(2)
    with open(a.case, "rb") as f:
        inp = f.read()

    times = []
    out_hash = None
    for _ in range(a.repeat):
        st = time.perf_counter()
        try:
            res = subprocess.run(
                [a.bin], input=inp,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=a.timeout,
            )
        except subprocess.TimeoutExpired:
            print(f"TIMEOUT (>{a.timeout}s): {a.bin}", file=sys.stderr)
            sys.exit(1)
        ed = time.perf_counter()
        if res.returncode != 0:   # crash を計測値として握り潰さない
            print(f"非ゼロ終了 rc={res.returncode}: {a.bin}", file=sys.stderr)
            print(res.stderr.decode("utf-8", "replace"), file=sys.stderr)
            sys.exit(res.returncode)
        h = hashlib.sha256(res.stdout).hexdigest()[:12]
        if out_hash is None:
            out_hash = h
        elif h != out_hash:
            print(f"[WARN] 出力が回ごとに異なる ({out_hash} vs {h})", file=sys.stderr)
        times.append(ed - st)

    times.sort()
    print(f"bin={a.bin} case={a.case} repeat={a.repeat} stdout_sha256={out_hash}")
    print(f"min={min(times):.6f} median={statistics.median(times):.6f} "
          f"avg={sum(times)/len(times):.6f} max={max(times):.6f}")


if __name__ == "__main__":
    main()

import subprocess
import time
import os

FAST = "./build/fast"
CASE = "cases/sample.in"

def main():
    if not os.path.exists(CASE):
        print(f"{CASE} not found")
        return

    with open(CASE, "rb") as f:
        inp = f.read()

    times = []

    for _ in range(10):
        st = time.perf_counter()
        subprocess.run(
            [FAST],
            input=inp,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10
        )
        ed = time.perf_counter()
        times.append(ed - st)

    print("min:", min(times))
    print("avg:", sum(times) / len(times))
    print("max:", max(times))

if __name__ == "__main__":
    main()

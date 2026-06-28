#!/usr/bin/env python3
# =====================================================================
# stress.py — fast vs naive のストレステスト (3 モード + validator 対応)
#   小ケースを量産して fast を検証する。完全一致系だけでなく、構築/最適化系
#   (正解が一意でない課題)にも使えるよう mode を選べる。
#
#   mode:
#     exact         … fast と naive の stdout が完全一致するか (一意解の課題)
#     valid-only    … fast の出力を validator が valid と判定するか (naive 不要)
#     score-compare … fast/naive 双方を validator で採点し score を比較 (naive 必要)
#
#   使い方:
#     python3 tools/stress.py --fast ./build/fast --naive ./build/naive --mode exact --cases 1000
#     python3 tools/stress.py --fast ./build/contest --validator tools/validate_output.py \
#         --mode valid-only --cases 1000 --timeout 5
#
#   ケース生成は gen_small_cases.gen_case() を共有 (正本は tools/gen_small_cases.py)。
# =====================================================================
import argparse
import os
import random
import subprocess
import sys
import tempfile

# ケース生成ロジックの正本を import (script dir を path に追加して CWD 非依存に)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_small_cases import gen_case  # noqa: E402


def run(cmd, inp, timeout):
    """(returncode, output) を返す。timeout/クラッシュを「空出力一致で PASS」と誤判定しない。"""
    try:
        res = subprocess.run(
            [cmd],
            input=inp.encode(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return 124, "TIMEOUT"
    if res.returncode != 0:
        return res.returncode, res.stderr.decode().strip()
    return 0, res.stdout.decode().strip()


TEMPLATE_RC = 3   # validate_output.py が「雛形のまま(--strict)」で返す終了コード


def run_validator(validator, inp, out, strict=False):
    """validator を (input, output) で実行。(ok, score, msg, rc) を返す。
    ok=True なら valid。score は stdout の 'score=' から抽出 (無ければ None)。
    strict=True なら validator に --strict を渡す (未カスタマイズ validator は rc=3)。"""
    with tempfile.NamedTemporaryFile("w", suffix=".in", delete=False) as fi:
        fi.write(inp); in_path = fi.name
    with tempfile.NamedTemporaryFile("w", suffix=".out", delete=False) as fo:
        fo.write(out + "\n"); out_path = fo.name
    try:
        cmd = [sys.executable, validator, in_path, out_path]
        if strict:
            cmd.append("--strict")
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        score = None
        for tok in res.stdout.decode().split():
            if tok.startswith("score="):
                score = tok[len("score="):]
        ok = (res.returncode == 0)
        msg = res.stderr.decode().strip() if not ok else ""
        return ok, score, msg, res.returncode
    finally:
        os.unlink(in_path)
        os.unlink(out_path)


def dump(t, inp, **outs):
    """失敗ケースを表示 (input と各出力)。"""
    print(f"--- 失敗 at test {t} ---")
    print("input:"); print(inp)
    for k, v in outs.items():
        print(f"{k}:"); print(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fast", default="./build/fast")
    ap.add_argument("--naive", default="./build/naive")
    ap.add_argument("--validator", default=None, help="出力検査スクリプト (valid-only/score-compare で使用)")
    ap.add_argument("--mode", choices=["exact", "valid-only", "score-compare"], default="exact")
    ap.add_argument("--cases", type=int, default=10000)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--timeout", type=float, default=2.0)
    ap.add_argument("--lenient-validator", action="store_true",
                    help="validator に --strict を渡さない(未カスタマイズの雛形 validator でも形式チェックのみで通す)")
    a = ap.parse_args()

    if a.mode in ("valid-only", "score-compare") and not a.validator:
        ap.error(f"--mode {a.mode} には --validator が必要")

    # validator を使うモードは既定で strict (未カスタマイズの雛形 validator を弾く)。
    # 雛形のまま valid-only を回すと「形式OK」を valid と誤認するため、起動時に rc=3 を1回検出して止める。
    # (rc=3 は雛形固有。カスタム済み validator はダミー出力に対し 0/1 を返すので誤検出しない)
    strict = not a.lenient_validator
    if a.validator and strict and a.mode in ("valid-only", "score-compare"):
        _, _, _, rc = run_validator(a.validator, "0\n", "0", strict=True)
        if rc == TEMPLATE_RC:
            print("ERROR: validator が未カスタマイズ(雛形)です。valid-only/score-compare は形式チェックのみで誤認します。",
                  file=sys.stderr)
            print("       validate_output.py を problem 固有に実装し CUSTOMIZED=True にするか、"
                  "形式チェックのみで良ければ --lenient-validator を付けてください。", file=sys.stderr)
            sys.exit(2)

    rng = random.Random(a.seed)
    for t in range(a.cases):
        inp = gen_case(rng)
        rc_fast, out_fast = run(a.fast, inp, a.timeout)

        # fast 側の crash/timeout は全モード共通で即失敗
        if rc_fast != 0:
            dump(t, inp, fast=out_fast); print(f"fast crash/timeout (rc={rc_fast})")
            sys.exit(1)

        if a.mode == "exact":
            rc_naive, out_naive = run(a.naive, inp, a.timeout)
            if rc_naive != 0:
                dump(t, inp, naive=out_naive); print(f"naive crash/timeout (rc={rc_naive})")
                sys.exit(1)
            if out_fast != out_naive:
                dump(t, inp, fast=out_fast, naive=out_naive); print("WA (exact 不一致)")
                sys.exit(1)

        elif a.mode == "valid-only":
            ok, score, msg, _ = run_validator(a.validator, inp, out_fast, strict=strict)
            if not ok:
                dump(t, inp, fast=out_fast); print(f"INVALID: {msg}")
                sys.exit(1)

        elif a.mode == "score-compare":
            rc_naive, out_naive = run(a.naive, inp, a.timeout)
            if rc_naive != 0:
                dump(t, inp, naive=out_naive); print(f"naive crash/timeout (rc={rc_naive})")
                sys.exit(1)
            ok_f, sc_f, msg_f, _ = run_validator(a.validator, inp, out_fast, strict=strict)
            ok_n, sc_n, _, _ = run_validator(a.validator, inp, out_naive, strict=strict)
            if not ok_f:
                dump(t, inp, fast=out_fast); print(f"fast INVALID: {msg_f}")
                sys.exit(1)
            if not ok_n:
                dump(t, inp, naive=out_naive); print("naive INVALID (参照解が無効)")
                sys.exit(1)
            # スコアの良し悪し方向は課題依存なので「表示」に留める (失敗にはしない)
            if sc_f != sc_n:
                print(f"test {t}: score fast={sc_f} naive={sc_n}")

        if t % 1000 == 0:
            print("passed", t)

    print("all passed")


if __name__ == "__main__":
    main()

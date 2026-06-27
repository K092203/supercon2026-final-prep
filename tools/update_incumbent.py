#!/usr/bin/env python3
# =====================================================================
# update_incumbent.py — results.csv から「正解かつ最良」の構成を選び
#   state/incumbent.json を更新する (厳密に改善した時だけ置換)。
#   incumbent = 命綱: いつジョブが落ちても即提出できる現時点ベスト。
#
# 使い方:
#   tools/update_incumbent.py <round_dir> [--objective min-elapsed|max-score|score-per-sec]
#                                         [--state state/incumbent.json]
#   round_dir に configs.tsv (id→構成) と results.csv (id→計測) がある前提。
#
# 依存: Python 標準ライブラリのみ (WSL 側で動かす。富岳に Python 依存を置かない)。
# =====================================================================
import argparse, csv, json, math, os, sys
from datetime import datetime, timezone


def load_configs(path):
    """configs.tsv: id target bin ranks omp rep args → {id: {...}}"""
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            if not row.get("id") or row["id"].startswith("#"):
                continue
            out[row["id"]] = row
    return out


def load_results(path):
    """results.csv: id,elapsed,correct,score,exit_code,rep_done,notes → [rows]"""
    rows = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            rows.append(row)
    return rows


def objective_value(elapsed, score, kind):
    """大きいほど良い統一スコアに変換 (incumbent は最大を採る)。"""
    if kind == "min-elapsed":
        return -elapsed                      # 速いほど良い
    if kind == "max-score":
        return score                         # スコア最大化
    if kind == "score-per-sec":
        return score / elapsed if elapsed > 0 else float("-inf")
    raise ValueError(f"unknown objective: {kind}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("round_dir")
    ap.add_argument("--objective", default="min-elapsed",
                    choices=["min-elapsed", "max-score", "score-per-sec"])
    ap.add_argument("--state", default="state/incumbent.json")
    args = ap.parse_args()

    results_csv = os.path.join(args.round_dir, "results.csv")
    configs_tsv = os.path.join(args.round_dir, "configs.tsv")
    if not os.path.exists(results_csv):
        print(f"[incumbent] results.csv が無い: {results_csv}", file=sys.stderr)
        sys.exit(1)

    cfgs = load_configs(configs_tsv)
    rows = load_results(results_csv)

    # 正解かつ数値として有効な行だけを候補に
    cand = []
    for r in rows:
        if str(r.get("correct", "0")).strip() != "1":
            continue
        try:
            elapsed = float(r["elapsed"]); score = float(r["score"])
        except (ValueError, KeyError, TypeError):
            continue
        if not (math.isfinite(elapsed) and math.isfinite(score)):
            continue            # nan / inf は除外 (incumbent を汚さない)
        cand.append((objective_value(elapsed, score, args.objective), elapsed, score, r))

    if not cand:
        print("[incumbent] 正解構成なし → incumbent 据え置き", file=sys.stderr)
        return

    cand.sort(key=lambda t: t[0], reverse=True)   # 目的値が大きい順
    # configs.tsv に対応構成がある候補だけを採る。args 無し=再現不能な incumbent を作らない。
    chosen = next((c for c in cand if c[3]["id"] in cfgs), None)
    if chosen is None:
        print(f"[incumbent] configs.tsv に対応 id が無い ({configs_tsv}) → 再現不能なため"
              " incumbent を更新しない", file=sys.stderr)
        sys.exit(2)
    best_obj, best_el, best_sc, best_row = chosen
    bid = best_row["id"]
    cfg = cfgs[bid]

    incumbent = {
        "id": bid,
        "target": cfg.get("target", ""),
        "bin": cfg.get("bin", ""),
        "args": cfg.get("args", ""),
        "ranks": int(cfg["ranks"]) if cfg.get("ranks") else None,
        "omp": int(cfg["omp"]) if cfg.get("omp") else None,
        "elapsed": best_el,
        "correct": True,
        "score": best_sc,
        "objective": args.objective,
        "source_round": os.path.basename(os.path.normpath(args.round_dir)),
        "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    # 既存 incumbent と比較し、厳密に改善した時だけ置換 (同一 objective 前提)
    os.makedirs(os.path.dirname(args.state) or ".", exist_ok=True)
    prev = None
    if os.path.exists(args.state):
        try:
            with open(args.state) as f:
                prev = json.load(f)
        except (json.JSONDecodeError, OSError):
            prev = None

    if prev and prev.get("objective") == args.objective:
        prev_obj = objective_value(float(prev["elapsed"]), float(prev["score"]), args.objective)
        if best_obj <= prev_obj:
            print(f"[incumbent] 改善なし (現 {args.objective}: 据え置き id={prev.get('id')} "
                  f"elapsed={prev.get('elapsed')} score={prev.get('score')})", file=sys.stderr)
            return

    # アトミック書き込み: 一時ファイル → rename。途中で落ちても incumbent.json が壊れない(命綱)。
    tmp = args.state + ".tmp"
    with open(tmp, "w") as f:
        json.dump(incumbent, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, args.state)
    print(f"[incumbent] 更新: id={bid} elapsed={best_el} score={best_sc} "
          f"({args.objective}) → {args.state}", file=sys.stderr)


if __name__ == "__main__":
    main()

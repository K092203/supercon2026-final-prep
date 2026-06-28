# オートチューニング測定ハーネス — 運用ガイド

> 富岳「1ジョブ」で N 構成をまとめて測り、いつ落ちても提出できる incumbent を切らさないための
> 測定基盤。GP は載っていない（=外せる頭。§9 の差込点参照）。本体は **configs → 掃引 → incumbent**。
>
> 本書は**操作(how)**。**なぜこの形か(設計思想)**は [design-infra.md](design-infra.md) を参照。

---

## 1. 全体像（インターフェースが製品）

```
spaces/<tmpl>.tsv ──gen_configs.py──▶ configs.tsv
       │                                   │
  (手動 / LHS / 将来GP = 差し替え可能)       ▼
                            tune-sweep.sh（測定ループ・1本）
                            launcher=mpirun(local) / mpiexec(富岳)
                                          │
                                          ▼
                                     results.csv ──update_incumbent.py──▶ state/incumbent.json
```

- **`configs.tsv` ↔ `results.csv` ↔ `incumbent.json`** が固定インターフェース。
- 測定ループは [tools/tune-sweep.sh](../tools/tune-sweep.sh) 1 本。ローカルと富岳で **launcher と bindir だけ**差し替える
  → ローカルリハが富岳本番経路をそのまま検証する。

---

## 2. ファイルと役割

| ファイル | 役割 |
|---|---|
| [src/tune_args.hpp](../src/tune_args.hpp) | 全テンプレ共通の引数規約。`args.getf/geti` で argv/env を読み、末尾に `#TUNE elapsed=.. score=.. correct=..` を **stderr** へ出す |
| [tools/tune-sweep.sh](../tools/tune-sweep.sh) | 測定ループ（心臓部）。N 構成を順に rep 回測り、1 構成ごとに results.csv へ即追記 |
| [tools/gen_configs.py](../tools/gen_configs.py) | space.tsv → configs.tsv（LHS/grid・整数丸め・重複除去・カテゴリ列挙） |
| [tools/update_incumbent.py](../tools/update_incumbent.py) | results.csv から正解かつ最良を選び、**厳密に改善した時だけ** incumbent.json を置換 |
| [tools/tune-local.sh](../tools/tune-local.sh) | ローカル通しリハ（mpirun / build/mpi） |
| [tools/fugaku-tune.sh](../tools/fugaku-tune.sh) | 富岳バッチ版（sync→configs/tune-sweep送付→tune.pjm投入→wait→round rsync回収→incumbent） |
| [jobs/tune.pjm.template](../jobs/tune.pjm.template) | PJM ディレクティブ + tune-sweep.sh 呼び出し |
| `autotune/spaces/*.tsv` | 探索空間定義（当日埋める） |

---

## 3. space.tsv の書き方

1 行 1 ノブ。`#` コメント可。

```
sa-temp   float  0.2     3.0      # 連続値
iters     int    5000    40000    # 整数（最近傍へ丸め）
pad       pow2   1       16       # 2 のべき集合 {1,2,4,8,16}
bin       choice stencil stencil_blocked   # カテゴリ（外側で列挙）
```

- `name` が **target/bin/ranks/omp** のいずれかなら configs の該当列に入る
  （例: `bin choice …` で**リビルド済みバイナリ**を切り替え＝リビルド層）。それ以外は `--name value` として args に入る。
- **categorical（choice）は GP に渡さず外側で列挙**。各分岐内の連続・整数だけ LHS で振る（GP の弱点を回避）。

例: [autotune/spaces/search.tsv](../autotune/spaces/search.tsv) / [autotune/spaces/stencil.tsv](../autotune/spaces/stencil.tsv)

---

## 4. 1 ラウンドの回し方

### ローカル（本選前のリハ。実機なしで全経路を検証）

```bash
# 1) 構成生成（ローカルは過剰サブスクライブ回避のため omp を小さく）
tools/gen_configs.py autotune/spaces/search.tsv --n 6 --method lhs \
    --target search --bin search --ranks 2 --omp 2 --rep 1 > /tmp/c.tsv

# 2) 掃引 → incumbent（mpirun / build/mpi）
tools/tune-local.sh /tmp/c.tsv 0.5 max-score
#   引数: <configs> [budget_sec] [objective] [elapse_sec]
```

### 富岳（Day1 以降。`tune-local` を `fugaku-tune` に替えるだけ）

```bash
# 構成は omp=12 / ranks=4（A64FX 定石）で生成
tools/gen_configs.py autotune/spaces/search.tsv --n 12 --method lhs \
    --target search --bin search --ranks 4 --omp 12 --rep 3 > configs.tsv

tools/fugaku-tune.sh configs.tsv <BUDGET_SEC> max-score
#   sync→送付→tune.pjm 投入→wait→results.csv 回収→incumbent 更新 まで自動
```

---

## 5. results.csv / incumbent.json の読み方

`results.csv`（1 構成 1 行・即追記）:

```
id,elapsed,correct,score,exit_code,rep_done,notes
000,0.502463,1,2816.997184,0,1,ok
005,1.000000,0,0,124,1,incorrect/timeout      # timeout は elapsed=2*budget のペナルティ
003,1.000000,0,0,0,0,anytime-break(...)        # 時間切れで未測定（測れた分は上に残る）
```

- `elapsed` は rep の**中央値**、`correct` は全 rep の **AND**、`score` は中央値 run の値。
- 目的関数: **`min-elapsed`**（速度律速＝ステンシル等）/ **`max-score`**（予算固定の anytime＝SA・モンテカルロ）/ `score-per-sec`。
- `incumbent.json` は「現時点ベストの正解構成」。**いつジョブが落ちても提出できる命綱**。
  打切り round の後も据え置きで生き残る（検証済み）。
- 失敗構成の stderr は `results/tune/<round>/errors.log` に id 付きで集約される（crash/timeout の原因確認用）。

---

## 6. 3 層ノブモデル（重要）

| 層 | 例 | 振り方 |
|---|---|---|
| **① リビルド要** | flagset, `-D` 定数（stencil_blocked の **BT/RB/CB**）, stride | ログインノードで**事前ビルド**し、configs の `bin` 列で選択 |
| **② ジオメトリ（ピン留め敏感）** | **ranks×omp** | **別ジョブで少数点**だけ測る。各点で `make test-mpi` 相当のピン留め検証 |
| **③ 連続な内側ノブ** | sa_temp, cooling, block, pad | **1 ジョブ内バッチ掃引**（LHS/GP の本来の獲物） |

> ②を 1 ジョブ内で気軽に掃引しないこと。`max-proc-per-node` は submit 時固定で、`1rank×48` と `4rank×12`
> は `OMP_PLACES/PROC_BIND` の効き方が別物。mis-pin すると帯域が出ず、その悪い数字が GP/incumbent を汚染する。

### 6.1 リビルド層の変種を一括ビルド（当日コピペ用・検証済み）

`BT/RB/CB` は `#ifndef` ガード付きなので `-D` で安全に上書きできる（既定 BT=4/RB=128/CB=256）。
変種を**別バイナリ**として事前ビルドし、`configs.tsv` の `bin` 列で選べば ① を ③ と同じ掃引に載せられる。

```bash
# 富岳向けに BT×(RB,CB) の変種を一括ビルド (ログインノードで)
mkdir -p build/fugaku
for bt in 1 2 4; do for rbcb in "128 256" "256 256"; do
  set -- $rbcb; rb=$1; cb=$2
  name="stencil_blocked_bt${bt}_rb${rb}_cb${cb}"
  mpiFCCpx -Nclang -Ofast -Kfast,openmp,simd,zfill -msve-vector-bits=512 -DUSE_MPI -Isrc \
    -DBT=$bt -DRB=$rb -DCB=$cb src/stencil_blocked.cpp -o build/fugaku/$name
done; done
```

```text
# configs.tsv は bin 列にこの name を入れるだけ (target は stencil_blocked のまま)
id    target           bin                               ranks omp rep args
000   stencil_blocked  stencil_blocked_bt1_rb128_cb256   4     12  2
001   stencil_blocked  stencil_blocked_bt2_rb128_cb256   4     12  2
002   stencil_blocked  stencil_blocked_bt4_rb256_cb256   4     12  2
```

> ローカル検証は `mpiFCCpx`→`g++ -std=c++17 -O2 -fopenmp` に置換すれば同じパターンで通る（実証済み）。
> `BT=1` は plain stencil と等価なので、変種群に必ず混ぜて回帰の基準点にする。

---

## 7. ローカルリハの注意（検証で判明した実挙動）

- **mpirun の stdin 食い**: `tune-sweep.sh` は launcher の stdin を入力ファイル（既定 `/dev/null`、stdin を読む課題は
  第7引数 `input_file`）に固定する（無いと configs を食って 2 構成目以降が読めない）。修正済み。
- **過剰サブスクライブ**: ローカルで `-n4 × omp12 = 48` スレッドは MPI ランタイムが稀に起動でストールする。
  → ローカルリハは **`--omp 2 --ranks 2`** で生成する。富岳は `4×12=48` ぴったりなので起きない。
- ハングしても `tune-sweep.sh` は per-config `timeout` で打ち切りペナルティを記録して**継続**する（全滅しない）。

---

## 8. Day-1 ランブック

1. 課題を読み、テンプレ選択（search/stencil/skeleton/contest）。`solve()` を実装。
2. **実行時間制限を確認 → `BUDGET_SEC` 決定**（README 既定 1750 は仮）。
3. `make fugaku BUDGET_SEC=…` で**複数 flagset/バイナリを事前ビルド**（リビルド層）。
4. `autotune/spaces/<tmpl>.tsv` にチューニングしたい**内側ノブ**を書く。
5. solver が argv でそのノブを受けるか確認（`tune_args.hpp` 規約。当日は `correct` の検証器＝
   `solver_naive.cpp` 照合だけ問題固有に配線）。
6. `gen_configs.py … --omp 12 --ranks 4 > configs.tsv` → `fugaku-tune.sh configs.tsv <BUDGET>`。
7. `ranks×omp` の比較は**別途**少数ジョブで（ピン留め検証込み）。
8. `state/incumbent.json` を常に提出候補として確保。

---

## 9. 付録: GP（trustbo-gp）差込点

このハーネスに GP は**載っていない**。載せる場合も本体は不変で、**configs を作る側を差し替えるだけ**:

```
gen_configs.py（LHS）  →  autotune/ Rust CLI（trustbo-gp の ask_batch → 同じ configs.tsv を出力）
```

results.csv を読んで `tell` し、次ラウンドの configs.tsv を出す Rust producer を `autotune/` に置けばよい。
掃引・incumbent・space 定義は一切変えない。**ストレステストに気持ちよく通った時だけ載せる。渋ければ LHS のまま戦う。**

---

## 10. 凍結条件（ここに達したら新機能を止める）

- [x] g++ / mpic++ ビルドが警告なく通る（OpenMPI ヘッダ由来の警告は除く）
- [x] `make test-mpi` ALL PASS（tune_args 配線後も既存 MPI 経路に回帰なし）
- [x] gen → sweep → incumbent がローカルで通る
- [x] anytime 打切りで「測れた分 + incumbent」が残る
- [x] LHS の重複除去・カテゴリ列挙が効く
- [ ] **Day1: 富岳で `fugaku-tune.sh` 実機初通し**（本選前は構文・ドライランまで）
- [ ] **本選レギュレーション最終確認**（AI/自作ツール/持ち込み/時間制限）

到達後は infra を止め、残り時間は**過去問でのアルゴリズム練習**へ。

---

## 11. 堅牢性: 潰した穴一覧(レッドチーム実証済み)

3 ラウンドの敵対的テストで発見・修正した実バグ(すべて再現テストで確認):

| 穴 | 症状 | 対策 |
|---|---|---|
| CRLF 改行の configs | 算術破綻(args 空時) | tune-sweep が `tr -d '\r'` で正規化 |
| 末尾改行なしの configs | 最終構成が消失 | `read … \|\| [ -n "$id" ]` |
| solver が stdin 入力を読む課題 | `/dev/null` で全構成 score=0 誤計測 | 入力ファイル引数(tune-sweep/local/fugaku) |
| configs.tsv 欠落の round | args 空=再現不能 incumbent | 対応構成が無ければ更新拒否 + アトミック書込 |
| `--key`(値なし)/`--key=`(空)/空 env | 値が 1.0/0.0 に silent 化け | フラグ別管理 + 空値は既定へ |
| 非ゼロ終了 + `#TUNE` 出力 | crash 構成が「速い」incumbent に化ける | 終了コード≠0 は #TUNE を信用せず失敗扱い |
| 同一 id 重複 | incumbent が別構成の args を紐付け | 重複 id 検出で fail-fast |
| args の glob `*` | cwd ファイル名に展開 | `set -f`(noglob) |
| 非数値 rep/omp、omp=0 | `set -u` 算術で sweep 全体クラッシュ | 整数サニタイズ(非数値/0/負 → 1, WARN) |
| 壊れた space.tsv | 生 traceback | `file:line` 付き明瞭エラー |
| score=nan/inf | incumbent を汚染 | `math.isfinite` で除外 |

検証済みの堅牢性: **SIGTERM 中でも results.csv は完全行のみ**(1 構成 1 行の atomic append)、ranks 異常値は当該構成だけ timeout 失敗で**全体は継続**、敵対的 configs(全病理同時)でも生存。

**コードで塞がない残リスク(運用で対処)**:
- `correct` の偽陽性 → 当日 problem 固有の検証器を必ず配線(§8)。未知課題では汎用検証不能。
- `--cooling abc` 等の非数値 arg は atof=0 で silent(主要罠のフラグ/空値/空 env は対策済み)。
- objective を round 間で切替えると incumbent 上書き(仕様)。

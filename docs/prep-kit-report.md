# SuperCon2026 富岳向け準備キット 詳細レポート

- 生成日: 2026-06-28
- 対象 commit: `06e46c3abc81d632530c67413e59bc7835a61151`
- 対象ツリー: `/home/kotaro/dev/supercon2026/final-prep`
- 調査方針: 実在する `README.md`、`docs/`、`src/`、`tools/`、`jobs/`、`Makefile`、`.github/workflows/ci.yml` を読んで裏取りした。未確定事項は「未確定」または「推測」と明記する。

## 1. 概要と目的

このリポジトリは、SuperCon2026 本選で富岳(A64FX)を使う前提の MPI + OpenMP C++ テンプレート、富岳リモート開発ツール、オートチューニング測定ハーネスをまとめた準備キットである。

狙いは「課題公開直後にゼロから環境やテンプレートを作らず、当日の問題固有ロジックに集中する」こと。`README.md` では Day1 クイックスタートとして次の流れを提示している。

```bash
bash tools/day1-smoke.sh
make contest && bash tests/judge.sh tests
tools/fugaku-run.sh contest <BUDGET_SEC> tests/sample_01.in
```

ターゲットとして明記されている富岳側の基本前提は、1ノード=48コア=4 CMG x 12コア、SVE 512bit、推奨実行構成は `#PJM --mpi "max-proc-per-node=4"` + `OMP_NUM_THREADS=12 OMP_PROC_BIND=close OMP_PLACES=cores`。富士通コンパイラの既定は `mpiFCCpx -Nclang -Ofast -Kfast,openmp,simd,zfill -msve-vector-bits=512` で、`Makefile` の `CXX_FUGAKU ?= mpiFCCpx` と一致している。

重要な注意として、競技の実行時間制限は未確定扱いである。`README.md`、`docs/day1-checklist.md`、`docs/problem_notes.md` のいずれも `BUDGET_SEC=1750` を仮値として扱い、本選初日に実際の制限を確認して上書きするよう明記している。

## 2. 設計思想

設計思想は `docs/design-infra.md` と `docs/design-rebuild.md` に分かれている。前者は WSL-富岳インフラとオートチューニング基盤、後者は C++ テンプレートの設計記録である。

中心思想は「本選を決めるのは課題のアルゴリズム」であり、自動化はパラメータ測定や富岳投入の反復作業を軽くするためのものとして位置付けられている。`docs/design-infra.md` は、アルゴリズムが 10-100 倍を動かし、パラメータ調整は 1.5-3 倍程度という見立てを置き、ジョブ枠と人間の思考時間を希少資源として扱う。

責務分離も明確である。

- 手元 WSL: AI / Claude Code、ソース編集、configs 生成、results 解析、incumbent 管理。
- 富岳: ソース受領、`mpiFCCpx` ビルド、PJM ジョブ実行、測定結果出力。

富岳に API key、`node_modules`、PyTorch などを持ち込まない方針で、富岳は「コンパイル済み C++ を走らせて測る」測定器に徹する。AI が富岳へ入らない代わりに、`results/<jobid>/` に `meta.json`、`build.log`、`stdout.txt`、`stderr.txt`、`resource.txt`、`status.txt` などを残し、手元の AI がローカルファイルだけを読めば富岳上の状態を把握できるようにしている。

`docs/design-rebuild.md` は歴史的文書で、冒頭に「現状は `mpiFCCpx` 既定・4テンプレ(skeleton/stencil/stencil_blocked/search)構成」と注意がある。古い記述として `src/main.cpp` や「3バイナリ」などが残るため、現状確認には `README.md`、`docs/design-infra.md`、`docs/repository-overview.html` を優先する。

## 3. アーキテクチャ全体像

通常の富岳単発実行は、`tools/fugaku-run.sh` が次の処理を直列に実行する。

```text
WSL
  src/ Makefile
    |
    | tools/fugaku-sync.sh
    v
富岳ログインノード
  rsync 受信 -> make fugaku -> build/fugaku/*
    |
    | tools/fugaku-submit.sh
    v
富岳計算ジョブ
  mpiexec -n <ranks> build/fugaku/<target>
    |
    | tools/fugaku-wait.sh / tools/fugaku-fetch.sh
    v
WSL
  results/<jobid>/, results/latest -> <jobid>
```

単発デバッグは `fugaku-run.sh`、バッチ掃引は `fugaku-tune.sh` に分かれる。両者とも `tools/fugaku-config.env` を読み、直後に `tools/fugaku-validate.sh` を source して config 値を fail-closed に検証する。これにより、remote shell や PJM ジョブに素で埋め込まれる値へ空白、改行、シェルメタ文字が混入する事故を投入前に止める。

ジョブ結果は `results/<jobid>/` に自己完結スナップショットとして回収される。`tools/fugaku-fetch.sh` が生成する `meta.json` は、`jobid`、`target`、`budget_sec`、`nodes`、`mpi_ranks`、`omp_threads`、`rscgrp`、`elapse_limit`、`git_commit`、`git_dirty`、`build_status`、`exit_code`、`wall_sec`、`max_rss_kb`、`outcome`、`sched_status`、`input_sha256`、`input_bytes`、`tune`、`fetched_at` を持つ。

## 4. ディレクトリ構成

実ツリーで確認できる主な構成は次の通り。

```text
final-prep/
├── AGENTS.md
├── Makefile
├── README.md
├── autotune/
│   └── spaces/
│       ├── search.tsv
│       └── stencil.tsv
├── cases/
│   └── sample.in
├── docs/
│   ├── ai_context.md
│   ├── autotune.md
│   ├── codex-pipeline.md
│   ├── day1-checklist.md
│   ├── decisions.md
│   ├── design-infra.md
│   ├── design-rebuild.md
│   ├── experiments.md
│   ├── fugaku-ssh-template.txt
│   ├── fugaku-workflow.md
│   ├── problem_notes.md
│   └── repository-overview.html
├── jobs/
│   ├── search.job
│   ├── skeleton.job
│   ├── stencil.job
│   └── tune.pjm.template
├── results/
│   ├── .gitkeep
│   └── tune/
├── scripts/
│   ├── profile.sh
│   └── time_omp.sh
├── src/
│   ├── common.hpp
│   ├── contest.cpp
│   ├── search.cpp
│   ├── skeleton.cpp
│   ├── solver_naive.cpp
│   ├── stencil.cpp
│   ├── stencil_blocked.cpp
│   ├── tune_args.hpp
│   └── utilities.hpp
├── state/
│   └── .gitkeep
├── submissions/
│   └── .gitkeep
├── tests/
│   ├── judge.sh
│   ├── sample_01.in
│   ├── sample_01.out
│   ├── sample_02.in
│   └── sample_02.out
└── tools/
    ├── check-mpi.sh
    ├── codex-review.sh
    ├── day1-smoke.sh
    ├── fugaku-*.sh
    ├── gen_configs.py
    ├── gen_small_cases.py
    ├── save_candidate.sh
    ├── stress.py
    ├── tune-local.sh
    ├── tune-sweep.sh
    ├── update_incumbent.py
    └── validate_output.py
```

`build/`、`results/`、`submissions/`、`state/incumbent.json` などは実行時生成物を置く場所で、追跡対象は `.gitkeep` や設定テンプレートが中心である。

## 5. C++ テンプレート

### 5.1 共通ヘッダ

`src/common.hpp` は全テンプレート共通の `wtime()` と `Rng` を提供する。MPI 有効時は `MPI_Wtime()`、非 MPI では `std::chrono::steady_clock` を使う。乱数は splitmix64 で seed する xoshiro256**。`Rng::below()` は `__uint128_t` が使える場合は Lemire 法、使えない場合は double 経路にフォールバックし、範囲外をクランプする。

`src/utilities.hpp` は競技実装用の fast I/O、`Budget`、ビット演算、OpenMP ヘルパーを提供する。`fastio::init()` は stdin を最大 64MB の静的バッファへ読み切り、超過時は stderr にエラーを出して終了する。出力も 64MB バッファで、`wi/wll/wf/wc/ws/wn` を使う。`Budget` は `wtime()` ベースの期限管理である。

`src/tune_args.hpp` はチューニング共通規約で、`--key value`、`--key=value`、`--flag`、`TUNE_<KEY>` 環境変数を扱う。値の優先順位は argv、env、デフォルト。空値や値なしフラグを数値として誤解釈しないため、`raw()` は空文字を未設定扱いにし、`getf/geti` は `strtod/strtoll` の endptr で全体が数値か検証する。測定行は `tune::report(score, correct, elapsed)` が stderr に `#TUNE elapsed=... score=... correct=...` として出す。

### 5.2 `src/skeleton.cpp`

汎用スケルトン。N体、線形代数、ハイブリッド、モンテカルロ、BFS など、特定の形に寄らない課題のベースとして想定されている。現状の中身は円周率風の Monte Carlo サンプルで、OpenMP reduction で `local_count` を増やし、MPI 有効時は `MPI_Allreduce` で `global_count` に集約する。

特徴:

- `MPI_Init_thread(..., MPI_THREAD_FUNNELED, ...)` を使用。
- ランクとスレッドごとに `Rng` seed を分離。
- `BUDGET_SEC` はコンパイル時 macro の既定値だが、`--budget` で実行時上書きできる。
- rank 0 が `[env]`、`[result]`、`#TUNE` を出す。

### 5.3 `src/stencil.cpp`

2D ステンシル、反応拡散、セルオートマトン向けテンプレート。全体格子を行方向で MPI 分割し、上下ゴースト行を交換する。

A64FX 向けに実装済みの要点:

- float 固定で SVE 512bit の 16レーンを狙う。
- SoA 的な連続配置、`__restrict`、`#pragma omp simd`。
- first-touch 並列初期化。各スレッドが担当行に最初に触れる。
- stride padding。`stride = W + PAD` とし、`PAD` は `--pad` で既定 8。2 のべき幅によるキャッシュセット衝突を避ける意図。
- 非ブロッキング通信。`MPI_Irecv` / `MPI_Isend` を投げ、内部行 `2..lh-1` を先に更新し、`MPI_Waitall` 後に境界行を更新する。
- deadline 超過時も出力を保証するため、10 step ごとに `wtime() > deadline` を確認して break する。

当日差し替える場所は、`H/W/STEPS/D/dt`、`update_row` の更新式、初期条件。`react` は現在 `0.0f * react` で無効化されている。

### 5.4 `src/stencil_blocked.cpp`

温度ブロッキング版ステンシル。plain stencil が毎ステップ全格子を HBM から流すのに対し、`BT` ステップ分をタイルローカルバッファ上で進めて HBM 往復を減らす設計である。

主な仕様:

- `GH/GW/GSTEPS` は macro で既定 8192/8192/200。
- `BT/RB/CB` は compile-time macro。既定は `BT=4`、`RB=128`、`CB=256`。
- runtime 引数として `--steps` と `--pad` を読む。
- MPI では `BT` 段の deep-halo を `BT` ステップごとに 1 回交換する。
- `lh < BT` の場合は `MPI_Abort` で明示停止する。
- 出力は `sum/sumsq/chk` を出し、plain との一致検証に使う。

`docs/autotune.md` §6.1 には `-DBT/-DRB/-DCB` を変えた複数バイナリを事前ビルドし、`configs.tsv` の `bin` 列で選ぶ手順がある。これは「リビルド要ノブは実行時引数にしない」という 3層ノブモデルに沿っている。

### 5.5 `src/search.cpp`

組合せ最適化向けの並列局所探索 / 焼きなましテンプレート。現状の課題依存部は QUBO 風のサンプルで、`Problem::cost()` が全評価、`Problem::delta()` がビット反転差分評価である。

特徴:

- スレッドごとに独立 SA を走らせ、ランク内ベストを集約。
- `delta()` は分岐を避け、`#pragma omp simd reduction(+:S)` で unit-stride ベクトル化を狙う。
- チューニングノブとして `--sa-temp`、`--cooling`、`--iters`、`--sync` を読む。
- MPI 有効時は `MPI_Allreduce` with `MPI_DOUBLE_INT` + `MPI_MAXLOC` でベストランクを特定し、`MPI_Bcast` で解ベクターを配布する。
- rank 0 は SYNC ごとに `result.txt` を書く。時間切れでも直近ベストを残す意図。

当日は `Problem` 構造体、入力生成ブロック、出力形式、近傍操作、冷却スケジュールを課題に合わせて変更する。

### 5.6 `src/contest.cpp`

本選当日用の I/O 配線サンプル。現状は「`N` と整数列を読み、合計と最大値を出す」だけである。`utilities.hpp` の `fastio` を使う実例で、`make contest`、`make test-contest`、`bash tests/judge.sh tests` の対象になる。

MPI 有効時は `MPI_Init` し、出力は rank 0 のみ。rank 0 は stdout に解、stderr に `#TUNE` を出す。

### 5.7 `src/solver_naive.cpp`

参照実装の骨組み。`contest.cpp` と同じサンプル問題を素朴に解く。`tools/stress.py` の naive 側として使う想定で、当日は parse、`solve_naive()`、output を課題形式に合わせる。

## 6. 富岳リモートワークフロー

富岳系スクリプトは `tools/fugaku-config.env.template` から作る `tools/fugaku-config.env` を読む。`fugaku-config.env` 自体は秘密や環境固有値を含むため、追跡対象ではない。

主要コマンド:

```bash
tools/fugaku-sync.sh [BUDGET_SEC]
tools/fugaku-submit.sh <target> [budget_sec] [input_file]
tools/fugaku-wait.sh <jobid>
tools/fugaku-fetch.sh <jobid> <target> <budget_sec>
tools/fugaku-run.sh <target> [budget_sec] [input_file]
tools/fugaku-cancel.sh [jobid]
```

`fugaku-run.sh` の target は `skeleton|stencil|stencil_blocked|search|contest`。`stencil-blocked` は `stencil_blocked` に正規化される。存在しない target や input は投入前に止まる。

`fugaku-validate.sh` は以下を検証する。

- 必須値: `FUGAKU_HOST`、`FUGAKU_REMOTE_DIR`、`FUGAKU_RSCGRP`、`FUGAKU_GROUP`、`FUGAKU_NODE_COUNT`、`FUGAKU_MPI_RANKS`、`FUGAKU_OMP_THREADS`、`FUGAKU_ELAPSE`。
- 任意値: `FUGAKU_CXX`、`FUGAKU_LLIO_VOL`、`FUGAKU_SPATH`、`FUGAKU_FREQ`、`FUGAKU_THROTTLING`、`FUGAKU_MODULES`。
- パスや識別子は許可文字集合に制限し、改行やシェル注入文字を弾く。

`fugaku-submit.sh` は `BUDGET_SEC + FUGAKU_ELAPSE_MARGIN_SEC <= FUGAKU_ELAPSE` を確認する。`FUGAKU_ELAPSE_MARGIN_SEC` の既定は 30 秒。予算が PJM elapse を超える場合は投入前にエラー終了する。

stdin 入力がある場合、`fugaku-submit.sh` は `inputs/in_<timestamp>_<pid>.dat` という一意名で remote へ rsync する。固定名による並行投入時の上書きを避けるためである。ジョブ内では `results/<jobid>/input.dat` と `input.sha256` に複製し、実行後に remote inputs 側を掃除する。

PJM ジョブは `fugaku-submit.sh` が動的生成する。主な実行環境は次の通り。

```bash
export OMP_NUM_THREADS=${FUGAKU_OMP_THREADS}
export OMP_PROC_BIND=close
export OMP_PLACES=cores
mpiexec -n ${FUGAKU_MPI_RANKS} "${FUGAKU_REMOTE_DIR}/build/fugaku/${TARGET}"
```

`/usr/bin/time -v -o` が実際に使える場合だけ `resource.txt` を取る。存在確認だけでなく `true` で probe しており、time の互換性問題でソルバ実行自体を壊さない作りになっている。

`fugaku-fetch.sh` は remote の `results/<jobid>/` と最新ビルドログを回収し、`meta.json` を生成し、`results/latest` symlink を更新する。`status.txt` がない場合は `outcome=killed-or-incomplete`。`exit_code=124` は `timeout`、それ以外の非ゼロは `failed` として扱う。

## 7. オートチューニング測定ハーネス

固定インターフェースは次の 3 つ。

```text
configs.tsv -> results.csv -> state/incumbent.json
```

`tools/gen_configs.py` は `autotune/spaces/*.tsv` を読み、`configs.tsv` を生成する。出力列は `id target bin ranks omp rep args`。対応する `space.tsv` の type は `float`、`int`、`pow2`、`choice`。`target/bin/ranks/omp/rep` は特別扱いで configs の列に入り、それ以外は `--name value` として `args` に入る。`choice` は外側で直積列挙され、連続/整数ノブは LHS または grid で撒かれる。

代表コマンド:

```bash
tools/gen_configs.py autotune/spaces/search.tsv --n 12 \
  --target search --bin search --ranks 4 --omp 12 --rep 3 > configs.tsv

tools/tune-local.sh configs.tsv 0.5 max-score
tools/fugaku-tune.sh configs.tsv <BUDGET_SEC> max-score tests/sample_01.in
```

`tools/tune-sweep.sh` がローカル/富岳共通の測定ループである。引数は次の形。

```bash
tune-sweep.sh <configs.tsv> <results.csv> <launcher> <bindir> <budget_sec> <elapse_sec> [input_file]
```

ローカルは `launcher="mpirun --oversubscribe"`、`bindir=build/mpi`。富岳は `launcher=mpiexec`、`bindir=build/fugaku`。この launcher と bindir の差し替えだけで同じループを使う。

堅牢化として実装済みの事項:

- CRLF を `tr -d '\r'` で正規化。
- 末尾改行なしの最終行も読む。
- 重複 id を検出したら fail-fast。
- `ranks/omp/rep` は非数値や 0 以下を 1 にサニタイズし警告。
- `set -f` で glob 展開を止める。
- launcher の stdin を input file または `/dev/null` に固定し、`mpirun` が configs の stdin を食う事故を防ぐ。
- 1構成ごとに `results.csv` へ即追記し `sync` する。
- per-config timeout は `budget*1.5+60` 秒。
- 失敗/timeout は有限ペナルティ `2*budget`。
- 非ゼロ終了時は `#TUNE` が出ていても信用しない。

`tools/update_incumbent.py` は `results.csv` と `configs.tsv` を読み、正解かつ最良の構成だけを `state/incumbent.json` に反映する。目的関数は `min-elapsed`、`max-score`、`score-per-sec`。既存 incumbent と同じ objective の場合、厳密に改善した時だけ atomic rename で置換する。`configs.tsv` に対応 id がない測定値は再現不能として採用しない。

`docs/autotune.md` の 3層ノブモデルは次の整理である。

| 層 | 例 | 振り方 |
|---|---|---|
| リビルド要 | flagset、`-D` 定数、`BT/RB/CB`、stride | 事前ビルドし `bin` 列で選ぶ |
| ジオメトリ | `ranks x omp` | 別ジョブで少数点を測る |
| 連続な内側ノブ | `sa_temp`、`cooling`、`block`、`pad` | 1ジョブ内バッチ掃引 |

`jobs/tune.pjm.template` は `fugaku-tune.sh` が placeholder を埋める PJM テンプレートで、ジョブ本体は `bash tools/tune-sweep.sh ...` を呼ぶだけである。

## 8. 検証ループ

検証ループは、小ケース生成、愚直解、validator、stress、候補保存で構成される。

`tools/gen_small_cases.py` は `gen_case(rng)` と `corner_cases()` が正本で、`tools/stress.py` もこれを import する。現状は「N と整数列」のサンプルケースを生成する。当日は課題の入力形式に書き換える。既存 seed のケースを無言上書きしないため、同じ seed のファイルが出力先にある場合は `--force` なしでは停止する。

`src/solver_naive.cpp` は「確実に正しい」参照実装を置く場所。現状は `contest.cpp` と同じサンプルを素朴に計算する。

`tools/validate_output.py` は 4 関数を当日実装する前提で分離している。

- `read_input(path)`
- `parse_output(path)`
- `validate(inst, ans)`
- `score(inst, ans)`

現在の `CUSTOMIZED=False` の状態では、空出力、debug token、`nan/inf`、`#TUNE` や `[search]` などの debug 行混入を検出する程度である。`--strict` を付けると、未カスタマイズ状態では exit 3 で停止する。

`tools/stress.py` は 3 モードを持つ。

- `exact`: fast と naive の stdout 完全一致。
- `valid-only`: fast の出力を validator で検査。naive 不要。
- `score-compare`: fast/naive 両方を validator で採点し、スコア差を表示。良否方向は課題依存なので現状では fail しない。

validator を使うモードでは既定で strict になり、未カスタマイズ validator を検出して起動時に止める。形式チェックだけで回す場合は `--lenient-validator` を明示する。

`tools/save_candidate.sh` は提出候補を `submissions/YYYYMMDD-HHMMSS_<label>/` に保存する。保存対象は `src/`、`results` の主要ファイル、`git.commit`、`git.status`、`git.diff`、`note.md`。`tools/fugaku-config.env` は保存しない。`src/` 配下に秘密らしきファイル名やパスがあれば除外し、`git.diff` に秘密らしき文字列があれば警告する。

## 9. ローカル検証と CI

`Makefile` の主要ターゲットは次の通り。

```bash
make                  # skeleton/stencil/stencil_blocked/search
make contest
make local-mpi        # build/mpi/*
make test-mpi         # tools/check-mpi.sh
make fugaku           # build/fugaku/*
make fugaku-run TARGET=contest BUDGET_SEC=1750 INPUT=tests/sample_01.in
make tune-local CONFIGS=/tmp/c.tsv BUDGET_SEC=1
make clean
```

`tools/check-mpi.sh` は OpenMPI があるローカル環境で、4ランク検証を行う。

- stencil: 1ランクと4ランクの最終 sum が一致するか。
- stencil_blocked: plain stencil と blocked が一致するか。
- skeleton: `MPI_Allreduce` で4ランク分が集約されるか。
- search: `MPI_MAXLOC + Bcast` がデッドロックせず、`result.txt` を出すか。

`tests/judge.sh` は `tests/*.in` を `./build/contest` に与え、対応する `*.out` があれば stdout を完全一致比較する。`*.out` がない場合は実行のみ確認し、`RUN_ONLY` として扱う。

`tools/day1-smoke.sh` は Day1 冒頭の一括健全性確認で、以下を行う。

- `make clean && make contest`
- `bash tests/judge.sh tests`
- `python3 -m py_compile tools/*.py`
- `bash -n tools/*.sh scripts/*.sh tests/*.sh`
- `validate_output.py` の sample valid 確認
- `gen_small_cases.py` の決定性確認
- OpenMPI があれば `make test-mpi`

`.github/workflows/ci.yml` は Ubuntu latest で `build-essential openmpi-bin libopenmpi-dev python3` を入れ、`make`、`make local-mpi`、`make test-mpi`、`make contest`、`bash tests/judge.sh tests`、Python 構文チェック、shell 構文チェックを実行する。

## 10. Codex セカンドオピニオン・パイプライン

`docs/codex-pipeline.md` と `tools/codex-review.sh` に、Claude 主導で Codex CLI を read-only のセカンドオピニオンとして使う仕組みがある。

使い方:

```bash
tools/codex-review.sh diff
tools/codex-review.sh result
tools/codex-review.sh "stencil_blocked.cpp のタイル境界に off-by-one が無いか確認して"
```

設計原則は、Claude と Codex が同じファイルだけを読み、富岳には入らず、Codex は read-only に徹すること。`AGENTS.md` も同じ前提を持ち、Codex の入口として `README.md`、主要 `docs/`、`results/<jobid>/` の読み方を指示している。

`tools/codex-review.sh` は実行結果を `results/codex/<timestamp>-<mode>.md` に保存する。Claude はこのファイルを読み、指摘を二次判断に使う想定である。

## 11. ドキュメント体系

主要ドキュメントの役割は次の通り。

| ファイル | 役割 |
|---|---|
| `README.md` | 全体像、クイックスタート、テンプレ選択、富岳実行、オートチューニング、ディレクトリ構造 |
| `docs/day1-checklist.md` | 課題公開直後から30分のチェックリスト。担当者名を書きながら使う形式 |
| `docs/autotune.md` | 測定ハーネスの操作、3層ノブモデル、Day1 ランブック、堅牢化記録 |
| `docs/fugaku-workflow.md` | WSL2-富岳のセットアップ、個別コマンド、結果スナップショットの読み方 |
| `docs/problem_notes.md` | 当日プレイブック。課題サマリ、テンプレ選択、実験ログの入口 |
| `docs/experiments.md` | 最適化レシピと実験ログ。A64FX の診断順やメモリ/演算律速のレシピ |
| `docs/design-infra.md` | インフラ、ハーネス、全体方針の設計思想 |
| `docs/design-rebuild.md` | C++ テンプレート再構築時の設計記録。歴史的文書として注意書きあり |
| `docs/repository-overview.html` | 外部向け総覧 HTML |
| `docs/ai_context.md` | AI 応答は日本語という言語ルール |
| `docs/codex-pipeline.md` | Claude x Codex のセカンドオピニオン運用 |
| `docs/fugaku-ssh-template.txt` | SSH config テンプレート |

`docs/decisions.md` は存在するが、現時点では内容が空である。

## 12. 本選当日の運用フロー

`docs/day1-checklist.md` と `docs/problem_notes.md` を合わせると、当日の推奨フローは次の通りである。

1. 環境スモークを先に走らせる。

```bash
git pull
bash tools/day1-smoke.sh
ssh fugaku "echo OK"
tools/fugaku-run.sh contest 5 tests/sample_01.in
```

2. 課題仕様を読み、入力形式、出力形式、制約、scoring、実行時間制限、メモリ制限、提出形式、サンプル、一意解かどうかを表に埋める。

3. テンプレートを選ぶ。

- 組合せ最適化: `src/search.cpp`
- ステンシル/CA/反応拡散: `src/stencil.cpp`、メモリ律速なら `src/stencil_blocked.cpp`
- 粒子N体/線形代数/汎用: `src/skeleton.cpp`
- まず I/O を通す: `src/contest.cpp`

4. 検証ループを配線する。

```bash
make fast FAST_TARGET=contest && make naive
python3 tools/gen_small_cases.py --seed 1 --corners --out tests/generated
python3 tools/stress.py --fast ./build/fast --naive ./build/naive --mode exact --cases 1000 --seed 1
```

構築/最適化で出力が一意でなければ、`--mode valid-only --validator tools/validate_output.py` を使う。ただし validator は problem 固有に実装し、`CUSTOMIZED=True` にする。

5. ローカル判定と富岳初回 run を行う。

```bash
make contest && bash tests/judge.sh tests
tools/fugaku-run.sh contest <BUDGET_SEC> <input>
cat results/latest/meta.json
```

6. valid な候補を保存する。

```bash
tools/save_candidate.sh stable results/latest "Day1 first valid"
```

7. アルゴリズムが固まったら、`gen_configs.py` -> `fugaku-tune.sh` -> `state/incumbent.json` のチューニングループでパラメータを詰める。

詰まった時の脱出ルートとして、`docs/day1-checklist.md` には MPI ハング時の `--omp 2 --ranks 2`、ステンシル変種ビルド、予算/PJM elapse 調整、構築問題での `valid-only`、提出候補保存などがまとまっている。

## 13. 既知の前提・未確定・残課題

既知の前提:

- 富岳実機操作は人間またはスクリプトが行い、AI は手元 WSL のファイルだけを読む。
- `FUGAKU_ELAPSE`、`FUGAKU_RSCGRP`、`FUGAKU_GROUP`、`FUGAKU_REMOTE_DIR` などは `tools/fugaku-config.env` に当日または環境ごとに設定する。
- `src/main.cpp` は存在しない。テンプレートを直接編集する方針である。
- `contest.cpp`、`solver_naive.cpp`、`gen_small_cases.py`、`validate_output.py` は現状サンプル問題用で、当日 problem 固有に差し替える。

未確定:

- `BUDGET_SEC=1750` は仮値。本選当日の実行時間制限を確認して上書きする必要がある。
- 富岳実機での `fugaku-tune.sh` E2E 初通しは `docs/autotune.md` で Day1 未完了項目として残っている。
- 本選レギュレーション、AI/自作ツール/持ち込み/時間制限の最終確認は Day1 項目。
- `FUGAKU_MODULES`、LLIO volume、`mpiFCCpx` が実環境でそのまま動くかは Day1 確認事項。

残課題:

- GP(trustbo-gp) 本接続は未実装。`docs/autotune.md` では任意の後付け差込点として扱われている。
- `docs/decisions.md` は空で、意思決定ログとしては未使用。
- `score-compare` は現状スコア差を表示するだけで、最大化/最小化に基づく fail 判定は課題依存として未実装。
- `validate_output.py` の汎用状態は形式チェック止まり。これを本物の正誤判定と誤認しない運用が必要。
- `search.cpp` の `result.txt` 出力形式、`Problem`、`delta()`、correct 判定はすべて当日課題に依存する。

## 14. 完成度評価

観点別の所見:

| 観点 | 評価 | 所見 |
|---|---|---|
| C++ テンプレート | 高 | 汎用、ステンシル、温度ブロッキング、探索、I/O 雛形、naive が揃っている。A64FX 向けの first-touch、stride padding、`__restrict`、`omp simd`、非ブロッキング MPI、`MAXLOC+Bcast` まで入っている |
| 富岳リモート運用 | 高 | sync/submit/wait/fetch/run/cancel が分離され、config 検証、予算-elapse 整合、一意入力名、`meta.json` 生成まで実装済み |
| オートチューニング | 中-高 | GP はないが、固定 IF、LHS/grid 生成、共通 sweep、incumbent 更新、堅牢化は実装済み。測定ハーネスとしては実戦投入可能な形 |
| 検証ループ | 中 | 仕組みは揃っているが、validator/naive/case generator は当日課題への差し替えが必須 |
| CI / ローカル検証 | 高 | Ubuntu CI で OpenMPI を入れ、ローカル/MPI/contest/judge/Python/shell を確認する構成 |
| ドキュメント | 高 | README、設計、運用、Day1、autotune、Codex、実験ログが揃う。ただし歴史的文書と現状との差分には注意 |
| 当日即応性 | 高 | Day1 smoke、チェックリスト、候補保存、結果スナップショット、Codex レビュー経路まで用意されている |
| 未確定リスク | 中 | 実機 E2E、競技制限、最終レギュレーション、problem 固有実装は当日依存 |

総合すると、このリポジトリは「富岳で戦うための低レイヤ準備」と「当日チーム運用の型」がかなり揃った状態である。一方で、競技の点を決める問題固有アルゴリズム、validator、naive、ケース生成、最終提出形式は意図的に空けてある。引き継ぐ開発者は、インフラを増やすよりも、Day1 でこの型に課題仕様を素早く流し込み、`results/latest/meta.json` と `state/incumbent.json` を軸に検証可能な改善ループを回すことを優先すべきである。

# SuperCon2026 本選 テンプレートリポジトリ

富岳（A64FX）向け MPI + OpenMP ハイブリッド最適化テンプレート。  
8月末本選で即座に使い始めるための構成一式（提出プログラムには実行時間制限あり。値は当日確認）。

---

## ターゲット環境

| 項目 | 値 |
|---|---|
| スーパーコンピュータ | 富岳 (A64FX) |
| ノード構成 | 1ノード = 48コア = 4CMG × 12コア |
| メモリ帯域 | HBM2 〜1 TB/s |
| SIMD幅 | SVE 512bit（float 16レーン、double 8レーン） |
| 富士通コンパイラ | `mpiFCCpx -Nclang -Ofast -Kfast,openmp,simd,zfill -msve-vector-bits=512`（ログインノードのクロスコンパイラ。計算ノードは `mpiFCC`） |
| 推奨実行構成 | `#PJM --mpi "max-proc-per-node=4"`（1ランク=1CMG固定）+ `OMP_NUM_THREADS=12 OMP_PROC_BIND=close OMP_PLACES=cores` |
| 競技時間 | ⚠️ **未確定**。`BUDGET_SEC=1750`（30分想定）は仮の値。**本選初日に実際の実行時間制限を確認して上書きする**こと |

---

## テンプレート選択指針

| 課題タイプ | 使用テンプレート | ポイント |
|---|---|---|
| 組合せ最適化（配置・スケジューリング） | `src/search.cpp` | `Problem` 構造体と `delta()` を差し替え |
| ステンシル / CA / 反応拡散 | `src/stencil.cpp` | 更新カーネル（lap+react）を差し替え |
| 粒子N体 / 線形代数 | `src/skeleton.cpp` | ループ本体を実装 |
| ハイブリッド（SA + ステンシル評価） | `skeleton.cpp` ベース | stencil のカーネル関数を切り出して流用 |

---

## ローカルビルドと動作確認

```bash
# 全テンプレートをビルド (g++ / OpenMP / MPI なし)
make

# 個別ビルドと実行
make skeleton && ./build/skeleton
make stencil  && ./build/stencil
make search   && ./build/search
make stencil-blocked && ./build/stencil_blocked   # 温度ブロッキング版 (メモリ律速ステンシル用)

# MPI 経路の事前検証 (富岳に投げる前に 4 ランクで確認)
#   要 OpenMPI: sudo apt-get install -y openmpi-bin libopenmpi-dev
make test-mpi   # ハロ交換 / MPI_Allreduce / MAXLOC+Bcast を自動 PASS/FAIL 判定

# 富岳提出用ビルド (mpiFCCpx / USE_MPI / SVE)
make fugaku

# クリーン
make clean
```

**`make test-mpi` の役割:** MPI のバグ（ハロ交換の境界誤り・集約漏れ・MAXLOC/Bcast のデッドロック）は
単一プロセスでは絶対に出ず、富岳で初めて発覚してキュー時間を浪費する。ローカル 4 ランクで先に潰す。
（出力例: `✅ ALL PASS — MPI 経路は健全。富岳へ投入可能。`）

**ローカル実行の出力例:**

```
[env] ranks=1 threads/rank=12 total_cores=12 host=your-host
[result] in_circle=25746986855  elapsed=5.000s    # skeleton (Monte Carlo)
[stencil] sum=1.234567e+03  steps=200/200  5.001s # stencil
[search] best=12.345678  ranks=1 threads=12       # search
```

---

## 富岳での実行（本選フロー）

### 初回セットアップ（本選初日 1 回のみ）

```bash
# 1. SSH config 追記（HostName と User を実際の値に書き換える）
cat docs/fugaku-ssh-template.txt >> ~/.ssh/config
chmod 600 ~/.ssh/config

# 2. アカウント設定ファイルを作成
cp tools/fugaku-config.env.template tools/fugaku-config.env
# FUGAKU_USER / FUGAKU_GROUP / FUGAKU_RSCGRP / FUGAKU_REMOTE_DIR を埋める

# 3. 富岳側ディレクトリ作成
ssh fugaku "mkdir -p ~/supercon2026/final-prep/results"

# 4. ControlMaster 確立（OTP があればここで入力。以降 4時間不要）
ssh fugaku "echo 'OK'"

# 5. 動作確認（sync + build のみ）
tools/fugaku-sync.sh 5
```

詳細: [docs/fugaku-workflow.md](docs/fugaku-workflow.md)

### 通常の開発ループ

```bash
# ワンショット: 転送 → ビルド → ジョブ投入 → 待機 → 結果回収
tools/fugaku-run.sh stencil 1750

# 結果を確認
cat results/latest/stdout.txt
cat results/latest/meta.json

# コードを修正して再実行
tools/fugaku-run.sh stencil 1750
```

---

## オートチューニング（1ジョブで複数構成を掃引）

パラメータを振って速さを測る作業を自動化する測定ハーネス。詳細・3層モデル・Day1ランブックは [docs/autotune.md](docs/autotune.md)。

```bash
# 探索空間 → configs.tsv（LHS・整数丸め・重複除去・カテゴリ列挙）
tools/gen_configs.py autotune/spaces/search.tsv --n 12 \
    --target search --bin search --ranks 4 --omp 12 --rep 3 > configs.tsv
# 富岳で N 構成を 1 ジョブ掃引 → state/incumbent.json 更新
tools/fugaku-tune.sh configs.tsv <BUDGET_SEC> max-score
# ローカル予行演習（実機前に全経路を検証。過剰サブスクライブ回避で omp は小さく）
tools/gen_configs.py autotune/spaces/search.tsv --n 6 --ranks 2 --omp 2 --rep 1 > /tmp/c.tsv
tools/tune-local.sh /tmp/c.tsv 0.5 max-score
```

> `state/incumbent.json` =「いつ落ちても提出できる現時点ベスト」。各テンプレは `src/tune_args.hpp` 経由で
> `--sa-temp` 等を argv で受け、末尾に `#TUNE elapsed=.. score=.. correct=..` を stderr へ出す。
> GP は載っていない（任意の付録。差込点は docs/autotune.md §9）。

---

## Codex セカンドオピニオン（任意）

実装を Codex CLI（OpenAI）に **read-only** で独立レビュー/検証させ、Claude が結果を取り込むパイプライン。
独立視点で見落としを減らし、レビュー/検証を別エンジンに逃がしてトークンを分散する。詳細は [docs/codex-pipeline.md](docs/codex-pipeline.md)。

```bash
tools/codex-review.sh diff      # 現在の git 差分を Codex がレビュー
tools/codex-review.sh result    # results/latest/ の富岳スナップショットを Codex が分析
```

> Codex の入口は `AGENTS.md`（Claude と同一の `results/` スナップショット読解手順を記載）。
> `codex exec` は read-only サンドボックスなのでソースは編集しない（検証台に徹する）。

---

## 本選当日の手順

```bash
# 1. 課題を読んでテンプレートを選ぶ（上表参照）
# 2. 対象ファイルを直接編集（各ファイル冒頭の「🎯 当日の手順」に編集箇所と注意を記載）
vim src/stencil.cpp   # または search.cpp / skeleton.cpp

# 3. ローカル動作確認（5秒で完了）
make stencil && ./build/stencil

# 4. 富岳に投入（BUDGET_SEC は当日の実行時間制限に合わせる。1750 は仮）
tools/fugaku-run.sh stencil <BUDGET_SEC>

# 5. 結果 → AI 解析 → 修正 → 繰り返し
```

> **注意**: `src/main.cpp` は存在しない。テンプレートを直接編集する。  
> 各テンプレ冒頭の `🎯 当日の手順` に「どこを触るか・何を忘れないか」を集約済み。  
> I/O 配線は `src/contest.cpp`（fastio の読む→解く→書く雛形）で実証済み。  
> `make test-contest`、または `make contest && bash tests/judge.sh tests` で一括判定（`*.in`/`*.out` を足す）。  
> `make stress` は `solver_naive.cpp` に愚直解を書いてから使う（現状は空スタブ）。

---

## ディレクトリ構造

```
final-prep/
├── src/
│   ├── common.hpp          # wtime() / Rng (xoshiro256**) 共通ヘッダ (一元管理)
│   ├── utilities.hpp       # 競技用 fastio / Budget / bit演算 (common.hpp を内包)
│   ├── skeleton.cpp        # 汎用スケルトン (MPI+OMP+時間予算)
│   ├── stencil.cpp         # ステンシル/CA (2D行分割・通信/計算オーバーラップ)
│   ├── stencil_blocked.cpp # 温度ブロッキング版 (メモリ律速時の伸び代。plain と結果一致を検証済)
│   ├── search.cpp          # 並列SA (xoshiro256** / MPI_MAXLOC+Bcast)
│   ├── contest.cpp         # 当日雛形 (fastio I/O 配線の実証サンプル。当日 solve を差し替え)
│   ├── solver_naive.cpp    # 愚直解プレースホルダ (stress.py 用)
│   └── tune_args.hpp       # チューニング共通規約 (argv/env を読む → #TUNE 行を出す)
├── tools/
│   ├── fugaku-run.sh       # ワンショット実行 (sync→submit→wait→fetch)
│   ├── fugaku-sync.sh      # rsync + ログインノードビルド
│   ├── fugaku-submit.sh    # pjsub 投入
│   ├── fugaku-wait.sh      # pjstat ポーリング
│   ├── fugaku-fetch.sh     # 結果回収
│   ├── fugaku-tune.sh      # バッチ掃引 (1ジョブでN構成。fugaku-run のバッチ版)
│   ├── fugaku-cancel.sh    # ジョブ削除 (pjdel。暴走/ミスジョブ即停止)
│   ├── fugaku-config.env.template  # アカウント設定テンプレート
│   ├── check-mpi.sh        # ローカル4ランクで MPI 経路を自動検証 (make test-mpi)
│   ├── tune-sweep.sh       # 測定ループ (local/富岳 共用の心臓部)
│   ├── tune-local.sh       # ローカル掃引リハ (mpirun。富岳前の予行演習)
│   ├── gen_configs.py      # 探索空間 → configs.tsv (LHS/grid・丸め・重複除去)
│   ├── update_incumbent.py # results.csv → state/incumbent.json (改善時のみ)
│   ├── codex-review.sh     # Codex セカンドオピニオン (read-only レビュー/検証)
│   ├── stress.py           # Fast vs Naive 比較（課題実装後に使用）
│   ├── benchmark.py        # Fast の速度計測
│   └── runner.sh           # ⚠️ 旧ローカルランナー (src/main.cpp 参照・現構成では未整合)
├── jobs/                   # pjsub 参照テンプレート
│   ├── skeleton.job / stencil.job / search.job   # 手動投入用
│   └── tune.pjm.template   # バッチ掃引ジョブ (fugaku-tune.sh が生成)
├── autotune/
│   └── spaces/             # 探索空間定義 search.tsv / stencil.tsv (当日埋める)
├── cases/
│   └── sample.in           # ダミー入力（課題に合わせて書き換え）
├── tests/                  # サンプル *.in/*.out + judge.sh (一括正誤判定)
├── scripts/                # ⚠️ profile.sh / time_omp.sh (src/main.cpp 参照・旧ツール)
├── docs/
│   ├── fugaku-workflow.md  # 富岳インフラ詳細設計
│   ├── fugaku-ssh-template.txt
│   ├── design-rebuild.md   # 設計思想: C++テンプレート (なぜ)
│   ├── design-infra.md     # 設計思想: インフラ/ハーネス/全体 (なぜ。テンプレ以外)
│   ├── problem_notes.md    # 当日プレイブック（初動手順 + テンプレ選択ツリー + 記入欄）
│   ├── experiments.md      # 最適化レシピ集（ROI順）+ 実験ログ表
│   ├── decisions.md        # 意思決定ログ予定地（現状 空）
│   ├── autotune.md         # オートチューニング運用ガイド (操作/3層モデル/Day1/堅牢化記録)
│   ├── codex-pipeline.md   # Claude×Codex セカンドオピニオン・パイプライン
│   └── repository-overview.html  # 外部向け総覧 (単体HTML)
├── results/                # .gitignore済み（富岳結果。tune/ にバッチ掃引結果）
├── state/                  # .gitignore済み（incumbent.json = 命綱。.gitkeep のみ追跡）
├── build/                  # .gitignore済み
├── AGENTS.md               # Codex CLI 指示書 (Claude の CLAUDE.md 相当・Codex版コンテキスト)
├── Makefile
└── README.md
```

---

## A64FX 最適化チェックリスト

- [ ] 富岳投入前に `make test-mpi` で MPI 経路（ハロ交換 / Allreduce / MAXLOC+Bcast）を 4 ランク検証
- [ ] `--mpi "max-proc-per-node=4"` で 1ランク=1CMG 固定（崩れると first-touch の局所性が壊れ帯域が出ない）
- [ ] first-touch 並列初期化（忘れると HBM 帯域が半分以下）
- [ ] リーディング次元を 2 のべきにしない（stride パディングでキャッシュセット衝突回避。stencil 実装済み）
- [ ] unit-stride アクセス（内側ループが j 方向で SVE 化される）
- [ ] `__restrict` 付与で別名なしを明示
- [ ] `#pragma omp simd` で内側ループをベクトル化（分岐レス化も忘れず。search の `delta()` 参照）
- [ ] `-Kzfill` で書き込み専用ストリームの read-for-ownership を省く（Makefile 設定済み）
- [ ] `Irecv` → 内部計算 → `Waitall` の順で通信/計算オーバーラップ（stencil 実装済み）
- [ ] 評価を差分 `delta()` で行う（全評価 O(N²) を避ける）
- [ ] `MPI_MAXLOC` + `Bcast` で全体ベストを効率的に同期
- [ ] 入力が 8MB 超なら `utilities.hpp` の `IBUF_SIZE` を増やす（既定 64MB。超過時は stderr 警告）
- [ ] `BUDGET_SEC` は当日の実行時間制限を確認して `make fugaku BUDGET_SEC=…` で上書き（時間内に必ず出力）

---

## ライセンス

競技用リポジトリ（非公開）

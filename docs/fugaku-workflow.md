# WSL2↔富岳 開発インフラ

## アーキテクチャ

```
WSL2 (Claude Code + 開発者)              富岳 (A64FX)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━
src/, Makefile                            $REMOTE_DIR/src/, Makefile
tools/                                    $REMOTE_DIR/build/fugaku/
results/                   ←─ rsync ─    $REMOTE_DIR/results/{JOBID}/

[1] fugaku-sync.sh    ──── rsync ──→     src/ Makefile を転送
                      ──── ssh ────→     make fugaku (ログインノード)
[2] fugaku-submit.sh  ──── ssh ────→     pjsub → JOBID を受け取る
[3] fugaku-wait.sh    ──── pjstat ──→    30秒ポーリングで完了待ち
[4] fugaku-fetch.sh   ←─── rsync ──     results/$JOBID/ を回収
[5] Claude Code が results/latest/ を read → ボトルネック特定 → src/ 修正
```

## 本戦初日セットアップ (5手順)

```bash
# 1. SSH config 追記
cat docs/fugaku-ssh-template.txt >> ~/.ssh/config
chmod 600 ~/.ssh/config
# HostName と User を実際の値に編集する

# 2. 接続テスト (OTP が必要な場合はここで入力)
ssh fugaku "hostname && echo OK"

# 3. 富岳側ディレクトリ作成
ssh fugaku "mkdir -p ~/supercon2026/final-prep/results"

# 4. アカウント設定ファイルを編集
cp tools/fugaku-config.env.template tools/fugaku-config.env
# FUGAKU_USER / FUGAKU_GROUP / FUGAKU_RSCGRP / FUGAKU_REMOTE_DIR を埋める

# 5. 動作確認 (ドライラン: sync + build のみ)
tools/fugaku-sync.sh 5
```

## 富岳環境/最適化ノブ (tools/fugaku-config.env)

公式コマンド準拠の opt-in 設定。**空のままなら現状の挙動(ゼロ回帰)**。Day1 に実機確認して値を埋める。

| 変数 | 用途 | 例 / 既定 |
|---|---|---|
| `FUGAKU_CXX` | ログインノードのMPI C++クロスコンパイラ | `mpiFCCpx`(計算ノードは `mpiFCC`) |
| `FUGAKU_MODULES` | `module load` する一覧 | `"lang/tcsds-1.2.41"` / 空=しない |
| `FUGAKU_LLIO_VOL` | `#PJM -x PJM_LLIO_GFSCACHE=` | `/vol0004` / 空=指定なし |
| `FUGAKU_FREQ` | `#PJM -L freq=`(速度・boost) | `2200` / 空=既定2000 |
| `FUGAKU_THROTTLING` | `#PJM -L throttling_state=`(HBMスロットル) | `0`=解除 / 空=既定 |
| `FUGAKU_SPATH` | `#PJM --spath`(PJM -S 統計の出力先) | `results/%j` / 空=出さない |

> ⚠️ Day1必須確認: ① `mpiFCCpx` で `make fugaku` が通るか ② `module` 名 ③ LLIO volume 名。
> `module` は非対話 ssh で未定義の場合があるため、ビルドが「コマンドなし」で失敗したら要調整。

## 開発ループ

```bash
# ワンショット実行 (sync → submit → wait → fetch → サマリ表示)
tools/fugaku-run.sh skeleton 1750

# 結果を Claude Code に解析させる
# → results/latest/stdout.txt, meta.json を read に渡す

# src/ を修正して再実行
tools/fugaku-run.sh skeleton 1750
```

## 個別コマンド

```bash
# 転送 + ビルドだけ
tools/fugaku-sync.sh [budget_sec]

# 投入だけ (JOBID を表示)
tools/fugaku-submit.sh skeleton 1750

# ジョブ状態を手動確認
ssh fugaku "pjstat"
ssh fugaku "pjstat -j 12345"

# 結果だけ回収
tools/fugaku-fetch.sh 12345 skeleton 1750

# ジョブキャンセル
ssh fugaku "pjdel 12345"
```

## AI 解析のエントリポイント

各ジョブの `results/<jobid>/` は**そのジョブの完全な検死報告書**(これを読めば富岳の状態が分かる):

```
results/
└── latest/          ← 最新ジョブへのシンボリックリンク
    ├── meta.json    ← 全部入りヘッダ (config+source+build+resource+outcome。最初に読む)
    ├── build.log    ← mpiFCCpx ビルド出力 (富士通clang エラー/警告)
    ├── stdout.txt   ← プログラム出力 ([stencil] sum=... 等)
    ├── stderr.txt   ← 実行時エラー・MPI エラー
    ├── resource.txt ← /usr/bin/time -v (最大RSS / 実wall / CPU%)
    ├── status.txt   ← completed exit=.. wall_sec=.. (無ければ PJM kill で未完)
    └── exit_code.txt
```

`meta.json` のフォーマット (新スキーマ):
```json
{
  "jobid": "123456", "target": "skeleton", "budget_sec": 1750,
  "nodes": 1, "mpi_ranks": 4, "omp_threads": 12, "total_cores": 48,
  "rscgrp": "small", "elapse_limit": "00:30:00",
  "git_commit": "2fd51ea", "git_dirty": 0, "build_status": "ok",
  "exit_code": 0, "wall_sec": 1748, "max_rss_kb": 1234567,
  "outcome": "completed", "sched_status": "COMPLETED",
  "fetched_at": "2026-08-17T12:34:56Z"
}
```
> `outcome`: completed / timeout / failed / killed-or-incomplete。`build_status`: ok / error。
> ビルド失敗時はジョブが出ないため `results/last-build.log` に出力が残る。

## ControlMaster による OTP の扱い

初回接続 (`ssh fugaku`) で OTP を入力すると `ControlPersist 4h` の間は
以降の ssh/rsync が再認証不要になる。`fugaku-run.sh` 実行前に
一度 `ssh fugaku` しておけばスクリプトは完全自動化で動く。

```bash
# セッション開始時に一度だけ手動接続
ssh fugaku "echo 'ControlMaster established'"

# 以降は自動 (4時間有効)
tools/fugaku-run.sh skeleton 1750
```

## ディレクトリ構造

```
final-prep/
├── jobs/
│   ├── skeleton.job   # pjsub 参照テンプレート (手動投入用)
│   ├── stencil.job
│   ├── search.job
│   └── tune.pjm.template  # バッチ掃引ジョブ (fugaku-tune.sh が生成)
├── results/           # .gitignore 済み
│   ├── .gitkeep
│   ├── latest -> 123456/   (シンボリックリンク)
│   └── 123456/
│       ├── meta.json  ← AI 解析エントリポイント
│       ├── stdout.txt
│       ├── stderr.txt
│       └── exit_code.txt
├── tools/
│   ├── fugaku-config.env.template  # 追跡対象 (生成物 fugaku-config.env が .gitignore)
│   ├── fugaku-sync.sh
│   ├── fugaku-submit.sh
│   ├── fugaku-wait.sh
│   ├── fugaku-fetch.sh
│   ├── fugaku-run.sh   ← 単発デバッグはこれ
│   ├── fugaku-tune.sh  ← バッチ掃引 (1ジョブでN構成。詳細 docs/autotune.md)
│   └── fugaku-cancel.sh← ジョブ削除 (pjdel。暴走/ミスジョブ即停止)
└── docs/
    ├── fugaku-ssh-template.txt
    ├── fugaku-workflow.md  (このファイル)
    └── autotune.md         # オートチューニング測定ハーネス運用ガイド
```

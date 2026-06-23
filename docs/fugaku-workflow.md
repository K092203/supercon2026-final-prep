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

```
results/
└── latest/          ← 最新ジョブへのシンボリックリンク
    ├── meta.json    ← ジョブ設定・コア数・exit_code (Claude Code が最初に読む)
    ├── stdout.txt   ← プログラム出力 ([stencil] sum=... 等)
    └── stderr.txt   ← コンパイル警告・MPI エラー等
```

`meta.json` のフォーマット:
```json
{
  "jobid": "123456",
  "target": "skeleton",
  "budget_sec": 1750,
  "nodes": 1,
  "mpi_ranks": 4,
  "omp_threads": 12,
  "total_cores": 48,
  "exit_code": 0
}
```

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
│   └── search.job
├── results/           # .gitignore 済み
│   ├── .gitkeep
│   ├── latest -> 123456/   (シンボリックリンク)
│   └── 123456/
│       ├── meta.json  ← AI 解析エントリポイント
│       ├── stdout.txt
│       ├── stderr.txt
│       └── exit_code.txt
├── tools/
│   ├── fugaku-config.env.template  # .gitignore 済み
│   ├── fugaku-sync.sh
│   ├── fugaku-submit.sh
│   ├── fugaku-wait.sh
│   ├── fugaku-fetch.sh
│   └── fugaku-run.sh   ← 普段はこれだけ使う
└── docs/
    ├── fugaku-ssh-template.txt
    └── fugaku-workflow.md  (このファイル)
```

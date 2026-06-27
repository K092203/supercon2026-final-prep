# AGENTS.md — Codex CLI 向けプロジェクト指示

> このファイルは **Codex CLI** が各セッション冒頭で読む指示書(Claude Code の CLAUDE.md 相当)。
> 目的: **Claude と Codex が完全に同じ情報・同じ前提で動けるようにする**こと。
> Codex は主に **セカンドオピニオン / 検証台**(レビュー・正誤確認・性能分析)として使う。

## 役割と原則
- **既定は read-only**。指示が無い限りソースを編集せず、「読んで分析・指摘」に徹する。
  (`codex exec` は既定で read-only サンドボックス。`tools/codex-review.sh` 経由の呼び出しも read-only)
- **応答は日本語**(コード・コマンド・API名のみ英語可。`docs/ai_context.md` のルールに準拠)。
- **富岳には入らない**。富岳での実行・ビルドは人間/スクリプトが行い、Codex は手元(WSL)の
  ファイルだけを読む(Claude と同じ責務分離)。

## このリポジトリは何か
富岳(A64FX)向け SuperCon2026 本選の MPI+OpenMP C++ テンプレート + リモート開発ツール +
自動チューニング測定基盤。詳細は下記を読むこと(Claude と同じ入口):
- `README.md` — 全体像とコマンド
- `docs/repository-overview.html` — 外部向け総覧(章立てで把握しやすい)
- `docs/design-rebuild.md` — C++テンプレートの設計思想
- `docs/design-infra.md` — インフラ/ハーネスの設計思想(なぜ)
- `docs/autotune.md` — 測定ハーネスの操作
- `docs/fugaku-workflow.md` — 富岳リモート手順

## 富岳の状態の読み方(Claude と同一)
各ジョブは `results/<jobid>/`(最新は `results/latest/`)に自己完結スナップショットとして残る。
**まず `meta.json` を読む**(設定・git commit・build_status・exit_code・wall_sec・max_rss_kb・outcome)。
次に必要に応じ `build.log`(mpiFCCpx エラー)/ `stdout.txt` / `stderr.txt` /
`resource.txt`(最大RSS・実時間)/ `status.txt`(完了の印。無ければ kill 未完)。
掃引は `results/tune/<round>/results.csv` と `state/incumbent.json`。

## ビルド・テスト(検証に使う)
```bash
make                 # ローカル4テンプレ (g++)
make local-mpi       # mpic++ で build/mpi/* (要 OpenMPI)
make test-mpi        # MPI経路の自動 PASS/FAIL 判定
bash tests/judge.sh tests   # *.in/*.out 一括判定
```
富岳ビルドは `make fugaku`(`CXX_FUGAKU` 既定 `mpiFCCpx`)。実機操作は `tools/fugaku-*.sh`。

## Claude からの呼ばれ方
Claude は `tools/codex-review.sh {diff|result|"<質問>"}` で Codex を呼び、Codex の分析結果
(`results/codex/<timestamp>.md`)を読んで二次判断に使う。Codex は read-only で結果ファイルを残すだけ。

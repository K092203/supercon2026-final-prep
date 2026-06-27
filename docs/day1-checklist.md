# Day1 チェックリスト（課題公開〜最初の30分）

課題公開直後に「仕様の読み違い」と「環境の崩れ」を潰すための1枚。
上から順に埋める。チーム分担の認識ズレ防止のため**担当者名も書く**。

---

## 0. 環境スモーク（コードを読む前に並行で）

- [ ] `git pull`（最新同期・コンフリクトマーカー無しを確認）
- [ ] `bash tools/day1-smoke.sh` が **ALL OK**
- [ ] 富岳 SSH 接続OK（`ssh fugaku "echo OK"`）／`tools/fugaku-config.env` 記入済
- [ ] `tools/fugaku-run.sh contest 5 tests/sample_01.in` で実機 1往復（`results/latest/meta.json` 確認）

> ⚠️ `BUDGET_SEC + 余裕(既定30s) <= FUGAKU_ELAPSE`。当日の実行時間制限を確認して両方を合わせる。

---

## 1. 課題仕様の読み取り（ここを埋める = 認識合わせ）

| 項目 | 値 | 担当/メモ |
|---|---|---|
| 入力形式 | | |
| 出力形式 | | |
| 制約（N の上限・値域など） | | |
| scoring（最大化/最小化・式） | | |
| 実行時間制限 | | → `BUDGET_SEC` に反映 |
| メモリ制限 | | → 64MB超なら `IBUF_SIZE` 調整 |
| 提出形式（ファイル/標準出力） | | |
| サンプル入出力の有無 | | `tests/` に配置 |
| 正解は一意か（構築/最適化か） | | → stress の mode 選択 |

---

## 2. テンプレート選択

- [ ] 課題タイプを判定 → 使うテンプレを決定
  - 組合せ最適化 → `src/search.cpp`
  - ステンシル/CA/反応拡散 → `src/stencil.cpp`（メモリ律速なら `stencil_blocked.cpp`）
  - 粒子N体/線形代数/汎用 → `src/skeleton.cpp`
  - まず I/O だけ通す → `src/contest.cpp`
- [ ] 選んだファイルの「🎯 当日の手順」コメントを読む

---

## 3. 検証ループの配線（担当を分ける）

- [ ] **validator 担当**: `tools/validate_output.py` の `read_input/parse_output/validate/score` を課題固有に
- [ ] **naive 担当**: `src/solver_naive.cpp` の `solve_naive()` を「確実に正しい」参照実装に（速度不問）
- [ ] **ケース生成担当**: `tools/gen_small_cases.py` の `gen_case()`/`corner_cases()` を課題形式に
- [ ] stress 実行: 一意解なら `--mode exact`、構築/最適化なら `--mode valid-only`（+ `--validator`）

```bash
make fast FAST_TARGET=contest && make naive
python3 tools/gen_small_cases.py --seed 1 --corners --out tests/generated
python3 tools/stress.py --fast ./build/fast --naive ./build/naive --mode exact --cases 1000 --seed 1
```

---

## 4. 富岳初回 run と候補保存

- [ ] `make contest && bash tests/judge.sh tests` がローカルで通る
- [ ] `tools/fugaku-run.sh contest <BUDGET_SEC> <input>` で初回投入 → `results/latest` 確認
- [ ] valid を確認したら **即** `tools/save_candidate.sh stable results/latest "Day1 first valid"`

> 「いつ落ちても提出できる現時点ベスト」を常に `submissions/` と `state/incumbent.json` に残す。

---

## 5. 失敗時にどこを見るか（詰まったら）

| 症状 | 見る場所 |
|---|---|
| ジョブが結果を残さない | `results/<jobid>/status.txt`（無ければ PJM kill＝予算/elapse 超過を疑う） |
| 実行時エラー | `stderr.txt` / `exit_code.txt` |
| ビルド失敗 | `build.log` |
| どのコードの結果か不明 | `meta.json`（commit/dirty/input_sha256） |
| 直近ジョブID | `results/.last-jobid` |

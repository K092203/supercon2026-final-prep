# 本選 当日プレイブック / 課題メモ

> このファイルは**本選当日に上から順に埋めながら使う**。意思決定ツリーで迷いを消す。

---

## 0. 初動 5 分（課題を読む前にやる）

```bash
git checkout main && git pull          # 最新テンプレ取得
make && make test-mpi                  # ローカル健全性 (g++ ビルド + MPI 4ランク検証)
tools/fugaku-sync.sh 5                  # 富岳へ転送 + ログインノードでビルド確認
```

- [ ] **実行時間制限を確認** → `BUDGET_SEC` = 制限 − 50秒マージン（README既定1750は仮）
- [ ] **mpiFCCpx ビルドを最優先で1回通す**（計算ノードは mpiFCC。富士通clang特有のエラーを早期に潰す）
- [ ] 提出方法・採点基準（正確さ/速度の配点）・提出回数を確認

---

## 1. 課題サマリ（記入欄）

| 項目 | 内容 |
|---|---|
| 課題名 | |
| 入力形式 | （行数・型・サイズ上限 → `IBUF_SIZE` 要調整か？） |
| 出力形式 | （ここを `result.txt` 書き出しに正確に反映） |
| 制約 (N, グリッド, ステップ) | |
| 実行時間制限 | （→ `BUDGET_SEC`） |
| 採点 | 正確さ □  速度 □  両方 □ |

---

## 2. 意思決定ツリー（テンプレ選択）

```
課題を読む
├─ 最適化したい量があり「より良い配置/順序/割当」を探す
│    → search.cpp   (SA。Problem 構造体 cost/delta を書き換え)
│      例: 配置 / スケジューリング / 敷詰め / Graph Golf / QUBO
│
├─ 2D/3D 格子を時間発展させる（隣接セルから更新）
│    → stencil.cpp  (update_row のカーネルを書き換え)
│      例: 反応拡散 / 熱・波動 / ライフゲーム・CA / 流体
│      ※ メモリ律速で速度が頭打ち → stencil_blocked.cpp (温度ブロッキング) を検討
│
├─ 粒子間の相互作用 / 行列演算 / 数え上げ
│    → skeleton.cpp (「ここに課題本体」へ実装。stencil のカーネルを流用可)
│      例: N体 / 線形代数 / モンテカルロ / BFS
│
└─ 上記の複合（評価関数が重いシミュレーション + 探索）
     → skeleton.cpp ベース。stencil のカーネルを SA の評価に流用
```

各テンプレ冒頭の `🎯 当日の手順` に「どこを触るか・何を忘れないか」を集約済み。

---

## 3. 実装の最初の一歩（共通）

1. 入力読込: `utilities.hpp` の `fastio::init()` → `ri()/rll()/rf()` で読む
   （入力が 8MB 超なら `IBUF_SIZE` を増やす。超過時は stderr に警告が出る）
2. **まず愚直に1回正解を出す**（small ケースで正答 → それから高速化）
3. 出力を課題フォーマットに整形（search の `result.txt` 書き出し部を直す）
4. `make <target> && ./build/<target> < cases/sample.in` でローカル確認
5. small ケースの正解を `tests/sample_01.out` に置き `tests/judge.sh` で回帰確認
6. `tools/fugaku-run.sh <target> <BUDGET_SEC>` で富岳投入（単発デバッグ）
7. **アルゴリズムが固まったら**パラメータ掃引で詰める:
   `tools/gen_configs.py autotune/spaces/<tmpl>.tsv … > configs.tsv`
   → `tools/fugaku-tune.sh configs.tsv <BUDGET_SEC> <objective>`（1ジョブでN構成）
   → `state/incumbent.json`（= いつ落ちても提出できる現時点ベスト）を提出候補に確保。
   詳細・3層ノブモデル・当日の `correct` 検証器の配線は [autotune.md](autotune.md)。

---

## 4. 当日ログ（時刻 / やったこと / 結果 / 次の一手）

| 時刻 | 変更 | スコア/時間 | 次 |
|---|---|---|---|
| | | | |

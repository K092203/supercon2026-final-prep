# SuperCon2026 本選テンプレート再構築 設計ドキュメント

**作成日**: 2026-06-23  
**ブランチ**: main  
**ステータス**: 実装済（2026-06-23 時点の設計記録＝**歴史的文書**）

> ⚠️ 本書は再構築**当時**の記録です。`src/main.cpp`(変更前スタブ)、コンパイラ名 `mpiFCC`、
> 「3 バイナリ」等は当時の記述で、**現状は `mpiFCCpx` 既定・4 テンプレ(skeleton/stencil/stencil_blocked/search)構成**。
> 最新の実態は [README.md](../README.md) / [design-infra.md](design-infra.md) / [repository-overview.html](repository-overview.html) を参照。

> **範囲**: 本書は **C++ テンプレート**の設計。テンプレート以外(WSL↔富岳インフラ /
> オートチューニング基盤 / 全体方針)の設計思想は [design-infra.md](design-infra.md)。

---

## 1. 背景と目的

### 現状

`src/main.cpp` および `src/solver_naive.cpp` は g++ 向けの空スタブであり、富岳 (A64FX) での競技に必要な MPI / OpenMP / SVE の構造が一切ない。

### 目標

8 月末の SuperCon2026 本選（富岳 1 ノード = A64FX 48 コア = 4 CMG × 12 コア）で即座に使えるテンプレートセットに `src/` を刷新する。3 つのアップロードテンプレート（`supercon_skeleton.cpp`, `stencil_mpi_omp.cpp`, `parallel_search.cpp`）を `src/` 直下に統合し、`Makefile` を MPI + OpenMP + SVE 対応に更新する。

---

## 2. ターゲット環境（A64FX 制約まとめ）

| 項目 | 値 |
|---|---|
| ノード構成 | 48 コア / 4 CMG / HBM2 ~1 TB/s |
| 推奨ランク構成 | 4 ランク/ノード（CMG ごと 1 ランク × 12 スレッド） |
| SIMD 幅 | SVE 512 bit（float 16 レーン、double 8 レーン） |
| 富士通コンパイラ | `mpiFCC -Nclang -Ofast -Kfast,openmp,simd -msve-vector-bits=512` |
| GCC 系コンパイラ | `mpic++ -O3 -fopenmp -mcpu=a64fx -msve-vector-bits=512` |
| ローカル検証 | `g++ -O2 -fopenmp -std=c++17` (MPI なしでも動く `#ifdef USE_MPI` ガード) |
| OMP 環境変数 | `OMP_NUM_THREADS=12 OMP_PROC_BIND=close OMP_PLACES=cores` |

---

## 3. ファイル構成の変更計画

### 変更前

```
src/
  main.cpp          ← 空スタブ (g++ only)
  solver_naive.cpp  ← 空スタブ
  common.hpp        ← 空
Makefile            ← g++ 単一バイナリ (fast / naive)
```

### 変更後

```
src/
  skeleton.cpp      ← 共通スケルトン（supercon_skeleton.cpp ベース）
                       wtime / Rng / MPI+OMP初期化 / 時間予算ループ
  stencil.cpp       ← ステンシル系テンプレート（stencil_mpi_omp.cpp ベース）
                       2D格子行分割 / Isend+Irecv / first-touch / omp simd
  search.cpp        ← 並列局所探索テンプレート（parallel_search.cpp ベース）
                       xoshiro256** / SA / MPI_MAXLOC+Bcast
  common.hpp        ← 共通ヘッダ（Rng 構造体 / wtime() を一元管理）
Makefile            ← 3 バイナリ対応 + ローカル/Fugaku 切替
```

> `solver_naive.cpp` は削除せず空のまま維持する。本選当日に「愚直解 vs 高速解」のストレステストで使う可能性があるため。

---

## 4. common.hpp の設計

`supercon_skeleton.cpp` と `parallel_search.cpp` はどちらも `Rng` (xoshiro256**) と `wtime()` を持つ。重複排除のため `common.hpp` に一本化する。

```cpp
// common.hpp — SuperCon2026 共通ユーティリティ
#pragma once
#include <cstdint>
#include <chrono>
#ifdef USE_MPI
#include <mpi.h>
#endif

static inline double wtime() {
#ifdef USE_MPI
    return MPI_Wtime();
#else
    using namespace std::chrono;
    return duration<double>(steady_clock::now().time_since_epoch()).count();
#endif
}

struct Rng {
    uint64_t s[4];
    static uint64_t sm64(uint64_t& x) {
        uint64_t z = (x += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
    void seed(uint64_t sd) { for (auto& v : s) v = sm64(sd); }
    static uint64_t rotl(uint64_t x, int k) { return (x << k) | (x >> (64 - k)); }
    uint64_t next() {
        uint64_t r = rotl(s[1] * 5, 7) * 9, t = s[1] << 17;
        s[2] ^= s[0]; s[3] ^= s[1]; s[1] ^= s[2]; s[0] ^= s[3];
        s[2] ^= t; s[3] = rotl(s[3], 45);
        return r;
    }
    double uniform() { return (next() >> 11) * (1.0 / 9007199254740992.0); }
    uint32_t below(uint32_t n) { return (uint32_t)(((__uint128_t)next() * n) >> 64); }
};
```

各 `.cpp` は `#include "common.hpp"` で取り込む。

---

## 5. Makefile の変更計画

### 要件

- `make` (引数なし): ローカル g++ でスケルトン・ステンシル・探索の 3 バイナリをビルド
- `make fugaku`: mpiFCC で 3 バイナリをビルド（富岳提出用）
- `make test-skeleton / test-stencil / test-search`: 個別実行
- `make stress / bench`: 既存ツールと互換性維持（`build/fast` を使うストレステスト用に `skeleton → build/fast` シムを残す）
- `make clean`: `build/` 削除

### 主要 Makefile 変数

```makefile
CXX_LOCAL  = g++
CXXFLAGS_LOCAL = -std=c++17 -O2 -fopenmp -Wall

CXX_FUGAKU = mpiFCC
CXXFLAGS_FUGAKU = -Nclang -Ofast -Kfast,openmp,simd -msve-vector-bits=512 -DUSE_MPI

# ローカルビルドにも -DUSE_MPI ガードを外してスタンドアロン実行できるようにする
CXXFLAGS_LOCAL_MPI = $(CXXFLAGS_LOCAL) -DUSE_MPI
```

### ターゲット一覧

| target | 説明 |
|---|---|
| `all` (default) | ローカル g++ で skeleton / stencil / search をビルド |
| `fugaku` | mpiFCC で 3 バイナリをビルド |
| `fast` | `skeleton` の別名（stress.py との互換性維持） |
| `test-skeleton` | `build/skeleton` を単体実行 |
| `test-stencil` | `build/stencil` を単体実行 |
| `test-search` | `build/search` を単体実行 |
| `run` | `test-skeleton` の別名 |
| `stress` | `tools/stress.py` 実行（fast vs naive） |
| `bench` | `tools/benchmark.py` 実行 |
| `clean` | `build/` 削除 |

---

## 6. 各テンプレートの役割と本選当日の運用フロー

### 問題タイプ別選択指針

| 課題タイプ | 使用テンプレート |
|---|---|
| A: 組合せ最適化（配置・スケジューリング） | `search.cpp` → Problem 構造体を書き換え |
| B: 格子シミュレーション（反応拡散・CA） | `stencil.cpp` → 更新カーネルを書き換え |
| C: 粒子 N 体 | `stencil.cpp` を粒子ループに転用 or `skeleton.cpp` ベース |
| D: 線形代数 | `skeleton.cpp` ベース + BLAS ライクな omp simd カーネル |
| E: データ探索 | `search.cpp` or `skeleton.cpp` ベース |
| ハイブリッド (最有力 2026 予想) | `skeleton.cpp` + `stencil.cpp` カーネルを SA の評価関数に流用 |

### 当日編集手順

> **注意**: `src/main.cpp` は存在しない。テンプレートを直接編集するか、
> 別名にコピーして Makefile に追記する。

```bash
# 1. 最新コードを取得
git checkout main && git pull

# 2. 課題タイプに合うテンプレートを直接編集
#    組合せ最適化 → src/search.cpp の Problem 構造体と delta() を書き換え
#    ステンシル/CA → src/stencil.cpp の更新カーネル (lap+react) を書き換え
#    その他/ハイブリッド → src/skeleton.cpp をベースに実装

# 3. ローカルで動作確認
make stencil         # または make search / make skeleton
./build/stencil      # 出力: [stencil] sum=... steps=.../... ...s

# 4. 富岳へ転送・ビルド・投入 (ワンコマンド)
tools/fugaku-run.sh stencil 1750
# → results/latest/stdout.txt と meta.json に結果が届く

# 5. 結果を見てコードを修正し、繰り返す
```

---

## 7. ストレステスト / ベンチマーク運用

`tools/stress.py` と `tools/benchmark.py` は `build/fast` を参照しており、変更不要。  
`Makefile` の `fast` ターゲットを `build/skeleton` へのシムとして残すことで既存スクリプトが引き続き動く。

---

## 8. スコープ外（今回やらないこと）

- Tier B テンプレート（粒子 N 体専用・BLAS 専用）は本選課題確認後に追加
- CI / GitHub Actions の富岳エミュレーション環境
- `cases/` のテストケース拡充（課題が出てから追加）
- `docs/problem_notes.md` / `docs/experiments.md` の記入（当日作業）

---

## 9. リスクと対策

| リスク | 影響 | 対策 |
|---|---|---|
| `#ifdef USE_MPI` ガード抜け | ローカルビルド失敗 | `make`（MPI なし）を常にデフォルトにし、CI 代わりの確認手順とする |
| `__uint128_t` が富士通 clang で未サポート | Rng.below() ビルドエラー | `(uint64_t)((double)next() * n)` でフォールバックを `common.hpp` に用意 |
| first-touch 初期化を忘れる | HBM 帯域が半分以下に低下 | `stencil.cpp` コメントに「first-touch 必須」注記を明記 |
| MPI_Waitall を呼び忘れてハロが未到着 | サイレントな計算バグ | `Irecv/Isend` → `Waitall` をセットで書く定型として `stencil.cpp` に固定 |
| 時間予算切れで提出ゼロ | 0 点 | `BUDGET` を制限時間 -10 秒に設定し、`deadline` 手前で必ず `printf` + ファイル書き出し |

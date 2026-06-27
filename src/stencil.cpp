// =====================================================================
// stencil.cpp  —  ステンシル / 反応拡散 / セルオートマトン用テンプレート
//   2D 格子を行方向で領域分割し、MPI でハロ交換、OpenMP+SVE で更新。
//   対象課題例: ライフゲーム('99) / 化学振動('15) / 森林火災('24) / 拡散・波動系
// ---------------------------------------------------------------------
// 富岳:
//   mpiFCC -Nclang -Ofast -Kfast,openmp,simd -msve-vector-bits=512
//          -DUSE_MPI stencil.cpp -o build/fugaku/stencil
// ローカル単一プロセス検証:
//   g++ -O2 -fopenmp -std=c++17 stencil.cpp -o build/stencil
//
// A64FX 最適化ポイント:
//   * float (16 レーン/SVE) 固定。内側 j ループが unit-stride で自動ベクトル化
//   * SoA 連続配置 + __restrict で別名なしを明示
//   * first-touch 並列初期化 (必須: 忘れると HBM 帯域が半分以下になる)
//   * Irecv/Isend でハロ交換を投げっぱなし → 内部セル更新 → Waitall で完了
//     (現実装では Waitall を先に呼んでいるため、最適化時はここを分割すること)
// =====================================================================
// ─────────────────────────────────────────────────────────────────────
// 🎯 当日の手順 (このファイル = ステンシル/反応拡散/CA/拡散・波動)
//   ① 課題パラメータ H/W/STEPS/D/dt を設定 (下の「課題パラメータ」ブロック)
//   ② update_row ラムダの更新式 (lap/react) を課題のカーネルに書き換え
//   ③ 初期条件 (種まき) を課題に合わせる
//   ④ make stencil && ./build/stencil → tools/fugaku-run.sh stencil <BUDGET_SEC>
//   ⚠️ BUDGET_SEC は当日の実行時間制限を確認して上書き (既定1750は仮の値)
//   ⚠️ react は現在 ×0.0f で無効化中。使う課題なら係数を戻す
//   ⚠️ first-touch 並列初期化と stride パディングは消さない (HBM 帯域が半減する)
// ─────────────────────────────────────────────────────────────────────
#include "common.hpp"
#include "tune_args.hpp"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <cmath>
#include <algorithm>
#ifdef _OPENMP
#include <omp.h>
#endif

int main(int argc, char** argv) {
    int rank = 0, nranks = 1;
#ifdef USE_MPI
    int provided = 0;
    int up = -1, down = -1;
    MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &nranks);
    up   = (rank == 0)          ? MPI_PROC_NULL : rank - 1;
    down = (rank == nranks - 1) ? MPI_PROC_NULL : rank + 1;
#endif

    // ===== 課題パラメータ (ここを書き換える) =============================
    tune::Args args(argc, argv);
    const int H = (int)args.geti("h", 8192), W = (int)args.geti("w", 8192); // 全体格子サイズ
    const int STEPS = (int)args.geti("steps", 200);  // 時間ステップ数 (deadline 超過時は途中で break)
    const float D = 0.20f, dt = 1.0f; // 拡散係数・時間刻み
#ifndef BUDGET_SEC
#define BUDGET_SEC 5.0
#endif
    const double BUDGET = tune::budget(args, BUDGET_SEC); // --budget で実行時上書き
    // ===================================================================

    // 行を各ランクに分配 (余りは先頭ランクへ)
    int base = H / nranks, rem = H % nranks;
    int lh = base + (rank < rem ? 1 : 0); // このランクの内部行数
    // リーディング次元のパディング: W が 2 のべき(例 8192)だと行間が同じキャッシュセットに
    // 写像され n[j]/c[j]/s[j] が衝突して L1/L2 ミスが激増する。8 要素ずらして回避する。
    // (ハロ交換は各行先頭の実 W 要素のみを送るためパディングは透過)
    const int PAD = (int)args.geti("pad", 8);
    size_t stride = (size_t)W + PAD;
    size_t rows = (size_t)lh + 2;         // 上下ゴースト各 1 行

    // first-touch 初期化 (各スレッドが自分の担当行に最初に触れる → CMG ローカル確保)
    std::vector<float> a(rows * stride), b(rows * stride);
    #pragma omp parallel for schedule(static)
    for (int i = 0; i < (int)rows; ++i) {
        float* __restrict pa = &a[(size_t)i * stride];
        float* __restrict pb = &b[(size_t)i * stride];
        for (int j = 0; j < W; ++j) { pa[j] = 0.0f; pb[j] = 0.0f; }
    }
    // 初期値: global 行 H/2 の中央帯に種を撒く。
    // ※ global 座標で撒くことで分割数 (nranks) に依存しない初期条件になる。
    //   → `make test-mpi` で n=1 と n=4 の最終 sum が一致するか比較でき、ハロ交換の正しさを検証できる。
    int row0_global = rank * base + std::min(rank, rem); // このランク先頭の global 行番号
    const int seed_grow = H / 2;
    if (seed_grow >= row0_global && seed_grow < row0_global + lh) {
        int li = seed_grow - row0_global + 1;            // local 行 (+1 は上ゴースト分)
        for (int j = W / 4; j < 3 * W / 4; ++j) a[(size_t)li * stride + j] = 1.0f;
    }

    double t0 = wtime();
    const double deadline = t0 + BUDGET;

    // 1 行更新カーネル (5点ラプラシアン + 反応項。内側 j ループが unit-stride で SVE 化される)。
    // a/b は std::swap でポインタが入れ替わるため毎回キャプチャ参照経由で読む。
    auto update_row = [&](int i) {
        const float* __restrict c = &a[(size_t)i * stride];
        const float* __restrict n = &a[(size_t)(i - 1) * stride];
        const float* __restrict s = &a[(size_t)(i + 1) * stride];
        float* __restrict o = &b[(size_t)i * stride];
        #pragma omp simd
        for (int j = 1; j < W - 1; ++j) {
            float lap = n[j] + s[j] + c[j-1] + c[j+1] - 4.0f * c[j];
            float react = c[j] * (1.0f - c[j]); // 例: ロジスティック反応 (課題で書き換え)
            o[j] = c[j] + dt * (D * lap + 0.0f * react);
        }
    };

    int final_step = 0;
    for (int step = 0; step < STEPS; ++step) {
        final_step = step + 1;
        // ---- ハロ交換を非ブロッキングで投げる ----
#ifdef USE_MPI
        MPI_Request req[4]; int nr = 0;
        MPI_Irecv(&a[0 * stride],          W, MPI_FLOAT, up,   0, MPI_COMM_WORLD, &req[nr++]);
        MPI_Irecv(&a[(rows - 1) * stride], W, MPI_FLOAT, down, 1, MPI_COMM_WORLD, &req[nr++]);
        MPI_Isend(&a[1 * stride],          W, MPI_FLOAT, up,   1, MPI_COMM_WORLD, &req[nr++]);
        MPI_Isend(&a[(size_t)lh * stride], W, MPI_FLOAT, down, 0, MPI_COMM_WORLD, &req[nr++]);
#endif
        // ---- 通信/計算オーバーラップ: ゴーストに依存しない内部行 (2..lh-1) を先に更新 ----
        #pragma omp parallel for schedule(static)
        for (int i = 2; i <= lh - 1; ++i) update_row(i);

        // ---- ゴースト到着を待ってから境界行 (1 と lh) を更新 ----
#ifdef USE_MPI
        MPI_Waitall(nr, req, MPI_STATUSES_IGNORE);
#endif
        update_row(1);
        if (lh >= 2) update_row(lh);

        std::swap(a, b);
        // deadline チェック: STEPS 完了前に時間切れになっても出力を保証する
        if (step % 10 == 0 && wtime() > deadline) {
            if (rank == 0) std::printf("[stencil] deadline reached at step %d/%d\n", step+1, STEPS);
            break;
        }
    }

    // 全格子の総和を確認用に集約
    double local_sum = 0.0;
    #pragma omp parallel for reduction(+:local_sum) schedule(static)
    for (int i = 1; i <= lh; ++i) {
        const float* __restrict c = &a[(size_t)i * stride];
        for (int j = 0; j < W; ++j) local_sum += c[j];
    }
    double total = local_sum;
#ifdef USE_MPI
    MPI_Reduce(&local_sum, &total, 1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD);
#endif
    double elapsed = wtime() - t0;
    if (rank == 0) {
        std::printf("[stencil] sum=%.6e  steps=%d/%d  %.3fs\n", total, final_step, STEPS, elapsed);
        // correct = 規定 STEPS を完了したか (deadline 切れ=未完=0)。score は確認用チェックサム。
        tune::report(total, (final_step >= STEPS) ? 1 : 0, elapsed);
    }

#ifdef USE_MPI
    MPI_Finalize();
#endif
    return 0;
}

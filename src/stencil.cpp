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
#include "common.hpp"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <cmath>
#ifdef _OPENMP
#include <omp.h>
#endif

int main(int argc, char** argv) {
    (void)argc; (void)argv;
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
    const int H = 8192, W = 8192;     // 全体格子サイズ
    const int STEPS = 200;            // 時間ステップ数 (deadline 超過時は途中で break)
    const float D = 0.20f, dt = 1.0f; // 拡散係数・時間刻み
#ifndef BUDGET_SEC
#define BUDGET_SEC 5.0
#endif
    // ===================================================================

    // 行を各ランクに分配 (余りは先頭ランクへ)
    int base = H / nranks, rem = H % nranks;
    int lh = base + (rank < rem ? 1 : 0); // このランクの内部行数
    size_t stride = (size_t)W;
    size_t rows = (size_t)lh + 2;         // 上下ゴースト各 1 行

    // first-touch 初期化 (各スレッドが自分の担当行に最初に触れる → CMG ローカル確保)
    std::vector<float> a(rows * stride), b(rows * stride);
    #pragma omp parallel for schedule(static)
    for (int i = 0; i < (int)rows; ++i) {
        float* __restrict pa = &a[(size_t)i * stride];
        float* __restrict pb = &b[(size_t)i * stride];
        for (int j = 0; j < W; ++j) { pa[j] = 0.0f; pb[j] = 0.0f; }
    }
    // 初期値: 中央ランクの中段に種を撒く
    if (rank == nranks / 2)
        for (int j = W / 4; j < 3 * W / 4; ++j) a[1 * stride + j] = 1.0f;

    double t0 = wtime();
    const double deadline = t0 + BUDGET_SEC;

    int final_step = 0;
    for (int step = 0; step < STEPS; ++step) {
        final_step = step + 1;
        // ---- ハロ交換 (Irecv/Isend → Waitall) ----
        // 最適化メモ: Waitall を内部セル更新後に移動すると通信/計算オーバーラップが可能
#ifdef USE_MPI
        MPI_Request req[4]; int nr = 0;
        MPI_Irecv(&a[0 * stride],          W, MPI_FLOAT, up,   0, MPI_COMM_WORLD, &req[nr++]);
        MPI_Irecv(&a[(rows - 1) * stride], W, MPI_FLOAT, down, 1, MPI_COMM_WORLD, &req[nr++]);
        MPI_Isend(&a[1 * stride],          W, MPI_FLOAT, up,   1, MPI_COMM_WORLD, &req[nr++]);
        MPI_Isend(&a[(size_t)lh * stride], W, MPI_FLOAT, down, 0, MPI_COMM_WORLD, &req[nr++]);
        MPI_Waitall(nr, req, MPI_STATUSES_IGNORE);
#endif
        // ---- 更新 (5点ラプラシアン + 反応項。内側 j ループが SVE 化される) ----
        #pragma omp parallel for schedule(static)
        for (int i = 1; i <= lh; ++i) {
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
        }
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
    if (rank == 0)
        std::printf("[stencil] sum=%.6e  steps=%d/%d  %.3fs\n", total, final_step, STEPS, elapsed);

#ifdef USE_MPI
    MPI_Finalize();
#endif
    return 0;
}

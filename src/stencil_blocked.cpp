// =====================================================================
// stencil_blocked.cpp  —  温度ブロッキング (temporal blocking) 版ステンシル
//   plain (stencil.cpp) は毎ステップ全格子を HBM から流すためメモリ律速。
//   本実装は BT ステップ分をキャッシュ上で回し、HBM 往復を ~1/BT に削減する。
//   手法: 2D オーバーラップ・タイリング (冗長ハロ付き trapezoid)。
//     各タイル (RB×CB) は上下左右に BT セルの冗長ハロを読み込み、
//     BT ステップ進めるごとに有効領域が 1 ずつ縮む。BT 後にタイル本体が正しくなる。
//   MPI: ランク境界は BT 段の deep-halo を BT ステップごとに 1 回だけ交換 (通信回避)。
// ---------------------------------------------------------------------
// 富岳:  mpiFCCpx -Nclang -Ofast -Kfast,openmp,simd,zfill -msve-vector-bits=512
//               -DUSE_MPI stencil_blocked.cpp -o build/fugaku/stencil_blocked
// ローカル: g++ -O2 -fopenmp -std=c++17 stencil_blocked.cpp -o build/stencil_blocked
//
// ⚠️ A64FX チューニング: 効果はタイル寸法に強く依存する。
//   CMG の L2 は 12 コア共有 8MB → スレッドあたり ~680KB に収める必要がある。
//   ((RB+2BT)*(CB+2BT)*4byte*2buf) を 600KB 未満にして CB/RB を実機で調整すること。
//   冗長計算率 ≈ 2BT/RB + 2BT/CB。BT を上げるほど HBM 削減↑だが冗長計算↑。
// ⚠️ BT=1 にすると plain stencil と同じ動作 (回帰確認用)。
//
// 正しさ: 各内部セルは plain と同一の式・同一の入力で STEPS 回更新されるため
//         結果は plain と一致する (make test-mpi の [2/4] で plain と一致を自動確認 (tools/check-mpi.sh))。
// =====================================================================
#include "common.hpp"
#include "tune_args.hpp"
#include <cstdio>
#include <vector>
#include <cmath>
#include <algorithm>
#ifdef _OPENMP
#include <omp.h>
#endif

// ===== 課題パラメータ (stencil.cpp と揃える。検証用に -D で上書き可) ===
#ifndef GH
#define GH 8192
#endif
#ifndef GW
#define GW 8192
#endif
#ifndef GSTEPS
#define GSTEPS 200
#endif
static const int   H = GH, W = GW;
static const float D = 0.20f, dt = 1.0f;
// STEPS / PAD は main で runtime 引数(--steps/--pad)として読む(stencil と公平に比較するため)
#ifndef BUDGET_SEC
#define BUDGET_SEC 5.0
#endif
// ----- 温度ブロッキングのチューニングパラメータ (実機で調整) -----
#ifndef BT
#define BT 4          // 温度ブロック段数 (1 で plain と等価)
#endif
#ifndef RB
#define RB 128        // 行タイル高
#endif
#ifndef CB
#define CB 256        // 列タイル幅
#endif

// 1 スーパーステップ: a(状態 t) から bt ステップ進めて b(状態 t+bt) を作る。
// 内部行は local [BT .. BT+lh-1]、内部列は [1 .. W-2]。冗長ハロで通信せず BT 進める。
static void advance_block(const std::vector<float>& a, std::vector<float>& b,
                          int lh, size_t stride, int bt,
                          bool top_bndry, bool bot_bndry) {
    const int IR0 = BT, IR1 = BT + lh - 1;        // 内部行 (inclusive)
    const int maxrow = lh + 2 * BT - 1;           // a の最終行 index
    const int ntr = (lh + RB - 1) / RB;
    const int ntc = ((W - 2) + CB - 1) / CB;
    const int LH = RB + 2 * BT, LW = CB + 2 * BT; // タイルローカルバッファ寸法 (最大)

    #pragma omp parallel
    {
        std::vector<float> u((size_t)LH * LW), v((size_t)LH * LW);
        #pragma omp for collapse(2) schedule(dynamic)
        for (int tr = 0; tr < ntr; ++tr)
        for (int tc = 0; tc < ntc; ++tc) {
            const int r0 = IR0 + tr * RB, r1 = std::min(r0 + RB, IR1 + 1); // [r0,r1) 内部行
            const int c0 = 1   + tc * CB, c1 = std::min(c0 + CB, W - 1);   // [c0,c1) 内部列
            // 読み込む冗長領域 (a の index 空間, inclusive)
            const int lr0 = std::max(0, r0 - bt),      lr1 = std::min(maxrow, r1 - 1 + bt);
            const int lc0 = std::max(0, c0 - bt),      lc1 = std::min(W - 1, c1 - 1 + bt);
            const int hgt = lr1 - lr0 + 1, wid = lc1 - lc0 + 1;
            // 縮むのは「保持境界に達していない」エッジのみ。
            //   列: col 0 / W-1 は常に領域境界 (保持) → lc0>0 / lc1<W-1 のときだけ cut
            //   行: ランク境界の ghost は隣接データ(状態 t のみ正)=cut。領域端 (top/bot_bndry) は保持。
            const bool top_cut   = (lr0 > 0) || !top_bndry;
            const bool bot_cut   = (lr1 < maxrow) || !bot_bndry;
            const bool left_cut  = (lc0 > 0);
            const bool right_cut = (lc1 < W - 1);

            for (int i = 0; i < hgt; ++i) {
                const float* __restrict src = &a[(size_t)(lr0 + i) * stride + lc0];
                float* __restrict dst = &u[(size_t)i * LW];
                for (int j = 0; j < wid; ++j) dst[j] = src[j];
            }

            for (int s = 1; s <= bt; ++s) {
                // 状態 s で正しい領域 (global): 各 cut エッジが s だけ縮む
                int gr0 = lr0 + (top_cut ? s : 0),   gr1 = lr1 - (bot_cut ? s : 0);
                int gc0 = lc0 + (left_cut ? s : 0),  gc1 = lc1 - (right_cut ? s : 0);
                // 保持するのは「真の領域境界」だけ:
                //   - 列 0 / W-1 は常に領域境界
                //   - 行は領域端 (top/bot_bndry) の ghost のみ保持。
                //     ランク間境界の ghost は隣接の実セルなので冗長に更新する
                //     (保持すると step>=2 で内部が古い ghost を読み誤答になる)。
                const int rlo_hold = top_bndry ? IR0 : 0;
                const int rhi_hold = bot_bndry ? IR1 : maxrow;
                gr0 = std::max(gr0, rlo_hold); gr1 = std::min(gr1, rhi_hold);
                gc0 = std::max(gc0, 1);        gc1 = std::min(gc1, W - 2);
                // v に u を複製してから内部を上書き (保持セルをそのまま残す)
                for (int i = 0; i < hgt; ++i) {
                    const float* __restrict us = &u[(size_t)i * LW];
                    float* __restrict vs = &v[(size_t)i * LW];
                    for (int j = 0; j < wid; ++j) vs[j] = us[j];
                }
                for (int gi = gr0; gi <= gr1; ++gi) {
                    const int i = gi - lr0;
                    const float* __restrict c = &u[(size_t)i * LW];
                    const float* __restrict n = &u[(size_t)(i - 1) * LW];
                    const float* __restrict so = &u[(size_t)(i + 1) * LW];
                    float* __restrict o = &v[(size_t)i * LW];
                    const int jlo = gc0 - lc0, jhi = gc1 - lc0;
                    #pragma omp simd
                    for (int j = jlo; j <= jhi; ++j) {
                        float lap = n[j] + so[j] + c[j - 1] + c[j + 1] - 4.0f * c[j];
                        o[j] = c[j] + dt * (D * lap); // react は課題で追加
                    }
                }
                std::swap(u, v);
            }
            // bt 回 swap 後、結果は u。内部 [r0,r1)×[c0,c1) を b へ書き戻し
            for (int gi = r0; gi < r1; ++gi) {
                const float* __restrict us = &u[(size_t)(gi - lr0) * LW];
                float* __restrict dst = &b[(size_t)gi * stride];
                for (int gj = c0; gj < c1; ++gj) dst[gj] = us[gj - lc0];
            }
        }
    }
}

int main(int argc, char** argv) {
    int rank = 0, nranks = 1;
#ifdef USE_MPI
    int provided = 0, up = -1, down = -1;
    MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &nranks);
    up   = (rank == 0)          ? MPI_PROC_NULL : rank - 1;
    down = (rank == nranks - 1) ? MPI_PROC_NULL : rank + 1;
#endif
    tune::Args args(argc, argv);
    const double BUDGET = tune::budget(args, BUDGET_SEC); // --budget で実行時上書き (BT/RB/CB は -D=リビルド層)
    const int STEPS = (int)args.geti("steps", GSTEPS);    // --steps で上書き (stencil と公平比較)
    const int PAD   = (int)args.geti("pad", 8);           // --pad で上書き
    const int base = H / nranks, rem = H % nranks;
    const int lh = base + (rank < rem ? 1 : 0);
    // lh < BT だと deep-halo 交換が内部行でなく ghost を含み MPI 分割で誤結果。明示停止。
    if (lh < (int)BT) {
        std::fprintf(stderr,    // 失敗したランク自身が出す (lh<BT は rank0 とは限らない)
            "[blocked] ERROR: rank=%d 局所行 lh=%d < BT=%d (nranks=%d が H=%d に対し多すぎ)。ランクを減らすか BT を下げる\n",
            rank, lh, (int)BT, nranks, H);
#ifdef USE_MPI
        MPI_Abort(MPI_COMM_WORLD, 1);
#endif
        return 1;
    }
    const size_t stride = (size_t)W + PAD;
    const size_t rows = (size_t)lh + 2 * BT;      // 上下に BT 段の deep-ghost
    const bool top_bndry = (rank == 0), bot_bndry = (rank == nranks - 1);

    std::vector<float> a(rows * stride), b(rows * stride);
    #pragma omp parallel for schedule(static)
    for (int i = 0; i < (int)rows; ++i) {
        float* __restrict pa = &a[(size_t)i * stride];
        float* __restrict pb = &b[(size_t)i * stride];
        for (int j = 0; j < W; ++j) { pa[j] = 0.0f; pb[j] = 0.0f; }
    }
    // 種まき: global 行 H/2 の中央帯 (stencil.cpp と同一 → sum/sumsq/chk を直接比較できる)
    const int row0_global = rank * base + std::min(rank, rem);
    const int seed_grow = H / 2;
    if (seed_grow >= row0_global && seed_grow < row0_global + lh) {
        const int li = BT + (seed_grow - row0_global);   // 内部行は local [BT..]
        for (int j = W / 4; j < 3 * W / 4; ++j) a[(size_t)li * stride + j] = 1.0f;
    }

    double t0 = wtime();
    const double deadline = t0 + BUDGET;
    int done = 0;
    for (int t = 0; t < STEPS; t += BT) {
        const int bt = std::min((int)BT, STEPS - t);
#ifdef USE_MPI
        // BT 段 deep-halo を 1 回だけ交換 (通信回避: 毎ステップではなく BT ステップに 1 回)
        MPI_Request req[4]; int nr = 0;
        MPI_Irecv(&a[0],                           BT * (int)stride, MPI_FLOAT, up,   0, MPI_COMM_WORLD, &req[nr++]);
        MPI_Irecv(&a[(size_t)(BT + lh) * stride],  BT * (int)stride, MPI_FLOAT, down, 1, MPI_COMM_WORLD, &req[nr++]);
        MPI_Isend(&a[(size_t)BT * stride],         BT * (int)stride, MPI_FLOAT, up,   1, MPI_COMM_WORLD, &req[nr++]);
        MPI_Isend(&a[(size_t)lh * stride],         BT * (int)stride, MPI_FLOAT, down, 0, MPI_COMM_WORLD, &req[nr++]);
        MPI_Waitall(nr, req, MPI_STATUSES_IGNORE);
#endif
        advance_block(a, b, lh, stride, bt, top_bndry, bot_bndry);
        std::swap(a, b);
        done = t + bt;
        if (wtime() > deadline) { if (rank == 0) std::printf("[blocked] deadline at step %d/%d\n", done, STEPS); break; }
    }

    // 3 種のチェックサム: sum(質量) / sumsq(エネルギー) / chk(位置重み)。
    // plain との一致検証用 (位置重みは場の形まで弁別する)。
    double loc[3] = {0, 0, 0};
    #pragma omp parallel for schedule(static) reduction(+:loc[:3])
    for (int g = 0; g < lh; ++g) {
        const int gr = row0_global + g;                  // global 行 (分割非依存)
        const float* __restrict c = &a[(size_t)(BT + g) * stride];
        for (int j = 0; j < W; ++j) {
            double x = c[j];
            loc[0] += x; loc[1] += x * x; loc[2] += x * ((double)gr * W + j);
        }
    }
    double tot[3] = {loc[0], loc[1], loc[2]};
#ifdef USE_MPI
    MPI_Reduce(loc, tot, 3, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD);
#endif
    double elapsed = wtime() - t0;
    if (rank == 0) {
        std::printf("[blocked] sum=%.6e sumsq=%.6e chk=%.6e  steps=%d/%d  BT=%d RB=%d CB=%d  %.3fs\n",
                    tot[0], tot[1], tot[2], done, STEPS, (int)BT, (int)RB, (int)CB, elapsed);
        tune::report(tot[0], (done >= STEPS) ? 1 : 0, elapsed);
    }
#ifdef USE_MPI
    MPI_Finalize();
#endif
    return 0;
}

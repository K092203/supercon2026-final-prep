// =====================================================================
// skeleton.cpp  —  SuperCon2026 (富岳 / A64FX) 共通スケルトン
//   MPI + OpenMP ハイブリッド / 高分解能計測 / スレッド毎高速乱数 / 時間予算
// ---------------------------------------------------------------------
// 富岳 (富士通 clang モード):
//   mpiFCC -Nclang -Ofast -Kfast,openmp,simd -msve-vector-bits=512
//          -DUSE_MPI skeleton.cpp -o build/fugaku/skeleton
// GCC 系:
//   mpic++ -O3 -fopenmp -mcpu=a64fx -msve-vector-bits=512
//          -DUSE_MPI skeleton.cpp -o build/skeleton-mpi
// ローカル単一プロセス検証:
//   g++ -O2 -fopenmp -std=c++17 skeleton.cpp -o build/skeleton
//
// 推奨実行 (1 ノード = 4 CMG, CMG ごと 1 ランク × 12 スレッド):
//   export OMP_NUM_THREADS=12 OMP_PROC_BIND=close OMP_PLACES=cores
//   mpiexec -n 4 ./build/fugaku/skeleton
// =====================================================================
#include "common.hpp"
#include <cstdio>
#include <vector>
#include <unistd.h>
#ifdef _OPENMP
#include <omp.h>
#endif

int main(int argc, char** argv) {
    int rank = 0, nranks = 1;
#ifdef USE_MPI
    int provided = 0;
    MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &nranks);
#endif
    int maxth = 1;
#ifdef _OPENMP
    maxth = omp_get_max_threads();
#endif
    (void)argc; (void)argv;
    char host[256] = "local";
    gethostname(host, sizeof(host));

    if (rank == 0)
        std::printf("[env] ranks=%d threads/rank=%d total_cores=%d host=%s\n",
                    nranks, maxth, nranks * maxth, host);

    // スレッドごとに独立な乱数列 (ランク×スレッドで seed を分離)
    std::vector<Rng> rng(maxth);
    for (int t = 0; t < maxth; ++t)
        rng[t].seed(0x5DEECE66DULL ^ ((uint64_t)rank << 32) ^ (uint64_t)t);

    // ===== ここに課題本体を書く ==========================================
    // ハイブリッド課題用スロット: ステンシル評価 + SA を組み合わせる場合は
    //   stencil.cpp のカーネル関数を切り出してここから呼ぶ

    const double BUDGET = 5.0;           // 本選では制限時間 -10 秒に設定
    const double deadline = wtime() + BUDGET;
    long long local_count = 0;
    double t0 = wtime();

    #pragma omp parallel reduction(+:local_count)
    {
        int tid = 0;
#ifdef _OPENMP
        tid = omp_get_thread_num();
#endif
        Rng& r = rng[tid];
        while (wtime() < deadline) {
            for (int i = 0; i < (1 << 16); ++i) {
                double x = r.uniform(), y = r.uniform();
                if (x * x + y * y <= 1.0) ++local_count;
            }
        }
    }

    long long global_count = local_count;
#ifdef USE_MPI
    MPI_Allreduce(&local_count, &global_count, 1, MPI_LONG_LONG, MPI_SUM, MPI_COMM_WORLD);
#endif
    double elapsed = wtime() - t0;
    if (rank == 0)
        std::printf("[result] in_circle=%lld  elapsed=%.3fs\n", global_count, elapsed);
    // ===================================================================

#ifdef USE_MPI
    MPI_Finalize();
#endif
    return 0;
}

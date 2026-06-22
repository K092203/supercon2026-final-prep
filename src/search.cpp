// =====================================================================
// search.cpp  —  並列局所探索 / 焼きなまし (SA) テンプレート
//   各スレッドが独立に探索 → ランク内ベスト → MPI(MAXLOC) で全体ベスト共有。
//   対象課題例: 敷詰め('10) / 配置('07) / スケジューリング('05) /
//               Graph Golf('16) / 変形テトリス('14) など組合せ最適化全般。
// ---------------------------------------------------------------------
// 富岳:
//   mpiFCC -Nclang -Ofast -Kfast,openmp -DUSE_MPI search.cpp -o build/fugaku/search
// ローカル単一プロセス検証:
//   g++ -O2 -fopenmp -std=c++17 search.cpp -o build/search
//
// 設計方針:
//   * 探索本体はスカラ寄り → 48 コア×多ノードの「独立試行」で台数効果
//   * 評価は必ず差分 (delta) で。全評価のやり直しをしない
//   * 提出は何度でも可の運用が多い → SYNC ごとに全体ベストを集約・保存
// =====================================================================
#include "common.hpp"
#include <cstdio>
#include <vector>
#include <cmath>
#include <algorithm>
#ifdef _OPENMP
#include <omp.h>
#endif

// ===== 課題依存部 (ここを差し替える) ==================================
// 例: QUBO — x∈{0,1}^N の x^T Q x を最大化
struct Problem {
    int N;
    std::vector<double> Q; // N×N 対称行列

    double q(int i, int j) const { return Q[(size_t)i * N + j]; }

    // 全評価 O(N²): 初期解評価・デバッグ用
    double cost(const std::vector<uint8_t>& x) const {
        double s = 0;
        for (int i = 0; i < N; ++i) if (x[i]) {
            s += q(i, i);
            for (int j = i+1; j < N; ++j) if (x[j]) s += 2.0 * q(i, j);
        }
        return s;
    }
    // 差分評価 O(N): ビット i を反転したときのコスト変化
    double delta(const std::vector<uint8_t>& x, int i) const {
        double g = q(i, i);
        for (int j = 0; j < N; ++j) if (j != i && x[j]) g += 2.0 * q(i, j);
        return x[i] ? -g : g;
    }
};
// =====================================================================

int main(int argc, char** argv) {
    (void)argc; (void)argv;
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

    // ---- 問題生成 (本選では入力読込に置換) ---
    Problem P; P.N = 400; P.Q.resize((size_t)P.N * P.N);
    { Rng g; g.seed(12345);
      for (int i = 0; i < P.N; ++i) for (int j = i; j < P.N; ++j) {
          double v = g.uniform() * 2.0 - 1.0;
          P.Q[(size_t)i*P.N+j] = v; P.Q[(size_t)j*P.N+i] = v; } }

#ifndef BUDGET_SEC
#define BUDGET_SEC 5.0
#endif
    const double BUDGET = BUDGET_SEC;   // 本選では make fugaku BUDGET_SEC=1750
    const double SYNC   = 0.5;   // この秒ごとに全体ベストを集約
    const double t_end  = wtime() + BUDGET;

    std::vector<uint8_t> best(P.N, 0);
    double best_score = P.cost(best);
    double t_sync = wtime() + SYNC;

    while (wtime() < t_end) {
        double next_sync = std::min(t_sync, t_end);

        // ---- スレッド独立 SA ----
        std::vector<std::vector<uint8_t>> th_best(maxth, best);
        std::vector<double> th_score(maxth, best_score);

        #pragma omp parallel
        {
            int tid = 0;
#ifdef _OPENMP
            tid = omp_get_thread_num();
#endif
            Rng r; r.seed(0xABCDEFULL ^ ((uint64_t)rank << 40) ^ ((uint64_t)tid << 8)
                          ^ (uint64_t)(t_sync * 1e3));
            std::vector<uint8_t> x = best;
            double cur = best_score, T = 1.0;
            std::vector<uint8_t> lb = x; double ls = cur;

            while (wtime() < next_sync) {
                for (int it = 0; it < 20000; ++it) {
                    int i = r.below(P.N);
                    double d = P.delta(x, i);
                    if (d > 0 || r.uniform() < std::exp(d / T)) {
                        x[i] ^= 1; cur += d;
                        if (cur > ls) { ls = cur; lb = x; }
                    }
                }
                T *= 0.999; // 冷却スケジュール (課題に合わせて調整)
                if (T < 1e-3) T = 1.0; // 再加熱
            }
            th_best[tid] = lb; th_score[tid] = ls;
        }

        // ランク内ベスト
        for (int t = 0; t < maxth; ++t)
            if (th_score[t] > best_score) { best_score = th_score[t]; best = th_best[t]; }

        // ---- MPI_MAXLOC でベストランクを特定し解を全員に配布 ----
#ifdef USE_MPI
        struct { double v; int r; } in{best_score, rank}, out{};
        MPI_Allreduce(&in, &out, 1, MPI_DOUBLE_INT, MPI_MAXLOC, MPI_COMM_WORLD);
        MPI_Bcast(best.data(), P.N, MPI_UNSIGNED_CHAR, out.r, MPI_COMM_WORLD);
        best_score = out.v;
        if (rank == 0) { /* ここで best を提出ファイルに保存 */ }
#endif
        t_sync = wtime() + SYNC;
    }

    if (rank == 0)
        std::printf("[search] best=%.6f  ranks=%d threads=%d\n",
                    best_score, nranks, maxth);
#ifdef USE_MPI
    MPI_Finalize();
#endif
    return 0;
}

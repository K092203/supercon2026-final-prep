#pragma once
// SuperCon2026 共通ユーティリティ — すべての .cpp からインクルードする
// ルール: グローバル変数をここに書かない (ODR 違反を防ぐため)
#include <cstdint>
#include <chrono>
#ifdef USE_MPI
#include <mpi.h>
#endif

// wall-clock 秒。MPI 有効時は MPI_Wtime、それ以外は steady_clock を使う。
// parallel_search.cpp の clock() 問題を回避するため全ファイルこれに統一する。
static inline double wtime() {
#ifdef USE_MPI
    return MPI_Wtime();
#else
    using namespace std::chrono;
    return duration<double>(steady_clock::now().time_since_epoch()).count();
#endif
}

// xoshiro256** (splitmix64 でシード) — スレッドごとに 1 インスタンス持つ
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
    double uniform() { return (next() >> 11) * (1.0 / 9007199254740992.0); } // [0,1)

    // Lemire 法: [0,n) を剰余バイアスなしで返す
    // 富士通 clang が __uint128_t をサポートしない場合は double キャスト版にフォールバック
    uint32_t below(uint32_t n) {
#ifdef __SIZEOF_INT128__
        return (uint32_t)(((__uint128_t)next() * n) >> 64);
#else
        // double 経路は next() 最大値が 2^64 に丸められ n を返しうる → クランプで OOB を防ぐ
        uint32_t v = (uint32_t)((double)next() * n * (1.0 / 18446744073709551616.0));
        return v < n ? v : n - 1;
#endif
    }
};

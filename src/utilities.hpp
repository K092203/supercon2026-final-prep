#pragma once
// SuperCon2026 競技コード共通ユーティリティ
// =====================================================================
// 速度最優先: プロダクト規範（エラーハンドリング・過剰抽象化）は適用しない
//
// 使い方 (main.cpp 側):
//   #include "utilities.hpp"
//   #include "solver.cpp"          // solver を単一 TU に結合
//
//   int main() {
//       fastio::init();            // 先頭で一度だけ: stdin を全部読む
//       read_input();
//       solve();
//       write_output();
//       fastio::flush();           // 末尾で一度だけ: obuf を stdout へ書く
//   }
// =====================================================================
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <algorithm>
#include <vector>
#include <chrono>
#ifdef _OPENMP
#include <omp.h>
#endif
#ifdef USE_MPI
#include <mpi.h>
#endif

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// タイマー
//   MPI 有効時は MPI_Wtime (プロセス間で同期)
//   それ以外は std::chrono::steady_clock (モノトニック)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
static inline double wtime() {
#ifdef USE_MPI
    return MPI_Wtime();
#else
    using namespace std::chrono;
    return duration<double>(steady_clock::now().time_since_epoch()).count();
#endif
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 高速乱数: xoshiro256** (splitmix64 シード)
//
//   設計:
//     スレッドごとに独立インスタンスを持つ。グローバル共有不可 (競合が起きる)
//     seed() に (rank*maxth + tid) を渡して完全に独立させる
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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
    uint32_t below(uint32_t n) {
#ifdef __SIZEOF_INT128__
        return (uint32_t)(((__uint128_t)next() * n) >> 64);
#else
        return (uint32_t)((double)next() * n * (1.0 / 18446744073709551616.0));
#endif
    }
};

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 超高速 I/O (fread ベース)
//
// フロー:
//   stdin ──fread──▶ ibuf[8MB] ──ri()/rll()──▶ [solver] ──wi()──▶ obuf[8MB] ──fwrite──▶ stdout
//
// なぜ fread か:
//   cin/scanf は内部で毎回システムコールを発行する。fread は stdin 全体を
//   一度に kernel バッファからユーザランドに転送する。
//   A64FX の HBM2 は帯域が広いので、まとめ読みでキャッシュ効率が上がる。
//
// 注意:
//   - init()  は main() 先頭で一度だけ呼ぶ (全 stdin を読み込む)
//   - flush() は main() 末尾で一度だけ呼ぶ (obuf を stdout へ書く)
//   - 入力が 8MB を超える場合は IBUF_SIZE を増やすこと
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
namespace fastio {
    static constexpr int IBUF_SIZE = 1 << 23; // 8 MB
    static constexpr int OBUF_SIZE = 1 << 23; // 8 MB

    // グローバル静的バッファ: ループ内 malloc/new は一切行わない
    static char ibuf[IBUF_SIZE];
    static char obuf[OBUF_SIZE];
    static int  ipos = 0, ilen = 0, opos = 0;

    inline void init()  { ilen = (int)fread(ibuf, 1, IBUF_SIZE, stdin); }
    inline void flush() { fwrite(obuf, 1, (size_t)opos, stdout); opos = 0; }

    inline char gc() { return (ipos < ilen) ? ibuf[ipos++] : '\0'; }
    inline void skip_ws() { while (ipos < ilen && (unsigned char)ibuf[ipos] <= ' ') ++ipos; }

    // 符号付き整数読み込み
    inline int ri() {
        skip_ws();
        int x = 0, s = 1;
        if (ipos < ilen && ibuf[ipos] == '-') { s = -1; ++ipos; }
        while (ipos < ilen && (unsigned char)ibuf[ipos] >= '0') x = x * 10 + (ibuf[ipos++] - '0');
        return x * s;
    }
    inline long long rll() {
        skip_ws();
        long long x = 0; int s = 1;
        if (ipos < ilen && ibuf[ipos] == '-') { s = -1; ++ipos; }
        while (ipos < ilen && (unsigned char)ibuf[ipos] >= '0') x = x * 10 + (ibuf[ipos++] - '0');
        return x * s;
    }
    inline double rf() {
        skip_ws();
        double x = 0; int s = 1, frac = 0; double scale = 1.0;
        if (ipos < ilen && ibuf[ipos] == '-') { s = -1; ++ipos; }
        while (ipos < ilen && ibuf[ipos] != '.') {
            if ((unsigned char)ibuf[ipos] < '0') break;
            x = x * 10 + (ibuf[ipos++] - '0');
        }
        if (ipos < ilen && ibuf[ipos] == '.') {
            ++ipos;
            while (ipos < ilen && (unsigned char)ibuf[ipos] >= '0') {
                x = x * 10 + (ibuf[ipos++] - '0'); scale *= 10;
                (void)frac;
            }
            x /= scale;
        }
        return x * s;
    }
    // 空白区切り文字列読み込み
    inline int rs(char* dst) {
        skip_ws();
        int len = 0;
        while (ipos < ilen && (unsigned char)ibuf[ipos] > ' ') dst[len++] = ibuf[ipos++];
        dst[len] = '\0';
        return len;
    }

    // 整数書き込み
    inline void wi(int x) {
        if (x < 0) { obuf[opos++] = '-'; x = -x; }
        if (x == 0) { obuf[opos++] = '0'; return; }
        char tmp[12]; int len = 0;
        while (x > 0) { tmp[len++] = (char)('0' + x % 10); x /= 10; }
        for (int i = len - 1; i >= 0; --i) obuf[opos++] = tmp[i];
    }
    inline void wll(long long x) {
        if (x < 0) { obuf[opos++] = '-'; x = -x; }
        if (x == 0) { obuf[opos++] = '0'; return; }
        char tmp[20]; int len = 0;
        while (x > 0) { tmp[len++] = (char)('0' + x % 10); x /= 10; }
        for (int i = len - 1; i >= 0; --i) obuf[opos++] = tmp[i];
    }
    inline void wf(double x, int prec = 6) {
        char tmp[64]; snprintf(tmp, sizeof(tmp), "%.*f", prec, x);
        for (int i = 0; tmp[i]; ++i) obuf[opos++] = tmp[i];
    }
    inline void wc(char c)        { obuf[opos++] = c; }
    inline void ws(const char* s) { while (*s) obuf[opos++] = *s++; }
    inline void wn()               { obuf[opos++] = '\n'; }  // 改行ショートカット
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 時間予算ヘルパー
//
//   Budget budget(1750.0);       // 1750 秒のタイマーをセット
//   while (!budget.expired()) { ... }
//   fprintf(stderr, "%.3f s remaining\n", budget.remaining());
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
struct Budget {
    double deadline;
    explicit Budget(double sec) : deadline(wtime() + sec) {}
    bool   expired()   const { return wtime() >= deadline; }
    double remaining() const { return deadline - wtime(); }
};

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ビット演算ユーティリティ
//   OpenMP + ビット演算を組み合わせた BFS/集合演算に使う
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
inline int popcnt(unsigned int x)        { return __builtin_popcount(x); }
inline int popcnt(unsigned long long x)  { return __builtin_popcountll(x); }
inline int ctz32(unsigned int x)         { return __builtin_ctz(x); }       // 末尾0の個数
inline int clz32(unsigned int x)         { return __builtin_clz(x); }       // 先頭0の個数
inline int msb32(unsigned int x)         { return 31 - __builtin_clz(x); }  // 最上位ビット位置
inline int lsb32(unsigned int x)         { return x & (-x); }               // 最下位ビット取り出し

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// OpenMP ヘルパー
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
inline int omp_tid() {
#ifdef _OPENMP
    return omp_get_thread_num();
#else
    return 0;
#endif
}
inline int omp_nth() {
#ifdef _OPENMP
    return omp_get_max_threads();
#else
    return 1;
#endif
}

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
// wtime() / Rng (xoshiro256**) は common.hpp に一元化する。
// 二重定義 (contest.cpp が common.hpp と両方 include した場合のコンパイルエラー) を防ぐため
// ここでは再定義せず common.hpp を取り込む。
#include "common.hpp"   // -> cstdint / chrono / mpi.h / wtime() / Rng
#include <cstdio>
#include <cstring>
#include <cmath>
#include <algorithm>
#include <vector>
#ifdef _OPENMP
#include <omp.h>
#endif

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
    static constexpr int IBUF_SIZE = 1 << 26; // 64 MB (本選の大規模入力に備える。足りなければ増やす)
    static constexpr int OBUF_SIZE = 1 << 26; // 64 MB

    // グローバル静的バッファ: ループ内 malloc/new は一切行わない
    static char ibuf[IBUF_SIZE];
    static char obuf[OBUF_SIZE];
    static int  ipos = 0, ilen = 0, opos = 0;

    // EOF まで読み切る。単発 fread は 1 回のシステムコール上限で途中打ち切りになり、
    // 入力が大きいとサイレントに WA を生む。ループで満杯まで読む。
    inline void init() {
        ilen = 0;
        size_t got;
        while (ilen < IBUF_SIZE &&
               (got = fread(ibuf + ilen, 1, (size_t)(IBUF_SIZE - ilen), stdin)) > 0)
            ilen += (int)got;
        if (ilen >= IBUF_SIZE)
            fprintf(stderr, "[fastio] WARNING: input filled IBUF_SIZE(%d). 入力切り捨ての恐れ → IBUF_SIZE を増やせ\n", IBUF_SIZE);
    }
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

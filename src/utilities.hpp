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
#include <cstdlib>
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
//   stdin ──fread──▶ ibuf[64MB] ──ri()/rll()──▶ [solver] ──wi()──▶ obuf[64MB] ──fwrite──▶ stdout
//
// なぜ fread か:
//   cin/scanf は内部で毎回システムコールを発行する。fread は stdin 全体を
//   一度に kernel バッファからユーザランドに転送する。
//   A64FX の HBM2 は帯域が広いので、まとめ読みでキャッシュ効率が上がる。
//
// 注意:
//   - init()  は main() 先頭で一度だけ呼ぶ (全 stdin を読み込む)
//   - flush() は main() 末尾で一度だけ呼ぶ (obuf を stdout へ書く)
//   - 入力が 64MB を超える場合は IBUF_SIZE を増やすこと
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
        if (ilen >= IBUF_SIZE && fgetc(stdin) != EOF) {
            fprintf(stderr, "[fastio] ERROR: 入力が IBUF_SIZE(%d) を超えたため中止します。部分入力で続行すると WA になります。src/utilities.hpp の IBUF_SIZE を増やしてください。\n", IBUF_SIZE);
            std::exit(1);
        }
    }
    inline void flush() { fwrite(obuf, 1, (size_t)opos, stdout); opos = 0; }

    inline char gc() { return (ipos < ilen) ? ibuf[ipos++] : '\0'; }
    inline void skip_ws() { while (ipos < ilen && (unsigned char)ibuf[ipos] <= ' ') ++ipos; }

    // 符号付き整数読み込み
    inline int ri() {
        skip_ws();
        int x = 0, s = 1;
        if (ipos < ilen && ibuf[ipos] == '-') { s = -1; ++ipos; }
        while (ipos < ilen && (unsigned char)ibuf[ipos] >= '0' && (unsigned char)ibuf[ipos] <= '9') x = x * 10 + (ibuf[ipos++] - '0');
        return x * s;
    }
    inline long long rll() {
        skip_ws();
        long long x = 0; int s = 1;
        if (ipos < ilen && ibuf[ipos] == '-') { s = -1; ++ipos; }
        while (ipos < ilen && (unsigned char)ibuf[ipos] >= '0' && (unsigned char)ibuf[ipos] <= '9') x = x * 10 + (ibuf[ipos++] - '0');
        return x * s;
    }
    inline double rf() {
        skip_ws();
        double x = 0; int s = 1;
        if (ipos < ilen && ibuf[ipos] == '-') { s = -1; ++ipos; }
        else if (ipos < ilen && ibuf[ipos] == '+') { ++ipos; }
        // 整数部
        while (ipos < ilen && (unsigned char)ibuf[ipos] >= '0' && (unsigned char)ibuf[ipos] <= '9')
            x = x * 10 + (ibuf[ipos++] - '0');
        // 小数部
        if (ipos < ilen && ibuf[ipos] == '.') {
            ++ipos; double scale = 1.0;
            while (ipos < ilen && (unsigned char)ibuf[ipos] >= '0' && (unsigned char)ibuf[ipos] <= '9') {
                x = x * 10 + (ibuf[ipos++] - '0'); scale *= 10;
            }
            x /= scale;
        }
        // 指数部 [eE][+-]?digits
        if (ipos < ilen && (ibuf[ipos] == 'e' || ibuf[ipos] == 'E')) {
            ++ipos; int es = 1, e = 0;
            if (ipos < ilen && (ibuf[ipos] == '+' || ibuf[ipos] == '-')) { if (ibuf[ipos] == '-') es = -1; ++ipos; }
            while (ipos < ilen && (unsigned char)ibuf[ipos] >= '0' && (unsigned char)ibuf[ipos] <= '9')
                e = e * 10 + (ibuf[ipos++] - '0');
            x *= std::pow(10.0, (double)(es * e));
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

    // 整数書き込み。
    //   * 各書き込み前に残量を確認し、不足なら flush() して obuf 溢れ(64MB超出力)を防ぐ。
    //   * 符号付き最小値(INT_MIN/LLONG_MIN)の `-x` は符号付きオーバーフロー(UB)になるため、
    //     unsigned で絶対値を作って桁分解する。
    inline void wi(int x) {
        if (opos + 12 > OBUF_SIZE) flush();
        if (x < 0) obuf[opos++] = '-';
        unsigned u = (x < 0) ? (0u - (unsigned)x) : (unsigned)x;
        if (u == 0) { obuf[opos++] = '0'; return; }
        char tmp[12]; int len = 0;
        while (u > 0) { tmp[len++] = (char)('0' + u % 10); u /= 10; }
        for (int i = len - 1; i >= 0; --i) obuf[opos++] = tmp[i];
    }
    inline void wll(long long x) {
        if (opos + 24 > OBUF_SIZE) flush();
        if (x < 0) obuf[opos++] = '-';
        unsigned long long u = (x < 0) ? (0ULL - (unsigned long long)x) : (unsigned long long)x;
        if (u == 0) { obuf[opos++] = '0'; return; }
        char tmp[24]; int len = 0;
        while (u > 0) { tmp[len++] = (char)('0' + u % 10); u /= 10; }
        for (int i = len - 1; i >= 0; --i) obuf[opos++] = tmp[i];
    }
    inline void wf(double x, int prec = 6) {
        if (opos + 80 > OBUF_SIZE) flush();
        char tmp[64]; snprintf(tmp, sizeof(tmp), "%.*f", prec, x);
        for (int i = 0; tmp[i]; ++i) obuf[opos++] = tmp[i];
    }
    inline void wc(char c)        { if (opos + 1 > OBUF_SIZE) flush(); obuf[opos++] = c; }
    inline void ws(const char* s) { while (*s) { if (opos + 1 > OBUF_SIZE) flush(); obuf[opos++] = *s++; } }
    inline void wn()              { if (opos + 1 > OBUF_SIZE) flush(); obuf[opos++] = '\n'; }  // 改行
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
//   ⚠️ ctz32/clz32/msb32 は x==0 で未定義動作。空集合(0)を渡さないこと。
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

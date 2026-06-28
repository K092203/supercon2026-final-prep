#pragma once
// =====================================================================
// tune_args.hpp — SuperCon2026 オートチューニング 共通規約
//   全テンプレが #include し、(1) argv / env からチューニング引数を読み、
//   (2) 末尾に機械可読の #TUNE 行を stderr へ出す。
//   測定ループ tools/tune-sweep.sh はこの #TUNE 行を抽出して results.csv を作る。
//
// 使い方:
//   #include "tune_args.hpp"
//   int main(int argc, char** argv){
//       // ... MPI_Init の後 ...
//       tune::Args args(argc, argv);
//       const double cooling = args.getf("cooling", 0.999);  // --cooling 0.99 / TUNE_COOLING=0.99
//       const double BUDGET  = tune::budget(args, BUDGET_SEC);// --budget で実行時上書き
//       // ... solve ...
//       if (rank == 0) tune::report(score, correct, elapsed); // 末尾で 1 回 (rank0)
//   }
//
// 設計方針:
//   * stdout は「課題の解」専用。測定行 (#TUNE) は stderr に出して衝突を避ける。
//   * 値の優先順位は argv > env(TUNE_<KEY>) > デフォルト。
//   * pure C++17 / 追加依存なし。g++ / mpic++ / mpiFCCpx すべてでコンパイル可能。
//   * リビルド要のノブ (stencil_blocked の BT/RB/CB 等の -D 定数) はここでは扱わない。
//     それらは「事前ビルドした別バイナリ」= configs の bin 列で切り替える (3層モデルの外側)。
// =====================================================================
#include "common.hpp"   // wtime()
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <cstdlib>
#include <cstdio>
#include <cctype>

namespace tune {

// "sa-temp" -> "TUNE_SA_TEMP" (env フォールバック用キー)
inline std::string env_key(const std::string& k) {
    std::string e = "TUNE_";
    for (char c : k) e += (c == '-') ? '_' : (char)std::toupper((unsigned char)c);
    return e;
}

// argv / env からキー=値を解釈する軽量パーサ。
//   --key value / --key=value / --flag(値なし=has で真) を受ける。
struct Args {
    std::unordered_map<std::string, std::string> kv;   // --key value / --key=value
    std::unordered_set<std::string> flagset;           // --flag (値なし) は別管理

    Args(int argc, char** argv) {
        for (int i = 1; i < argc; ++i) {
            std::string a = argv[i];
            if (a.rfind("--", 0) != 0) continue;   // --xxx 以外は無視
            a = a.substr(2);
            auto eq = a.find('=');
            if (eq != std::string::npos) {                       // --key=value (value は空もあり)
                kv[a.substr(0, eq)] = a.substr(eq + 1);
            } else if (i + 1 < argc && std::string(argv[i + 1]).rfind("--", 0) != 0) {
                kv[a] = argv[++i];                                // --key value
            } else {
                flagset.insert(a);                               // --flag (bare): 値として読ませない
            }
        }
    }

    // argv(非空値のみ) > env。値なしフラグ・空値(--key=)は「未設定」扱い → 既定値へ倒す。
    //   これで "--cooling"(値なし) や "--cooling="(空) が silent に 1.0/0.0 へ化けるのを防ぐ。
    const char* raw(const std::string& k) const {
        auto it = kv.find(k);
        if (it != kv.end()) return it->second.empty() ? nullptr : it->second.c_str();
        const char* e = std::getenv(env_key(k).c_str());
        return (e && *e) ? e : nullptr;   // 空文字 env (TUNE_X="") も未設定扱い
    }
    bool has(const std::string& k) const {
        return kv.count(k) || flagset.count(k) || std::getenv(env_key(k).c_str()) != nullptr;
    }
    // 数値は strtod/strtoll + endptr で「全体が数値か」を検証し、不正(--budget abc 等)は既定へ。
    //   atof/atoll は不正値を黙って 0 にし、budget=0(即時 deadline)等の事故を生むため使わない。
    double getf(const std::string& k, double def) const {
        const char* v = raw(k); if (!v) return def;
        char* end = nullptr; double r = std::strtod(v, &end);
        return (end != v && *end == '\0') ? r : def;
    }
    long long geti(const std::string& k, long long def) const {
        const char* v = raw(k); if (!v) return def;
        char* end = nullptr; long long r = std::strtoll(v, &end, 10);
        return (end != v && *end == '\0') ? r : def;
    }
    std::string gets(const std::string& k, const std::string& def) const { const char* v = raw(k); return v ? std::string(v) : def; }
};

// 予約キー --budget(秒)。あれば実行時上書き、無ければコンパイル時 def。
//   これで再コンパイルせず全構成を同一予算に揃えられる。
inline double budget(const Args& a, double def) { return a.getf("budget", def); }

// rank0 が末尾で 1 回呼ぶ。stderr に機械可読 1 行を出す:
//   #TUNE elapsed=<sec> score=<val> correct=<0|1>
//   elapsed は速度の代表値、score は最大化したい量 (無ければ 0)、correct は正誤(0/1)。
inline void report(double score, int correct, double elapsed) {
    std::fprintf(stderr, "#TUNE elapsed=%.6f score=%.10g correct=%d\n",
                 elapsed, score, correct);
    std::fflush(stderr);
}

} // namespace tune

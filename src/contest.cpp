// =====================================================================
// contest.cpp  —  本選当日用 雛形 (I/O 配線の実証サンプル)
//   「読む → 解く → 書く」の配線が通ることを示すサンプル実装。
//   当日は solve 部を課題アルゴリズムに、入出力を課題フォーマットに置換する。
//   ※ このサンプルは「N と整数列を読み、合計と最大値を返す」だけ。
//
// ビルド/テスト:
//   make contest         && ./build/contest < tests/sample_01.in   # ローカル
//   make test-contest                                              # sample_01 で実行
//   bash tests/judge.sh tests                                      # *.in/*.out 一括判定
//   make contest-fugaku                                            # 富岳 (mpiFCC)
//
// 配線のポイント (当日はここだけ意識すれば動く):
//   1) fastio::init() を最初に 1 回   … stdin を一括読み込み (大入力は IBUF_SIZE 調整)
//   2) ri()/rll()/rf() で読む         … CUSTOMIZE: 課題の入力形式に合わせる
//   3) 解く                            … CUSTOMIZE: ここを課題アルゴリズムに置換
//   4) wi()/wll()/wf()/ws() で書く     … CUSTOMIZE: 課題の出力形式に合わせる (rank0 のみ)
//   5) fastio::flush() を最後に 1 回   … obuf を stdout へ
//   長時間探索なら Budget budget(秒); while(!budget.expired()){...} で締切管理。
// =====================================================================
#include "utilities.hpp"
#include <climits>

int main(int argc, char** argv) {
    int rank = 0;
#ifdef USE_MPI
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
#else
    (void)argc; (void)argv;
#endif

    // ---- 1) 入力読み込み (CUSTOMIZE: 課題フォーマットに合わせる) ----
    fastio::init();
    int n = fastio::ri();
    std::vector<int> a(n > 0 ? n : 0);
    for (int i = 0; i < n; ++i) a[i] = fastio::ri();

    // ---- 2) 解く (CUSTOMIZE: ここを課題アルゴリズムに置換) ----
    //   例: 合計と最大値を OpenMP リダクションで求める
    long long sum = 0;
    int mx = INT_MIN;
    #pragma omp parallel for reduction(+:sum) reduction(max:mx) schedule(static)
    for (int i = 0; i < n; ++i) { sum += a[i]; if (a[i] > mx) mx = a[i]; }
    if (n == 0) mx = 0;

    // ---- 3) 出力 (CUSTOMIZE: 課題フォーマットに合わせる。rank0 のみ書く) ----
    if (rank == 0) {
        fastio::wll(sum);
        fastio::wc(' ');
        fastio::wi(mx);
        fastio::wn();
        fastio::flush();
    }

#ifdef USE_MPI
    MPI_Finalize();
#endif
    return 0;
}

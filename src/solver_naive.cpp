// =====================================================================
// solver_naive.cpp — 愚直解テンプレート (参照実装)
//   役割: stress.py の "naive"。fast(contest 等)と出力を比較し正しさを担保する。
//   contest.cpp と同じ「parse → solve_naive() → output」の流れ。
//   既定は contest.cpp のサンプルと同一の「N と整数列 → 合計と最大値」を素朴に計算
//   (= sample_01 で contest と同じ出力になり、stress --mode exact の既定が通る)。
//
//   ⚠️ 本選当日:
//     - parse / output を課題の入出力形式に合わせる
//     - solve_naive() を O(N^2) 等「確実に正しい」参照実装に置換する
//       (高速である必要はない。小ケースで fast の正しさを保証するのが目的)
// =====================================================================
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

// CUSTOMIZE: 当日ここを「確実に正しい」参照実装に置換する
static void solve_naive(const vector<int>& a, ll& sum, int& mx) {
    sum = 0;
    mx = a.empty() ? 0 : INT_MIN;
    for (int x : a) { sum += x; if (x > mx) mx = x; }
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);

    // ---- parse (CUSTOMIZE: 課題の入力形式に合わせる) ----
    int n;
    if (!(cin >> n)) return 0;           // 空入力は何も出さない
    if (n < 0) n = 0;
    vector<int> a(n);
    for (int i = 0; i < n; ++i) cin >> a[i];

    // ---- solve ----
    ll sum; int mx;
    solve_naive(a, sum, mx);

    // ---- output (CUSTOMIZE: 課題の出力形式に合わせる) ----
    cout << sum << ' ' << mx << '\n';
    return 0;
}

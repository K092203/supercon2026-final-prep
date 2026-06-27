#!/usr/bin/env bash
# WSL2→富岳 ソースコード転送 + ログインノードでビルド
# 使い方: tools/fugaku-sync.sh [BUDGET_SEC]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$SCRIPT_DIR/fugaku-config.env"

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: $CONFIG が見つかりません"
  echo "  cp $SCRIPT_DIR/fugaku-config.env.template $CONFIG && editor $CONFIG"
  exit 1
fi
source "$CONFIG"

BUDGET_SEC="${1:-${BUDGET_SEC:-1750}}"

echo "=== [1/2] rsync: src/ → REMOTE/src/, Makefile → REMOTE/ ($FUGAKU_HOST)"
# src は REMOTE/src/ へ送る (Makefile が src/xxx.cpp を参照するため。直下に平坦化しない)。
# --delete は src/ 配下のみに限定 = results/ build/ tools/ を絶対に消さない。
rsync -avz --delete "$REPO_ROOT/src/" "$FUGAKU_HOST:$FUGAKU_REMOTE_DIR/src/"
rsync -avz "$REPO_ROOT/Makefile" "$FUGAKU_HOST:$FUGAKU_REMOTE_DIR/"

echo "=== [2/2] build: make fugaku BUDGET_SEC=$BUDGET_SEC (ログインノード)"
# ビルド出力をログへ集約 (fetch が build.log として回収 → mpiFCC エラーを AI が読める)。
# パイプを避け make の終了コードを直接取る (非bash ログインシェルでも PIPESTATUS に
# 依存せず build 失敗を確実に検出する)。
REMOTE_BUILD_LOG="$FUGAKU_REMOTE_DIR/results/_build/build-latest.log"
BUILD_RC=0
ssh "$FUGAKU_HOST" \
  "cd $FUGAKU_REMOTE_DIR && mkdir -p build/fugaku results/_build && \
   make fugaku BUDGET_SEC=$BUDGET_SEC > results/_build/build-latest.log 2>&1" \
  || BUILD_RC=$?

# 成否に関わらずビルドログを手元へ (成功時も AI が警告を読める)
mkdir -p "$REPO_ROOT/results"
rsync -az "$FUGAKU_HOST:$REMOTE_BUILD_LOG" "$REPO_ROOT/results/last-build.log" 2>/dev/null || true
if [ "$BUILD_RC" -ne 0 ]; then
  echo "❌ ビルド失敗 (rc=$BUILD_RC) → results/last-build.log (末尾):"
  tail -30 "$REPO_ROOT/results/last-build.log" 2>/dev/null || true
  exit "$BUILD_RC"
fi

echo "=== sync+build 完了 (results/last-build.log)"

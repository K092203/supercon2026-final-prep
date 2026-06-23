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

echo "=== [1/2] rsync: src/ Makefile → $FUGAKU_HOST:$FUGAKU_REMOTE_DIR/"
rsync -avz --delete --exclude='build/' \
  "$REPO_ROOT/src/" "$REPO_ROOT/Makefile" \
  "$FUGAKU_HOST:$FUGAKU_REMOTE_DIR/"

echo "=== [2/2] build: make fugaku BUDGET_SEC=$BUDGET_SEC (ログインノード)"
ssh "$FUGAKU_HOST" \
  "cd $FUGAKU_REMOTE_DIR && mkdir -p build/fugaku && make fugaku BUDGET_SEC=$BUDGET_SEC"

echo "=== sync+build 完了"

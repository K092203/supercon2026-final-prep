#!/usr/bin/env bash
# =====================================================================
# save_candidate.sh — 提出候補のスナップショット保存 (命綱の複製)
#   本選中に「今なら提出できる」状態を失わないため、src + 実行結果 + 来歴を
#   submissions/ に丸ごと保存する。最終日に過去の安定版へ即戻れるようにする。
#
#   使い方:
#     tools/save_candidate.sh <label> [results_dir] ["note"]
#       label       … stable / best / day2-baseline 等の短いラベル
#       results_dir … 結果スナップショット (既定 results/latest)
#       note        … 自由メモ (なぜ保存するか)
#   例:
#     tools/save_candidate.sh stable results/latest "Day2 valid baseline"
#     tools/save_candidate.sh best   results/latest "Day4 tuned best"
#
#   保存先: submissions/YYYYMMDD-HHMMSS_<label>/  (.gitignore 済み=ローカル成果物)
#   ⚠️ tools/fugaku-config.env は秘密情報のため絶対に保存しない。
# =====================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

LABEL="${1:-}"
RESULTS_DIR="${2:-results/latest}"
NOTE="${3:-}"

if [ -z "$LABEL" ]; then
    echo "usage: tools/save_candidate.sh <label> [results_dir] [\"note\"]" >&2
    exit 2
fi
# label をファイル名安全に正規化 (英数 . _ - のみ)
SAFE_LABEL="$(printf '%s' "$LABEL" | tr -c 'A-Za-z0-9._-' '_')"

TS="$(date +%Y%m%d-%H%M%S)"
DEST="submissions/${TS}_${SAFE_LABEL}"
mkdir -p "$DEST"

# ---- 1) ソース一式 (当日の提出物そのもの) ----
#   fugaku-config.env を誤って含めないため src/ だけをコピー (tools/ は来歴で代替)。
cp -r src "$DEST/src"

# ---- 2) 実行結果スナップショット (あるものだけ) ----
if [ -d "$RESULTS_DIR" ]; then
    for f in meta.json stdout.txt stderr.txt build.log input.sha256 argv.txt env.txt job.sh; do
        [ -f "$RESULTS_DIR/$f" ] && cp "$RESULTS_DIR/$f" "$DEST/$f"
    done
else
    echo "WARNING: results_dir が無い: $RESULTS_DIR (src と来歴のみ保存)" >&2
fi

# ---- 3) 来歴 (どのコード状態か後で再現できるように) ----
git rev-parse HEAD            > "$DEST/git.commit" 2>/dev/null || echo nogit > "$DEST/git.commit"
git status --short            > "$DEST/git.status" 2>/dev/null || true
git diff                      > "$DEST/git.diff"   2>/dev/null || true

# ---- 4) note.md (ラベル・時刻・score・input hash・理由) ----
SCORE="$(grep -o '"score":[^,}]*' "$DEST/meta.json" 2>/dev/null | head -1 || true)"
IN_HASH="$(cat "$DEST/input.sha256" 2>/dev/null || echo "(なし)")"
{
    echo "# 提出候補: ${LABEL}"
    echo ""
    echo "- saved_at: ${TS}"
    echo "- label: ${LABEL}"
    echo "- results_dir: ${RESULTS_DIR}"
    echo "- git_commit: $(cat "$DEST/git.commit")"
    echo "- score(meta): ${SCORE:-(なし)}"
    echo "- input_sha256: ${IN_HASH}"
    echo "- note: ${NOTE:-(なし)}"
} > "$DEST/note.md"

echo "[save_candidate] 保存: $DEST"
ls "$DEST"

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
# 万一 src/ 配下に秘密ファイルが紛れていたら候補から除外する (誤って提出物へ含めない)。
SECRET_GLOBS=('*.env' '*.pem' '*.key' '*.p12' '*.pfx' '*secret*' '*credential*' 'id_rsa*' '*.token')
# ディレクトリ名で秘密を示すパス (例 src/secrets/config.txt は普通名でも中身が秘密)
SECRET_PATHS=('*/secret*/*' '*/secrets/*' '*/credential*/*' '*/private/*' '*/.ssh/*' '*/.env.d/*')
EXCLUDED=()
for g in "${SECRET_GLOBS[@]}"; do
    while IFS= read -r -d '' hit; do
        rm -f "$hit"; EXCLUDED+=("${hit#"$DEST/"}")
    done < <(find "$DEST/src" -type f -iname "$g" -print0 2>/dev/null)
done
for p in "${SECRET_PATHS[@]}"; do
    while IFS= read -r -d '' hit; do
        rm -f "$hit"; EXCLUDED+=("${hit#"$DEST/"}")
    done < <(find "$DEST/src" -type f -ipath "$p" -print0 2>/dev/null)
done
if [ "${#EXCLUDED[@]}" -gt 0 ]; then
    # 重複を畳んで一覧表示
    UNIQ="$(printf '%s\n' "${EXCLUDED[@]}" | sort -u | tr '\n' ' ')"
    echo "WARNING: 秘密と思われるファイル/パスを候補から除外しました: ${UNIQ}" >&2
fi

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
# git.diff に秘密らしき文字列が入っていないか軽く点検し、入っていれば警告 (削除は手動判断)。
if grep -Eiq 'PRIVATE KEY|password|passwd|secret|api[_-]?key|FUGAKU_(USER|GROUP|HOST)=' "$DEST/git.diff" 2>/dev/null; then
    echo "WARNING: $DEST/git.diff に秘密らしき文字列を検出。中身を確認し、不要なら削除してください。" >&2
fi

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

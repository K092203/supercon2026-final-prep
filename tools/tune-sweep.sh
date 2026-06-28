#!/usr/bin/env bash
# =====================================================================
# tune-sweep.sh — 測定ループ (ローカル/富岳 共用・心臓部)
#   configs.tsv の N 構成を順に測り、1 構成ごとに results.csv へ即追記する。
#   ローカル(mpirun)と富岳(mpiexec)で launcher と bindir を差し替えるだけ。
#   → ローカルリハが富岳本番経路をそのまま検証する (経路乖離なし)。
#
# 使い方:
#   tune-sweep.sh <configs.tsv> <results.csv> <launcher> <bindir> <budget_sec> <elapse_sec>
#     launcher : "mpirun --oversubscribe"(local) / "mpiexec"(富岳) ※フラグ込み可
#     bindir   : build/mpi(local) / build/fugaku(富岳)
#     budget_sec: ソルバ 1 回あたりの時間予算 (全構成で統一 → 公平な比較)
#     elapse_sec: ジョブ全体の壁時計上限 (anytime 打切り判定に使う)
#
# 設計の肝:
#   1) 1 構成測るたびに results.csv へ即追記 + sync (時間切れで殺されても全滅しない)
#   2) per-config timeout キャップ (1 構成のハングが全枠を食うのを防ぐ)
#   3) anytime: 残り時間が次の構成に足りなければ break (測れた分を確定して終了)
#   4) elapsed/score/correct は各テンプレが stderr に吐く #TUNE 行から抽出
#      rep 回測って elapsed 中央値・correct は全 rep の AND
# =====================================================================
set -uo pipefail   # -e は使わない (構成ごとに失敗を握り潰して継続するため)
set -f             # noglob: configs の args に * ? [ があっても cwd のファイル名に展開させない

CONFIGS="${1:?configs.tsv}"
RESULTS="${2:?results.csv}"
LAUNCHER="${3:?launcher (例 mpirun / mpiexec)}"
BINDIR="${4:?bindir (例 build/mpi / build/fugaku)}"
BUDGET="${5:?budget_sec}"
ELAPSE="${6:?elapse_sec}"
INPUT="${7:-/dev/null}"   # solver が stdin から問題入力を読む場合に渡す (既定: 入力なし)
if [ "$INPUT" != "/dev/null" ] && [ ! -e "$INPUT" ]; then
    echo "[tune-sweep] WARNING: 入力ファイルが無い: $INPUT → /dev/null を使う" >&2
    INPUT=/dev/null
fi

mkdir -p "$(dirname "$RESULTS")"
echo "id,elapsed,correct,score,exit_code,rep_done,notes" > "$RESULTS"
ERRLOG="$(dirname "$RESULTS")/errors.log"; : > "$ERRLOG"   # 失敗構成の stderr をここに残す

# per-config timeout キャップ: 予算の 1.5 倍 + 60s (起動/終了の余裕)
CAP=$(awk -v b="$BUDGET" 'BEGIN{ printf "%d", b*1.5 + 60 }')
PENALTY=$(awk -v b="$BUDGET" 'BEGIN{ printf "%.6f", b*2 }')  # 不正解/timeout の有限ペナルティ
SWEEP_START=$(date +%s)
TMP_ERR="$(mktemp)"; NORM="$(mktemp)"; trap 'rm -f "$TMP_ERR" "$NORM"' EXIT
# CRLF 正規化 (WSL で Windows 改行のまま編集された configs 対策)。
tr -d '\r' < "$CONFIGS" > "$NORM"
# 重複 id 検出: 同一 id があると results と configs の対応が崩れ、incumbent が構成を取り違える → 中止。
DUP=$(awk -F'\t' 'NF && $1!="id" && $1 !~ /^#/ {print $1}' "$NORM" | sort | uniq -d)
if [ -n "$DUP" ]; then
    echo "[tune-sweep] ERROR: configs に重複 id: $(echo "$DUP" | tr '\n' ' ')" >&2
    echo "             id は一意にすること (取り違え防止のため中止)。" >&2
    exit 1
fi

# 整数フィールド(ranks/omp/rep)のサニタイズ。非数値/0/負 → 1 にフォールバックして警告。
# (放置すると非数値が set -u 下の算術 `((k<=rep))` に渡り sweep 全体がクラッシュする)
posint() {
    local nm="$1" v="$2"
    case "$v" in
        ''|*[!0-9]*) echo "[tune-sweep] WARN $nm='$v' 非数値 → 1" >&2; echo 1; return;;
    esac
    if [ "$v" -lt 1 ]; then echo "[tune-sweep] WARN $nm='$v' <1 → 1" >&2; echo 1; return; fi
    echo "$v"
}

n_done=0; n_total=0
# `|| [ -n "$id" ]`: 末尾に改行が無い configs でも最終行を取りこぼさない。
while IFS=$'\t' read -r id target bin ranks omp rep args || [ -n "${id:-}" ]; do
    # ヘッダ行・空行・コメントをスキップ
    [ -z "${id:-}" ] && continue
    [ "$id" = "id" ] && continue
    case "$id" in \#*) continue;; esac
    n_total=$((n_total+1))
    args="${args:-}"
    ranks=$(posint "id=$id ranks" "${ranks:-1}")
    if [ -n "${TUNE_EXPECT_RANKS:-}" ] && [ "$ranks" != "$TUNE_EXPECT_RANKS" ]; then
        echo "[tune-sweep] WARN id=$id ranks=$ranks が想定($TUNE_EXPECT_RANKS)と相違。max-proc-per-node は投入時固定のため mis-pin の恐れ。" >&2
    fi
    omp=$(posint   "id=$id omp"   "${omp:-1}")
    rep=$(posint   "id=$id rep"   "${rep:-1}")

    # ---- anytime: 残り時間が (budget*rep + 余裕) に満たなければ打ち切り ----
    now=$(date +%s); spent=$((now - SWEEP_START))
    need=$(awk -v b="$BUDGET" -v r="$rep" 'BEGIN{ printf "%d", b*r + 10 }')  # 計測 + 起動余裕
    if [ $((ELAPSE - spent)) -lt "$need" ]; then
        echo "$id,$PENALTY,0,0,0,0,anytime-break(残り$((ELAPSE-spent))s<必要${need}s)" >> "$RESULTS"; sync
        echo "[tune-sweep] anytime 打切り: id=$id (残り $((ELAPSE-spent))s)" >&2
        continue
    fi

    export OMP_NUM_THREADS="$omp" OMP_PROC_BIND=close OMP_PLACES=cores TUNE_BUDGET="$BUDGET"
    BIN="$BINDIR/$bin"
    if [ ! -x "$BIN" ]; then
        echo "$id,$PENALTY,0,0,127,0,missing-bin($bin)" >> "$RESULTS"; sync
        echo "[tune-sweep] バイナリ無し: $BIN" >&2; continue
    fi

    # ---- rep 回計測 → "elapsed score correct" を集める ----
    measures=""; last_exit=0
    for ((k=1; k<=rep; k++)); do
        # <"$INPUT" 必須: mpirun/mpiexec は stdin を食う → while read の configs を
        #   消費して 2 構成目以降が読めなくなる。launcher の stdin を入力ファイル(既定/dev/null)に固定。
        # shellcheck disable=SC2086  # $LAUNCHER / $args は意図的に単語分割
        timeout "$CAP" $LAUNCHER -n "$ranks" "$BIN" $args --budget "$BUDGET" <"$INPUT" >/dev/null 2>"$TMP_ERR"
        last_exit=$?
        line=$(grep '^#TUNE' "$TMP_ERR" | tail -1)
        if [ "$last_exit" -ne 0 ] || [ -z "$line" ]; then
            # 非ゼロ終了(crash/abort/timeout)は #TUNE が出ていても信用しない → 失敗扱い
            measures+="$PENALTY 0 0"$'\n'
            { echo "== id=$id rep=$k exit=$last_exit =="; tail -20 "$TMP_ERR"; } >> "$ERRLOG"
        else
            el=$(sed -n 's/.*elapsed=\([0-9.eE+-]*\).*/\1/p' <<<"$line")
            sc=$(sed -n 's/.*score=\([0-9.eE+-]*\).*/\1/p' <<<"$line")
            co=$(sed -n 's/.*correct=\([0-9]*\).*/\1/p' <<<"$line")
            measures+="${el:-$PENALTY} ${sc:-0} ${co:-0}"$'\n'
        fi
    done

    # ---- 集約: elapsed 中央値・その run の score・correct は全 rep AND ----
    agg=$(printf '%s' "$measures" | awk '
        NF>=3 { el[++n]=$1; sc[n]=$2; if($3+0==0) bad=1; co[n]=$3 }
        END{
            if(n==0){ print "NA 0 0 0"; exit }
            for(i=1;i<=n;i++) o[i]=i
            for(i=1;i<=n;i++) for(j=i+1;j<=n;j++) if(el[o[j]]+0<el[o[i]]+0){t=o[i];o[i]=o[j];o[j]=t}
            m=o[int((n-1)/2)+1]                       # 下側中央値
            printf "%.6f %s %d %d\n", el[m]+0, sc[m], (bad?0:1), n
        }')
    el_med=$(awk '{print $1}' <<<"$agg")
    sc_med=$(awk '{print $2}' <<<"$agg")
    correct=$(awk '{print $3}' <<<"$agg")
    rep_done=$(awk '{print $4}' <<<"$agg")
    note="ok"
    if [ "$correct" -eq 0 ]; then
        if   [ "$last_exit" -eq 124 ]; then note="timeout"
        elif [ "$last_exit" -ne 0   ]; then note="exit=$last_exit"
        else note="incorrect"; fi
    fi

    echo "$id,$el_med,$correct,$sc_med,$last_exit,$rep_done,$note" >> "$RESULTS"; sync
    n_done=$((n_done+1))
    echo "[tune-sweep] id=$id elapsed=$el_med correct=$correct score=$sc_med ($n_done/$n_total)" >&2
done < "$NORM"

echo "[tune-sweep] 完了: $n_done 構成を測定 → $RESULTS" >&2

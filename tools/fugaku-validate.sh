#!/usr/bin/env bash
# =====================================================================
# fugaku-validate.sh — fugaku-config.env の値を検証する共通モジュール (sourced)
#   富岳系スクリプト(sync/submit/tune/fetch/wait/cancel)が `source fugaku-config.env`
#   の直後に source して使う。remote shell / PJM ジョブへ素で埋まる設定値に空白・改行・
#   シェルメタ文字があれば投入前に停止する (fail-closed。エスケープより安全側)。
#
#   ※ source 専用。検証 NG で `exit 2` するため、呼び出し元スクリプトが停止する。
#   ※ case の *[!class]* は改行も「class外の1文字」として捕捉するため、改行混入も自動で弾く。
# =====================================================================

_cfg_safe() {      # 必須・識別子/パス用: 英数 . _ / @ - のみ (host に : は不要なので不許可)
    local name="$1" val="${2-}"
    [ -n "$val" ] || { echo "ERROR: $name が未設定 (tools/fugaku-config.env)" >&2; exit 2; }
    case "$val" in *[!A-Za-z0-9._/@-]*)
        echo "ERROR: $name に使用不可文字: '$val' (英数 . _ / @ - のみ)" >&2; exit 2 ;; esac
}
_cfg_int() {       # 必須・1 以上の整数 (0 / 先頭ゼロは不可)
    local name="$1" val="${2-}"
    case "$val" in ''|*[!0-9]*|0*)
        echo "ERROR: $name は 1 以上の整数で指定: '$val'" >&2; exit 2 ;; esac
}
_cfg_elapse() {    # 必須・PJM elapse: SS / MM:SS / HH:MM:SS のみ (改行・異常文字を排除)
    local name="$1" val="${2-}"
    [ -n "$val" ] || { echo "ERROR: $name が未設定 (tools/fugaku-config.env)" >&2; exit 2; }
    case "$val" in
        *[!0-9:]* )       echo "ERROR: $name に使用不可文字: '$val' (数字と : のみ)" >&2; exit 2 ;;
    esac
    [[ "$val" =~ ^[0-9]+(:[0-5][0-9]){0,2}$ ]] || {
        echo "ERROR: $name は SS / MM:SS / HH:MM:SS 形式で指定: '$val'" >&2; exit 2; }
}
_cfg_opt_path() {  # 任意・パス/コマンド系 (空可): 英数 . _ / @ % - のみ (spath の %j 等を許容)
    local name="$1" val="${2-}"
    [ -n "$val" ] || return 0
    case "$val" in *[!A-Za-z0-9._/@%-]*)
        echo "ERROR: $name に使用不可文字: '$val'" >&2; exit 2 ;; esac
}
_cfg_opt_int() {   # 任意・整数 (空可)
    local name="$1" val="${2-}"
    [ -n "$val" ] || return 0
    case "$val" in *[!0-9]*)
        echo "ERROR: $name は整数で指定: '$val'" >&2; exit 2 ;; esac
}

# ---- 必須値 ----
_cfg_safe   FUGAKU_HOST        "${FUGAKU_HOST-}"
_cfg_safe   FUGAKU_REMOTE_DIR  "${FUGAKU_REMOTE_DIR-}"
_cfg_safe   FUGAKU_RSCGRP      "${FUGAKU_RSCGRP-}"
_cfg_safe   FUGAKU_GROUP       "${FUGAKU_GROUP-}"
_cfg_int    FUGAKU_NODE_COUNT  "${FUGAKU_NODE_COUNT-}"
_cfg_int    FUGAKU_MPI_RANKS   "${FUGAKU_MPI_RANKS-}"
_cfg_int    FUGAKU_OMP_THREADS "${FUGAKU_OMP_THREADS-}"
_cfg_elapse FUGAKU_ELAPSE      "${FUGAKU_ELAPSE-}"

# ---- 任意値 (空なら未使用) ----
_cfg_opt_path FUGAKU_CXX        "${FUGAKU_CXX:-}"        # remote build コマンド (sync が使用)
_cfg_opt_path FUGAKU_LLIO_VOL   "${FUGAKU_LLIO_VOL:-}"
_cfg_opt_path FUGAKU_SPATH      "${FUGAKU_SPATH:-}"
_cfg_opt_int  FUGAKU_FREQ       "${FUGAKU_FREQ:-}"
_cfg_opt_int  FUGAKU_THROTTLING "${FUGAKU_THROTTLING:-}"
# FUGAKU_MODULES は空白区切りの module 名を許容するが、module 名と空白以外は禁止 (改行/quote/注入文字)
if [ -n "${FUGAKU_MODULES:-}" ]; then
    case "$FUGAKU_MODULES" in *[!A-Za-z0-9._/+:\ -]*)
        echo "ERROR: FUGAKU_MODULES に使用不可文字: '$FUGAKU_MODULES' (module 名と空白のみ)" >&2; exit 2 ;; esac
fi

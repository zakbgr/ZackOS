#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# ZackOS logging and common helpers. Source this file; it has no side effects when sourced.
# Log lines go to stderr (stdout is reserved for data) and, after log_init, to a log file.

# shellcheck disable=SC2034  # exit-code constants are consumed by files that source this one

[[ -n "${_ZACKOS_LOG_LOADED:-}" ]] && return 0
_ZACKOS_LOG_LOADED=1

_ZACKOS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/palette.sh
source "${_ZACKOS_LIB_DIR}/palette.sh"

# Exit codes (see ARCHITECTURE.md section 8).
readonly ZACKOS_EXIT_OK=0
readonly ZACKOS_EXIT_FAILURE=1
readonly ZACKOS_EXIT_PREFLIGHT=2
readonly ZACKOS_EXIT_DECLINED=3
readonly ZACKOS_EXIT_BACKUP=4

ZACKOS_LOG_FILE="${ZACKOS_LOG_FILE:-}"

# Directory for logs, backups and install records. Override with ZACKOS_STATE_DIR (tests do).
zackos_state_dir() {
    printf '%s' "${ZACKOS_STATE_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/zackos}"
}

is_dry_run() {
    [[ "${ZACKOS_DRY_RUN:-0}" == "1" ]]
}

# log_init <command-name>: start a log file. Skipped in dry-run so that nothing is written.
log_init() {
    local name="${1:?log_init needs a name}"
    if is_dry_run; then
        ZACKOS_LOG_FILE=""
        return 0
    fi
    local dir
    dir="$(zackos_state_dir)/logs"
    mkdir -p -- "${dir}"
    ZACKOS_LOG_FILE="${dir}/$(date +%Y%m%dT%H%M%S)-${name}-$$.log"
    : >>"${ZACKOS_LOG_FILE}"
}

_zackos_color_on() {
    [[ -t 2 && -z "${NO_COLOR:-}" ]]
}

# _zackos_emit <LEVEL> <rgb "r;g;b"> <message...>
_zackos_emit() {
    local level="$1" rgb="$2"
    shift 2
    local msg="$*"
    if _zackos_color_on; then
        printf '\033[38;2;%sm[%s]\033[0m %s\n' "${rgb}" "${level}" "${msg}" >&2
    else
        printf '[%s] %s\n' "${level}" "${msg}" >&2
    fi
    if [[ -n "${ZACKOS_LOG_FILE}" ]]; then
        printf '%s [%s] %s\n' "$(date -Iseconds)" "${level}" "${msg}" >>"${ZACKOS_LOG_FILE}"
    fi
}

log_info() { _zackos_emit "INFO" "${ZACKOS_RGB_ACCENT}" "$@"; }
log_step() { _zackos_emit "STEP" "${ZACKOS_RGB_GREEN}" "$@"; }
log_warn() { _zackos_emit "WARN" "${ZACKOS_RGB_WARNING}" "$@"; }
log_error() { _zackos_emit "ERROR" "${ZACKOS_RGB_ERROR}" "$@"; }

# log_dry <message...>: announce an action that is skipped because of --dry-run.
log_dry() { _zackos_emit "DRY " "${ZACKOS_RGB_MUTED}" "would: $*"; }

# die <exit-code> <message...>
die() {
    local code="${1:?die needs an exit code}"
    shift
    log_error "$@"
    if [[ -n "${ZACKOS_LOG_FILE}" ]]; then
        printf 'See log: %s\n' "${ZACKOS_LOG_FILE}" >&2
    fi
    exit "${code}"
}

# zackos_run <command...>: log a command, then run it unless in dry-run mode.
zackos_run() {
    if is_dry_run; then
        log_dry "$*"
        return 0
    fi
    log_step "$*"
    "$@"
}

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Privileged steps (ADR 0006). This is the ONLY place that runs sudo.
#
#   priv_step <description> <undo description> <command> [args...]
#
# - Dry-run is the default: the step is printed and nothing runs.
# - With ZACKOS_APPLY=1 the exact command and its undo are shown and the user must type "yes"
#   for THIS step. There is no global yes flag (ZACKOS_ASSUME_YES is deliberately ignored).
# - Executed, declined and failed steps are appended to the journal.

[[ -n "${_ZACKOS_PRIV_LOADED:-}" ]] && return 0
_ZACKOS_PRIV_LOADED=1

_ZACKOS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "${_ZACKOS_LIB_DIR}/log.sh"

priv_journal_file() { printf '%s/priv-journal.tsv' "$(zackos_state_dir)"; }

# _priv_clean <text>: no tabs or newlines inside a journal field.
_priv_clean() { printf '%s' "${1//[$'\t\n']/ }"; }

_priv_journal() { # description command undo result
    local file
    file="$(priv_journal_file)"
    mkdir -p -- "$(dirname -- "${file}")"
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$(_priv_clean "$1")" "$(_priv_clean "$2")" \
        "$(_priv_clean "$3")" "$4" >>"${file}"
}

# _priv_confirm: read one line from ZACKOS_PRIV_INPUT (default /dev/tty); only "yes" confirms.
_priv_confirm() {
    local answer="" src="${ZACKOS_PRIV_INPUT:-/dev/tty}"
    printf 'Type "yes" to run this privileged step, anything else to skip: ' >&2
    if [[ "${src}" == "/dev/tty" ]]; then
        read -r answer <"${src}" || answer=""
    else
        # A file/pipe supplies several answers across calls: keep a persistent descriptor.
        if [[ -z "${_ZACKOS_PRIV_FD:-}" ]]; then
            exec {_ZACKOS_PRIV_FD}<"${src}"
        fi
        read -r answer <&"${_ZACKOS_PRIV_FD}" || answer=""
    fi
    printf '\n' >&2
    [[ "${answer}" == "yes" ]]
}

priv_step() {
    local description="${1:?description required}" undo="${2:?undo description required}"
    shift 2
    (($# > 0)) || {
        log_error "priv_step needs a command"
        return 2
    }
    local shown
    shown="$(printf '%q ' "$@")"
    shown="${shown% }"

    log_info "privileged step: ${description}"
    log_info "  command: sudo ${shown}"
    log_info "  undo:    ${undo}"

    if is_dry_run; then
        log_dry "run with sudo: ${shown}"
        return 0
    fi

    if [[ "${ZACKOS_TEST_EUID:-${EUID}}" -eq 0 ]]; then
        log_error "refusing to run privileged steps as root"
        return "${ZACKOS_EXIT_PREFLIGHT}"
    fi

    if ! _priv_confirm; then
        log_warn "declined: ${description}"
        _priv_journal "${description}" "sudo ${shown}" "${undo}" "declined"
        return "${ZACKOS_EXIT_DECLINED}"
    fi

    local rc=0
    sudo "$@" || rc=$?
    if ((rc == 0)); then
        log_step "done: ${description}"
        _priv_journal "${description}" "sudo ${shown}" "${undo}" "ok"
    else
        log_error "failed (exit ${rc}): ${description}"
        _priv_journal "${description}" "sudo ${shown}" "${undo}" "failed:${rc}"
    fi
    return "${rc}"
}

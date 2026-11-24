#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Preflight checks. Each function returns 0 when the check passes, or
# ZACKOS_EXIT_PREFLIGHT (2) after logging why it failed. Read-only.

[[ -n "${_ZACKOS_PREFLIGHT_LOADED:-}" ]] && return 0
_ZACKOS_PREFLIGHT_LOADED=1

_ZACKOS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "${_ZACKOS_LIB_DIR}/log.sh"
# shellcheck source=lib/detect.sh
source "${_ZACKOS_LIB_DIR}/detect.sh"

preflight_not_root() {
    if [[ "${ZACKOS_TEST_EUID:-${EUID}}" -eq 0 ]]; then
        log_error "Do not run ZackOS as root. It works at user level and asks before using sudo."
        return "${ZACKOS_EXIT_PREFLIGHT}"
    fi
}

preflight_arch() {
    local want="${1:-x86_64}" have
    have="$(detect_arch)"
    if [[ "${have}" != "${want}" ]]; then
        log_error "Unsupported architecture '${have}' (need '${want}')."
        return "${ZACKOS_EXIT_PREFLIGHT}"
    fi
}

# preflight_fedora [version]: require Fedora, and the given release if one is passed.
preflight_fedora() {
    local want="${1:-}" id ver
    id="$(detect_distro_id)"
    if [[ "${id}" != "fedora" ]]; then
        log_error "ZackOS targets Fedora; detected distro '${id}'."
        return "${ZACKOS_EXIT_PREFLIGHT}"
    fi
    ver="$(detect_fedora_version)"
    if [[ -n "${want}" && "${ver}" != "${want}" ]]; then
        log_error "ZackOS targets Fedora ${want}; detected Fedora ${ver}."
        return "${ZACKOS_EXIT_PREFLIGHT}"
    fi
}

# preflight_commands <cmd>...: every command must be on PATH.
preflight_commands() {
    local cmd missing=()
    for cmd in "$@"; do
        command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
    done
    if ((${#missing[@]} > 0)); then
        log_error "Missing required commands: ${missing[*]}"
        return "${ZACKOS_EXIT_PREFLIGHT}"
    fi
}

preflight_home_writable() {
    if [[ -z "${HOME:-}" || ! -d "${HOME}" || ! -w "${HOME}" ]]; then
        log_error "HOME is not set or not writable."
        return "${ZACKOS_EXIT_PREFLIGHT}"
    fi
}

# preflight_all_fedora [version]: the standard set. Runs every check, reports all failures.
preflight_all_fedora() {
    local rc=0
    preflight_not_root || rc="${ZACKOS_EXIT_PREFLIGHT}"
    preflight_arch x86_64 || rc="${ZACKOS_EXIT_PREFLIGHT}"
    preflight_fedora "${1:-}" || rc="${ZACKOS_EXIT_PREFLIGHT}"
    preflight_home_writable || rc="${ZACKOS_EXIT_PREFLIGHT}"
    preflight_commands cp mv sha256sum diff date readlink || rc="${ZACKOS_EXIT_PREFLIGHT}"
    return "${rc}"
}

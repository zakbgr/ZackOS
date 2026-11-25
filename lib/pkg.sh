#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Package manifest: parsing, validation, selection and read-only classification.
# Nothing here installs anything. See docs/PACKAGE-POLICY.md.

[[ -n "${_ZACKOS_PKG_LOADED:-}" ]] && return 0
_ZACKOS_PKG_LOADED=1

_ZACKOS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "${_ZACKOS_LIB_DIR}/log.sh"
# shellcheck source=lib/dnf.sh
source "${_ZACKOS_LIB_DIR}/dnf.sh"

# While COPR operations are locked (ADR 0005), no COPR row may be "approved".
ZACKOS_COPR_ROWS_MUST_BE_CANDIDATE=1

readonly PKG_PROTECTED=(kitty zsh neovim fastfetch waybar rofi dolphin)
readonly PKG_GROUPS=(core-terminal editor bar-launcher optional-dolphin hyprland-session)
readonly PKG_DEFAULT_GROUPS=(core-terminal)

pkg_manifest_file() {
    printf '%s' "${ZACKOS_PACKAGES_FILE:-${_ZACKOS_LIB_DIR}/../packages/fedora44.tsv}"
}

# pkg_rows: manifest rows without comments and blank lines.
pkg_rows() {
    local file
    file="$(pkg_manifest_file)"
    [[ -r "${file}" ]] || {
        log_error "package manifest not readable: ${file}"
        return 1
    }
    grep -v -E '^[[:space:]]*(#|$)' "${file}" || true
}

_pkg_in_list() { # item list...
    local item="$1" x
    shift
    for x in "$@"; do [[ "${x}" == "${item}" ]] && return 0; done
    return 1
}

pkg_is_protected() { _pkg_in_list "${1:?}" "${PKG_PROTECTED[@]}"; }

# pkg_validate: check every manifest rule; log every problem; return 1 if any.
pkg_validate() {
    local bad=0 n=0 row seen=" "
    local name source group optional status purpose extra
    while IFS= read -r row; do
        n=$((n + 1))
        IFS=$'\t' read -r name source group optional status purpose extra <<<"${row}"
        if [[ -n "${extra:-}" ]] || [[ -z "${purpose:-}" ]]; then
            log_error "row ${n}: expected 6 tab-separated columns: ${row}"
            bad=1
            continue
        fi
        if ! dnf_valid_name "${name}"; then
            log_error "row ${n}: invalid package name '${name}' (no globs, commas or spaces)"
            bad=1
        fi
        if [[ "${name}" == *-git ]]; then
            log_error "row ${n}: '${name}' is a -git package, which is never allowed"
            bad=1
        fi
        if [[ "${seen}" == *" ${name} "* ]]; then
            log_error "row ${n}: duplicate package '${name}'"
            bad=1
        fi
        seen+="${name} "
        if [[ "${source}" != "fedora" && ! "${source}" =~ ^copr:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
            log_error "row ${n}: invalid source '${source}' for ${name}"
            bad=1
        fi
        _pkg_in_list "${group}" "${PKG_GROUPS[@]}" || {
            log_error "row ${n}: unknown group '${group}' for ${name}"
            bad=1
        }
        [[ "${optional}" == "yes" || "${optional}" == "no" ]] || {
            log_error "row ${n}: optional must be yes or no for ${name}"
            bad=1
        }
        [[ "${status}" == "approved" || "${status}" == "candidate" ]] || {
            log_error "row ${n}: status must be approved or candidate for ${name}"
            bad=1
        }
        if pkg_is_protected "${name}" && [[ "${source}" != "fedora" ]]; then
            log_error "row ${n}: protected package '${name}' must come from fedora, not '${source}'"
            bad=1
        fi
        if [[ "${source}" == copr:* ]]; then
            [[ "${group}" == "hyprland-session" ]] || {
                log_error "row ${n}: COPR source is only allowed in group hyprland-session (${name})"
                bad=1
            }
            if [[ "${ZACKOS_COPR_ROWS_MUST_BE_CANDIDATE}" == "1" && "${status}" != "candidate" ]]; then
                log_error "row ${n}: COPR package '${name}' cannot be approved while COPR operations are locked"
                bad=1
            fi
        fi
        if [[ "${optional}" == "yes" && "${group}" == "core-terminal" ]]; then
            log_error "row ${n}: optional package '${name}' must not be in the default group core-terminal"
            bad=1
        fi
    done < <(pkg_rows)
    ((n > 0)) || {
        log_error "manifest has no rows"
        bad=1
    }
    return "${bad}"
}

# pkg_select [group...]: names selectable for installation, one per line. Only approved
# rows from the fedora source qualify. With no groups, the default groups are used.
pkg_select() {
    local groups=("$@") name source group optional status purpose
    ((${#groups[@]} > 0)) || groups=("${PKG_DEFAULT_GROUPS[@]}")
    while IFS=$'\t' read -r name source group optional status purpose; do
        _pkg_in_list "${group}" "${groups[@]}" || continue
        [[ "${status}" == "approved" && "${source}" == "fedora" ]] || continue
        printf '%s\n' "${name}"
    done < <(pkg_rows)
}

# pkg_source <name>: the manifest source of a package, or nothing.
pkg_source() {
    local name source rest
    while IFS=$'\t' read -r name source rest; do
        [[ "${name}" == "$1" ]] && {
            printf '%s' "${source}"
            return 0
        }
    done < <(pkg_rows)
    return 1
}

# pkg_state <name>: none | fedora | copr | other | unknown   (read-only)
pkg_state() {
    dnf_origin_class "$(dnf_installed_origin "$1")"
}

# pkg_action <state>: what an install run would do for a package whose manifest source is fedora.
pkg_action() {
    case "$1" in
    none) printf 'install' ;;
    fedora) printf 'ok' ;;
    unknown) printf 'ok-origin-unknown' ;;
    copr | other) printf 'conflict' ;;
    esac
}

# pkg_plan [group...]: table "name<TAB>state<TAB>action" for the selected packages.
pkg_plan() {
    local name state
    while IFS= read -r name; do
        state="$(pkg_state "${name}")"
        printf '%s\t%s\t%s\n' "${name}" "${state}" "$(pkg_action "${state}")"
    done < <(pkg_select "$@")
}

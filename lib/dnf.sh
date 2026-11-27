#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The only place that talks to dnf5 and rpm. Everything here is READ-ONLY: it queries, it never
# installs or removes. Mutating commands are built by callers and executed only through
# lib/priv.sh. Tests put fake binaries first on PATH (tests/fakebin).

[[ -n "${_ZACKOS_DNF_LOADED:-}" ]] && return 0
_ZACKOS_DNF_LOADED=1

_ZACKOS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "${_ZACKOS_LIB_DIR}/log.sh"

dnf_cmd() { printf '%s' "${ZACKOS_DNF:-dnf5}"; }

dnf_available() {
    command -v "$(dnf_cmd)" >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1
}

# Query format with a REAL tab: dnf5 on Fedora 44 does not expand "\t" in --queryformat (it prints
# it literally), which broke tab-separated parsing. "\n" is expanded by dnf5 itself.
_DNF_QF=$'%{name}\t%{from_repo}\\n'

# dnf_valid_name <name>: conservative RPM name check (no globs, commas, spaces, options).
dnf_valid_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]
}

dnf_is_installed() {
    dnf_valid_name "${1:-}" || return 2
    rpm -q -- "$1" >/dev/null 2>&1
}

# dnf_installed_origin <name>: "none" if not installed, otherwise the repository the package
# was installed from, or "unknown" if it cannot be determined.
# NOTE: the "from_repo" query tag is checked against real DNF5 by the Fedora 44 CI job.
dnf_installed_origin() {
    local name="${1:?package name required}" out
    dnf_valid_name "${name}" || return 2
    if ! dnf_is_installed "${name}"; then
        printf 'none'
        return 0
    fi
    out="$("$(dnf_cmd)" repoquery --installed --queryformat "${_DNF_QF}" "${name}" 2>/dev/null |
        awk -F'\t' -v n="${name}" '$1 == n && $2 != "" { print $2; exit }')" || true
    printf '%s' "${out:-unknown}"
}

# dnf_origin_class <origin>: fedora | copr | other | unknown | none
dnf_origin_class() {
    case "${1:-}" in
    none) printf 'none' ;;
    "" | unknown | "<unknown>" | "(none)") printf 'unknown' ;;
    fedora | updates | updates-testing | fedora-updates* | fedora-cisco-openh264) printf 'fedora' ;;
    copr:* | _copr:*) printf 'copr' ;;
    *) printf 'other' ;;
    esac
}

# dnf_all_installed_origins: "name<TAB>origin" for every installed package (read-only).
dnf_all_installed_origins() {
    "$(dnf_cmd)" repoquery --installed --queryformat "${_DNF_QF}" 2>/dev/null |
        awk -F'\t' 'NF >= 2 { print $1 "\t" $2 }'
}

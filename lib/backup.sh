#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Backup and restore primitives (see ARCHITECTURE.md section 6).
#
#   backup_begin               start a new backup session -> sets BACKUP_DIR
#   backup_path <abs-path>     preserve a path (or record that it is absent)
#   backup_restore <dir>       restore a session; nothing is ever deleted: whatever is
#                              in the way is moved into the restore session's displaced/ folder
#
# Manifest (BACKUP_DIR/manifest.tsv), one line per path:
#   <type> TAB <original path> TAB <path inside files/> TAB <sha256 or ->
# type is one of: file, dir, symlink, absent.
#
# These functions only touch the exact paths they are given and the backup folder.
# They never use rm. All of them honour ZACKOS_DRY_RUN=1.

[[ -n "${_ZACKOS_BACKUP_LOADED:-}" ]] && return 0
_ZACKOS_BACKUP_LOADED=1

_ZACKOS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "${_ZACKOS_LIB_DIR}/log.sh"

BACKUP_DIR="${BACKUP_DIR:-}"

backup_begin() {
    local base stamp candidate n=0
    base="$(zackos_state_dir)/backups"
    stamp="$(date +%Y%m%dT%H%M%S)-$$"
    candidate="${base}/${stamp}"
    # Never reuse a session directory: that would overwrite an existing manifest.
    while [[ -e "${candidate}" ]]; do
        n=$((n + 1))
        candidate="${base}/${stamp}-${n}"
    done
    BACKUP_DIR="${candidate}"
    if is_dry_run; then
        log_dry "create backup session ${BACKUP_DIR}"
        return 0
    fi
    mkdir -p -- "${base}" || return "${ZACKOS_EXIT_BACKUP}"
    mkdir -- "${BACKUP_DIR}" "${BACKUP_DIR}/files" || return "${ZACKOS_EXIT_BACKUP}"
    : >"${BACKUP_DIR}/manifest.tsv" || return "${ZACKOS_EXIT_BACKUP}"
    log_info "backup session: ${BACKUP_DIR}"
}

# _backup_check_path <path>: absolute, no tab/newline, not empty, not the filesystem root.
_backup_check_path() {
    local p="$1"
    if [[ "${p}" != /* || "${p}" == "/" ]]; then
        log_error "backup path must be absolute and not '/': '${p}'"
        return 1
    fi
    if [[ "${p}" == *$'\t'* || "${p}" == *$'\n'* ]]; then
        log_error "backup path contains a tab or newline: refusing"
        return 1
    fi
}

# _backup_in_manifest <manifest> <path>
_backup_in_manifest() {
    local manifest="$1" path="$2" type orig rel sum
    while IFS=$'\t' read -r type orig rel sum; do
        [[ "${orig}" == "${path}" ]] && return 0
    done <"${manifest}"
    return 1
}

# _backup_tree_digest <dir>: digest of names, types, link targets and file contents, using only
# coreutils/findutils (diffutils may be absent on a minimal Fedora; found by the Fedora 44 CI job).
_backup_tree_digest() {
    (
        cd -- "$1" || exit 1
        find . -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' p; do
            if [[ -L "${p}" ]]; then
                printf 'L %s -> %s\n' "${p}" "$(readlink -- "${p}")"
            elif [[ -f "${p}" ]]; then
                printf 'F %s %s\n' "${p}" "$(sha256sum <"${p}" | cut -d' ' -f1)"
            elif [[ -d "${p}" ]]; then
                printf 'D %s\n' "${p}"
            else
                printf 'O %s\n' "${p}"
            fi
        done | sha256sum
    )
}

backup_path() {
    local path="${1:?path required}" type rel sum="-" dest
    path="${path%/}"
    _backup_check_path "${path}" || return "${ZACKOS_EXIT_BACKUP}"
    if [[ -z "${BACKUP_DIR}" ]]; then
        log_error "backup_begin must be called first"
        return "${ZACKOS_EXIT_BACKUP}"
    fi

    if [[ -L "${path}" ]]; then
        type="symlink"
    elif [[ -f "${path}" ]]; then
        type="file"
    elif [[ -d "${path}" ]]; then
        type="dir"
    elif [[ ! -e "${path}" ]]; then
        type="absent"
    else
        log_error "unsupported file type, refusing to back up: ${path}"
        return "${ZACKOS_EXIT_BACKUP}"
    fi

    if is_dry_run; then
        log_dry "back up ${path} (${type})"
        return 0
    fi

    if _backup_in_manifest "${BACKUP_DIR}/manifest.tsv" "${path}"; then
        log_info "already backed up in this session: ${path}"
        return 0
    fi

    rel="-"
    if [[ "${type}" != "absent" ]]; then
        rel="${path#/}"
        dest="${BACKUP_DIR}/files/${rel}"
        mkdir -p -- "$(dirname -- "${dest}")" || return "${ZACKOS_EXIT_BACKUP}"
        cp -a -- "${path}" "${dest}" || {
            log_error "copy failed: ${path}"
            return "${ZACKOS_EXIT_BACKUP}"
        }
        case "${type}" in
        file)
            sum="$(sha256sum -- "${path}" | cut -d' ' -f1)"
            [[ "${sum}" == "$(sha256sum -- "${dest}" | cut -d' ' -f1)" ]] || {
                log_error "checksum mismatch after copying ${path}"
                return "${ZACKOS_EXIT_BACKUP}"
            }
            ;;
        dir)
            [[ "$(_backup_tree_digest "${path}")" == "$(_backup_tree_digest "${dest}")" ]] || {
                log_error "directory copy differs from original: ${path}"
                return "${ZACKOS_EXIT_BACKUP}"
            }
            ;;
        symlink)
            [[ "$(readlink -- "${path}")" == "$(readlink -- "${dest}")" ]] || {
                log_error "symlink copy differs from original: ${path}"
                return "${ZACKOS_EXIT_BACKUP}"
            }
            ;;
        esac
    fi
    printf '%s\t%s\t%s\t%s\n' "${type}" "${path}" "${rel}" "${sum}" >>"${BACKUP_DIR}/manifest.tsv"
    log_info "backed up (${type}): ${path}"
}

# backup_verify <session-dir>: check that every preserved file still matches its checksum.
backup_verify() {
    local dir="${1:?session dir required}" type orig rel sum
    [[ -f "${dir}/manifest.tsv" ]] || {
        log_error "no manifest in ${dir}"
        return "${ZACKOS_EXIT_BACKUP}"
    }
    while IFS=$'\t' read -r type orig rel sum; do
        case "${type}" in
        file)
            [[ -f "${dir}/files/${rel}" && "$(sha256sum -- "${dir}/files/${rel}" | cut -d' ' -f1)" == "${sum}" ]] || {
                log_error "backup copy is missing or corrupted: ${rel}"
                return "${ZACKOS_EXIT_BACKUP}"
            }
            ;;
        dir) [[ -d "${dir}/files/${rel}" ]] || {
            log_error "backup copy is missing: ${rel}"
            return "${ZACKOS_EXIT_BACKUP}"
        } ;;
        symlink) [[ -L "${dir}/files/${rel}" ]] || {
            log_error "backup copy is missing: ${rel}"
            return "${ZACKOS_EXIT_BACKUP}"
        } ;;
        absent) ;;
        *)
            log_error "unknown manifest entry type '${type}'"
            return "${ZACKOS_EXIT_BACKUP}"
            ;;
        esac
    done <"${dir}/manifest.tsv"
}

# _backup_displace <path>: move whatever is at <path> into the restore session's displaced/.
_backup_displace() {
    local path="$1" target
    if [[ -e "${path}" || -L "${path}" ]]; then
        target="${BACKUP_DIR}/displaced/${path#/}"
        mkdir -p -- "$(dirname -- "${target}")" || return 1
        mv -- "${path}" "${target}" || return 1
        log_info "moved aside: ${path}"
    fi
}

backup_restore() {
    local src="${1:?session dir required}" type orig rel sum entries=() line i
    backup_verify "${src}" || return "${ZACKOS_EXIT_BACKUP}"

    while IFS= read -r line; do
        entries+=("${line}")
    done <"${src}/manifest.tsv"

    backup_begin || return "${ZACKOS_EXIT_BACKUP}"
    if is_dry_run; then
        for ((i = ${#entries[@]} - 1; i >= 0; i--)); do
            IFS=$'\t' read -r type orig rel sum <<<"${entries[i]}"
            log_dry "restore ${orig} (${type})"
        done
        return 0
    fi

    # Reverse order: undo the most recent change first.
    for ((i = ${#entries[@]} - 1; i >= 0; i--)); do
        IFS=$'\t' read -r type orig rel sum <<<"${entries[i]}"
        _backup_check_path "${orig}" || return "${ZACKOS_EXIT_BACKUP}"
        _backup_displace "${orig}" || {
            log_error "could not move aside ${orig}"
            return "${ZACKOS_EXIT_BACKUP}"
        }
        if [[ "${type}" != "absent" ]]; then
            mkdir -p -- "$(dirname -- "${orig}")" || return "${ZACKOS_EXIT_BACKUP}"
            cp -a -- "${src}/files/${rel}" "${orig}" || {
                log_error "restore failed: ${orig}"
                return "${ZACKOS_EXIT_BACKUP}"
            }
        fi
        log_step "restored (${type}): ${orig}"
    done
    log_info "displaced items kept in: ${BACKUP_DIR}/displaced"
}

# backup_list: print available backup sessions, oldest first.
backup_list() {
    local root d
    root="$(zackos_state_dir)/backups"
    [[ -d "${root}" ]] || return 0
    for d in "${root}"/*/; do
        [[ -f "${d}manifest.tsv" ]] && printf '%s\n' "${d%/}"
    done
}

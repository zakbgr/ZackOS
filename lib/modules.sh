#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# User-level module engine: plan, install (symlinks into $HOME), status, rollback.
#
# A module is  modules/<name>/module.conf  plus  modules/<name>/files/<path relative to $HOME>.
#
# Safety rules (docs/INSTALLATION-DESIGN.md):
#   - nothing is overwritten: an existing file, directory or foreign symlink is a CONFLICT and
#     is skipped and left untouched; there is no replace option
#   - everything that is created is recorded in a backup session first, so rollback is exact
#   - rollback never deletes: it moves things aside (lib/backup.sh)
#   - dry-run is the default

[[ -n "${_ZACKOS_MODULES_LOADED:-}" ]] && return 0
_ZACKOS_MODULES_LOADED=1

_ZACKOS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "${_ZACKOS_LIB_DIR}/log.sh"
# shellcheck source=lib/backup.sh
source "${_ZACKOS_LIB_DIR}/backup.sh"

mod_dir() {
    local d="${ZACKOS_MODULES_DIR:-${_ZACKOS_LIB_DIR}/../modules}"
    (cd -P -- "${d}" 2>/dev/null && pwd)
}

mod_installed_file() { printf '%s/installed.tsv' "$(zackos_state_dir)"; }

mod_valid_name() { [[ "${1:-}" =~ ^[a-z][a-z0-9-]*$ ]]; }

# mod_list: names of all modules (directories with a module.conf).
mod_list() {
    local root d
    root="$(mod_dir)" || return 1
    for d in "${root}"/*/; do
        [[ -f "${d}module.conf" ]] && basename -- "${d%/}"
    done
}

# mod_conf_get <module> <key>: read a key=value line from module.conf (never sourced).
mod_conf_get() {
    local root
    root="$(mod_dir)" || return 1
    sed -n "s/^${2}=//p" "${root}/${1}/module.conf" | head -n 1
}

_mod_rel_ok() {
    local rel="$1"
    [[ -n "${rel}" && "${rel}" != /* && "${rel}" != *$'\t'* && "${rel}" != *$'\n'* ]] || return 1
    case "/${rel}/" in */../* | */./* | *//*) return 1 ;; esac
    return 0
}

# mod_validate <module>: structural checks; logs each problem.
mod_validate() {
    local m="${1:-}" root bad=0 rel
    mod_valid_name "${m}" || {
        log_error "invalid module name '${m}'"
        return 1
    }
    root="$(mod_dir)" || {
        log_error "modules directory not found"
        return 1
    }
    [[ -f "${root}/${m}/module.conf" ]] || {
        log_error "unknown module '${m}' (no module.conf)"
        return 1
    }
    [[ "$(mod_conf_get "${m}" name)" == "${m}" ]] || {
        log_error "module ${m}: name= in module.conf must equal the directory name"
        bad=1
    }
    [[ -d "${root}/${m}/files" ]] || {
        log_error "module ${m}: files/ directory missing"
        return 1
    }
    if [[ -n "$(find "${root}/${m}/files" -type l -print -quit)" ]]; then
        log_error "module ${m}: symlinks are not allowed inside files/"
        bad=1
    fi
    if [[ -n "$(find "${root}/${m}/files" -name $'*\n*' -print -quit)" ]]; then
        log_error "module ${m}: file names must not contain newlines"
        bad=1
    fi
    while IFS= read -r rel; do
        _mod_rel_ok "${rel}" || {
            log_error "module ${m}: unsafe path '${rel}'"
            bad=1
        }
    done < <(mod_files "${m}")
    return "${bad}"
}

# mod_files <module>: paths relative to $HOME, sorted.
mod_files() {
    local root
    root="$(mod_dir)" || return 1
    (cd -- "${root}/${1}/files" && find . -type f -print | sed 's|^\./||' | LC_ALL=C sort)
}

_mod_home_ok() {
    [[ -n "${HOME:-}" && "${HOME}" == /* && "${HOME}" != "/" && -d "${HOME}" ]]
}

# _mod_parent_problem <target>: print why an existing parent is unsafe; return 0 if unsafe.
_mod_parent_problem() {
    local cur
    cur="$(dirname -- "$1")"
    while [[ "${cur}" != "${HOME}" && "${cur}" != "/" ]]; do
        if [[ -L "${cur}" ]]; then
            printf 'parent is a symlink: %s' "${cur}"
            return 0
        fi
        if [[ -e "${cur}" && ! -d "${cur}" ]]; then
            printf 'parent is not a directory: %s' "${cur}"
            return 0
        fi
        cur="$(dirname -- "${cur}")"
    done
    return 1
}

# mod_classify <module> <rel>: prints  state<TAB>reason   (absent | ours | identical | conflict)
mod_classify() {
    local m="$1" rel="$2" root src target reason
    root="$(mod_dir)" || return 1
    src="${root}/${m}/files/${rel}"
    target="${HOME}/${rel}"
    if reason="$(_mod_parent_problem "${target}")"; then
        printf 'conflict\t%s\n' "${reason}"
    elif [[ ! -e "${target}" && ! -L "${target}" ]]; then
        printf 'absent\t\n'
    elif [[ -L "${target}" ]]; then
        if [[ "$(readlink -- "${target}")" == "${src}" ]]; then
            printf 'ours\t\n'
        else
            printf 'conflict\texisting symlink to %s\n' "$(readlink -- "${target}")"
        fi
    elif [[ -d "${target}" ]]; then
        printf 'conflict\tdirectory in the way\n'
    elif [[ -f "${target}" ]]; then
        if cmp -s -- "${src}" "${target}"; then
            printf 'identical\t\n'
        else
            printf 'conflict\texisting file differs\n'
        fi
    else
        printf 'conflict\tunsupported file type\n'
    fi
}

# mod_plan <module>...: lines  module<TAB>path<TAB>state<TAB>action<TAB>reason
# action is "link" only for absent targets; everything else is left alone.
mod_plan() {
    local m rel state reason action
    _mod_home_ok || {
        log_error "HOME is unsafe or missing: '${HOME:-}'"
        return 1
    }
    for m in "$@"; do
        mod_validate "${m}" || return 1
        while IFS= read -r rel; do
            IFS=$'\t' read -r state reason < <(mod_classify "${m}" "${rel}")
            action="skip"
            [[ "${state}" == "absent" ]] && action="link"
            printf '%s\t%s\t%s\t%s\t%s\n' "${m}" "${rel}" "${state}" "${action}" "${reason}"
        done < <(mod_files "${m}")
    done
}

# _mod_ensure_parent <target>: create missing parent directories, recording each one created.
_mod_ensure_parent() {
    local target="$1" dir missing=() cur
    dir="$(dirname -- "${target}")"
    cur="${dir}"
    while [[ ! -d "${cur}" && "${cur}" != "${HOME}" && "${cur}" != "/" ]]; do
        missing+=("${cur}")
        cur="$(dirname -- "${cur}")"
    done
    local i
    for ((i = ${#missing[@]} - 1; i >= 0; i--)); do
        mkdir -- "${missing[i]}" || return 1
        printf '%s\n' "${missing[i]}" >>"${BACKUP_DIR}/created-dirs.tsv"
    done
}

# mod_install <module>...: plan, then (only when applying) link the absent targets.
mod_install() {
    local m plan row state action rel reason src root linked=0 skipped=0 present=0 rc=0
    local -a todo=()
    plan="$(mod_plan "$@")" || return 1
    root="$(mod_dir)"

    while IFS=$'\t' read -r m rel state action reason; do
        [[ -n "${m}" ]] || continue
        case "${state}" in
        absent) log_info "link      ${m}: ~/${rel}" ;;
        ours) log_info "already   ${m}: ~/${rel}" ;;
        identical) log_info "identical ${m}: ~/${rel} (left as is)" ;;
        conflict) log_warn "conflict  ${m}: ~/${rel}: ${reason}. Skipped, nothing changed." ;;
        esac
        case "${state}" in
        absent) todo+=("${m}"$'\t'"${rel}") ;;
        ours) present=$((present + 1)) ;;
        *) skipped=$((skipped + 1)) ;;
        esac
    done <<<"${plan}"

    if is_dry_run; then
        log_dry "link ${#todo[@]} file(s), skip ${skipped}, already in place ${present}"
        return 0
    fi
    if ((${#todo[@]} == 0)); then
        log_info "nothing to do: already in place ${present}, skipped ${skipped}"
        return 0
    fi

    mkdir -p -- "$(zackos_state_dir)"
    backup_begin || return "${ZACKOS_EXIT_BACKUP}"
    : >>"${BACKUP_DIR}/created-dirs.tsv"
    for row in "${todo[@]}"; do
        IFS=$'\t' read -r m rel <<<"${row}"
        src="${root}/${m}/files/${rel}"
        # Re-check right before acting: the target must still be absent.
        IFS=$'\t' read -r state reason < <(mod_classify "${m}" "${rel}")
        if [[ "${state}" != "absent" ]]; then
            log_warn "target changed while installing, skipped: ~/${rel}"
            continue
        fi
        backup_path "${HOME}/${rel}" || return "${ZACKOS_EXIT_BACKUP}"
        _mod_ensure_parent "${HOME}/${rel}" || {
            log_error "cannot create parent directory for ~/${rel}"
            return 1
        }
        if ln -s -- "${src}" "${HOME}/${rel}" && [[ "$(readlink -- "${HOME}/${rel}")" == "${src}" ]]; then
            printf '%s\t%s\t%s\t%s\t%s\n' "${m}" "${HOME}/${rel}" "${src}" "${BACKUP_DIR}" "$(date -Iseconds)" \
                >>"$(mod_installed_file)"
            linked=$((linked + 1))
        else
            log_error "could not link ~/${rel}; run: zackos rollback"
            rc=1
            break
        fi
    done
    log_info "linked ${linked}, skipped ${skipped}, already in place ${present}. Rollback: zackos rollback ${BACKUP_DIR}"
    return "${rc}"
}

# mod_status: table  module<TAB>target<TAB>state(ok|missing|changed)
mod_status() {
    local file m target src session _when state
    file="$(mod_installed_file)"
    [[ -f "${file}" ]] || return 0
    while IFS=$'\t' read -r m target src session _when; do
        if [[ -L "${target}" && "$(readlink -- "${target}")" == "${src}" ]]; then
            state="ok"
        elif [[ -e "${target}" || -L "${target}" ]]; then
            state="changed"
        else
            state="missing"
        fi
        printf '%s\t%s\t%s\n' "${m}" "${target}" "${state}"
    done <"${file}"
}

# mod_latest_session: the backup session of the most recent install.
mod_latest_session() {
    local file
    file="$(mod_installed_file)"
    [[ -s "${file}" ]] || return 1
    tail -n 1 "${file}" | cut -f4
}

# mod_rollback [session|latest]
#
# Ownership rule: a target is removed ONLY if it is still a symlink that points at the exact
# module file we recorded in installed.tsv for this session. Anything else (a file the user put
# there afterwards, a changed link, a directory that now holds user files) is left untouched.
# Nothing is overwritten and no content is deleted: we only unlink our own symlinks and rmdir
# directories we created that are now empty. Safe to run repeatedly.
mod_rollback() {
    local want="${1:-latest}" session base file m target src sess _when d i
    local removed=0 kept=0 gone=0
    local -a rows=() dirs=()
    base="$(zackos_state_dir)/backups"
    file="$(mod_installed_file)"
    if [[ "${want}" == "latest" ]]; then
        session="$(mod_latest_session)" || {
            log_info "nothing to roll back: no recorded install"
            return 0
        }
    else
        session="${want}"
    fi
    case "${session}" in
    "${base}"/*) ;;
    *)
        log_error "session must be inside ${base}: ${session}"
        return 1
        ;;
    esac
    [[ "${session}" != *..* && -f "${session}/manifest.tsv" ]] || {
        log_error "not a valid backup session: ${session}"
        return 1
    }

    if [[ -f "${file}" ]]; then
        while IFS=$'\t' read -r m target src sess _when; do
            [[ "${sess}" == "${session}" ]] && rows+=("${m}"$'\t'"${target}"$'\t'"${src}")
        done <"${file}"
    fi
    if ((${#rows[@]} == 0)); then
        log_info "nothing to roll back for ${session} (already rolled back)"
        return 0
    fi

    for ((i = ${#rows[@]} - 1; i >= 0; i--)); do
        IFS=$'\t' read -r m target src <<<"${rows[i]}"
        if [[ -L "${target}" && "$(readlink -- "${target}")" == "${src}" ]]; then
            if is_dry_run; then
                log_dry "unlink ${target}"
            else
                unlink -- "${target}" && log_step "removed our link: ${target}"
            fi
            removed=$((removed + 1))
        elif [[ -e "${target}" || -L "${target}" ]]; then
            log_warn "${target} was changed after install, left untouched"
            kept=$((kept + 1))
        else
            gone=$((gone + 1))
        fi
    done

    if [[ -f "${session}/created-dirs.tsv" ]]; then
        while IFS= read -r d; do dirs+=("${d}"); done <"${session}/created-dirs.tsv"
        for ((i = ${#dirs[@]} - 1; i >= 0; i--)); do
            [[ -d "${dirs[i]}" && ! -L "${dirs[i]}" ]] || continue
            if is_dry_run; then
                [[ -z "$(find "${dirs[i]}" -mindepth 1 -print -quit 2>/dev/null)" ]] &&
                    log_dry "rmdir ${dirs[i]} (empty)"
            else
                rmdir -- "${dirs[i]}" 2>/dev/null && log_info "removed empty directory: ${dirs[i]}"
            fi
        done
    fi

    if is_dry_run; then
        log_dry "would remove ${removed} link(s), leave ${kept} changed, ${gone} already gone"
        return 0
    fi
    cp -p -- "${file}" "${file}.prev"
    awk -F'\t' -v s="${session}" '$4 != s' "${file}" >"${file}.new"
    mv -- "${file}.new" "${file}"
    log_info "rolled back: removed ${removed}, left ${kept} changed, ${gone} already gone"
}

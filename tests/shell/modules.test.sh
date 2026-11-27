#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/shell/harness.sh
source "${HERE}/harness.sh"
LIB="${HERE}/../../lib/modules.sh"
# shellcheck source=lib/modules.sh
source "${LIB}"

make_tmp
export NO_COLOR=1
export ZACKOS_STATE_DIR="${T_TMP}/state"
export ZACKOS_MODULES_DIR="${T_TMP}/modules"
export HOME="${T_TMP}/home"
mkdir -p "${HOME}"

# ---- build a fake module set
mk() { mkdir -p "$(dirname -- "$1")" && printf '%s\n' "$2" >"$1"; }
M="${ZACKOS_MODULES_DIR}"
mk "${M}/alpha/module.conf" "name=alpha"
mk "${M}/alpha/files/.config/alpha/main.conf" "alpha main"
mk "${M}/alpha/files/.config/alpha/theme.conf" "alpha theme"
mk "${M}/alpha/files/.config/alpha/sub/deep.conf" "alpha deep"
mk "${M}/beta/module.conf" "name=beta"
mk "${M}/beta/files/.local/share/beta/data.txt" "beta data"

# tree <dir>: stable listing of paths + link targets + content hashes (to compare states)
tree() {
    (cd -- "$1" && find . \( -type f -o -type l -o -type d \) -print | LC_ALL=C sort | while IFS= read -r p; do
        if [[ -L "${p}" ]]; then
            printf 'L %s -> %s\n' "${p}" "$(readlink -- "${p}")"
        elif [[ -f "${p}" ]]; then
            printf 'F %s %s\n' "${p}" "$(sha256sum <"${p}" | cut -c1-16)"
        else
            printf 'D %s\n' "${p}"
        fi
    done)
}

# ---- validation
assert_eq "alpha
beta" "$(mod_list)" "module list"
assert_rc 0 "valid module" mod_validate alpha
assert_rc 1 "unknown module" mod_validate nope
assert_rc 1 "bad module name" mod_validate '../alpha'
assert_rc 1 "bad module name 2" mod_validate 'Alpha'
mk "${M}/gamma/module.conf" "name=wrong"
mk "${M}/gamma/files/x" "x"
assert_rc 1 "name must match directory" mod_validate gamma
rm -r "${M}/gamma"
mk "${M}/delta/module.conf" "name=delta"
mk "${M}/delta/files/x" "x"
ln -s /etc/passwd "${M}/delta/files/evil"
assert_rc 1 "symlinks inside files/ are refused" mod_validate delta
rm -r "${M}/delta"

# ---- HOME safety
assert_rc 1 "HOME=/ refused" env HOME=/ ZACKOS_MODULES_DIR="${M}" bash -c "source '${LIB}'; mod_plan alpha"
assert_rc 1 "HOME unset refused" env -u HOME ZACKOS_MODULES_DIR="${M}" bash -c "source '${LIB}'; mod_plan alpha"
assert_rc 1 "relative HOME refused" env HOME=relative ZACKOS_MODULES_DIR="${M}" bash -c "source '${LIB}'; mod_plan alpha"

# ---- plan on an empty HOME
plan="$(mod_plan alpha beta)"
assert_eq "4" "$(grep -c $'\tabsent\tlink' <<<"${plan}")" "all four targets planned as link"

# ---- dry-run (default) changes nothing
before="$(tree "${HOME}")"
mod_install alpha beta >/dev/null 2>&1
assert_eq "${before}" "$(tree "${HOME}")" "dry-run install leaves HOME untouched"
assert_no_path "${ZACKOS_STATE_DIR}" "dry-run creates no state"

# ---- apply
export ZACKOS_APPLY=1
mod_install alpha beta >/dev/null 2>&1
assert_eq "0" "$?" "install rc"
assert_link "${HOME}/.config/alpha/main.conf" "${M}/alpha/files/.config/alpha/main.conf"
assert_link "${HOME}/.config/alpha/sub/deep.conf" "${M}/alpha/files/.config/alpha/sub/deep.conf"
assert_link "${HOME}/.local/share/beta/data.txt" "${M}/beta/files/.local/share/beta/data.txt"
assert_eq "4" "$(wc -l <"$(mod_installed_file)" | tr -d ' ')" "installed.tsv has 4 rows"
session="$(mod_latest_session)"
assert_eq "4" "$(grep -c '^absent	' "${session}/manifest.tsv")" "session records the 4 absent targets"
assert_contains "$(cat "${session}/created-dirs.tsv")" "${HOME}/.config/alpha/sub" "created directories recorded"

# ---- status
st="$(mod_status)"
assert_eq "4" "$(grep -c $'\tok$' <<<"${st}")" "status: all ok"

# ---- idempotent: second install changes nothing and creates no new session
sessions_before="$(find "${ZACKOS_STATE_DIR}/backups" -mindepth 1 -maxdepth 1 | wc -l)"
before="$(tree "${HOME}")"
mod_install alpha beta >/dev/null 2>&1
assert_eq "${before}" "$(tree "${HOME}")" "second install changes nothing"
assert_eq "${sessions_before}" "$(find "${ZACKOS_STATE_DIR}/backups" -mindepth 1 -maxdepth 1 | wc -l)" "no new backup session"
assert_eq "4" "$(wc -l <"$(mod_installed_file)" | tr -d ' ')" "installed.tsv unchanged"

# ---- rollback: dry-run first
before="$(tree "${HOME}")"; st_before="$(tree "${ZACKOS_STATE_DIR}")"
ZACKOS_DRY_RUN=1 mod_rollback latest >/dev/null 2>&1
assert_eq "${before}" "$(tree "${HOME}")" "dry-run rollback leaves HOME untouched"
assert_eq "${st_before}" "$(tree "${ZACKOS_STATE_DIR}")" "dry-run rollback leaves state untouched"
assert_link "${HOME}/.config/alpha/main.conf" "${M}/alpha/files/.config/alpha/main.conf"

# ---- real rollback restores the exact original state (empty HOME)
mod_rollback latest >/dev/null 2>&1
assert_eq "0" "$?" "rollback rc"
assert_eq "" "$(tree "${HOME}" | grep -v '^D \.$')" "HOME is empty again, created directories removed"
assert_eq "0" "$(wc -l <"$(mod_installed_file)" | tr -d ' ')" "installed.tsv rows removed"
assert_file "$(mod_installed_file).prev" "previous installed.tsv kept"
assert_file "${session}/manifest.tsv" "backup session record is kept"
assert_rc 0 "second rollback is a no-op (idempotent)" mod_rollback latest
assert_rc 0 "rollback of an already rolled back session is a no-op" mod_rollback "${session}"
assert_eq "" "$(tree "${HOME}" | grep -v '^D \.$')" "still clean after repeated rollback"

# ---- existing configs are never overwritten (conflict matrix)
mkdir -p "${HOME}/.config/alpha/sub" "${HOME}/.local/share"
printf 'MY OWN main\n' >"${HOME}/.config/alpha/main.conf"          # different file
printf 'alpha theme\n' >"${HOME}/.config/alpha/theme.conf"          # identical file
mkdir -p "${HOME}/.config/alpha/sub/deep.conf"                      # directory in the way
printf 'x\n' >"${HOME}/.local/share/beta"                           # parent is a file
user_before="$(tree "${HOME}")"
sess_n="$(find "${ZACKOS_STATE_DIR}/backups" -mindepth 1 -maxdepth 1 | wc -l)"
out="$(mod_install alpha beta 2>&1)"
assert_eq "${user_before}" "$(tree "${HOME}")" "conflicting install changed nothing"
assert_contains "${out}" "conflict  alpha: ~/.config/alpha/main.conf: existing file differs" "different file reported"
assert_contains "${out}" "identical alpha: ~/.config/alpha/theme.conf" "identical file reported"
assert_contains "${out}" "directory in the way" "directory conflict reported"
assert_contains "${out}" "parent is not a directory" "file-as-parent reported"
assert_eq "MY OWN main" "$(cat "${HOME}/.config/alpha/main.conf")" "user file content intact"
assert_eq "${sess_n}" "$(find "${ZACKOS_STATE_DIR}/backups" -mindepth 1 -maxdepth 1 | wc -l)" "no session created when nothing was linked"

# ---- foreign symlink and symlinked parent (stow-style dotfiles) are conflicts too
rm -r "${HOME}/.config" "${HOME}/.local"
mkdir -p "${HOME}/dotfiles/alpha" "${HOME}/.config" "${HOME}/.local/share/beta"
ln -s "${HOME}/dotfiles/alpha" "${HOME}/.config/alpha"                  # whole dir symlinked
ln -s /elsewhere "${HOME}/.local/share/beta/data.txt"                   # foreign symlink
user_before="$(tree "${HOME}")"
out="$(mod_install alpha beta 2>&1)"
assert_eq "${user_before}" "$(tree "${HOME}")" "symlink conflicts changed nothing"
assert_contains "${out}" "parent is a symlink" "symlinked parent reported"
assert_contains "${out}" "existing symlink to /elsewhere" "foreign symlink reported"

# ---- partial: conflicts skipped, absent targets still linked, pre-existing files untouched
rm -r "${HOME}/.config" "${HOME}/.local" "${HOME}/dotfiles"
mkdir -p "${HOME}/.config/alpha"
printf 'MY OWN main\n' >"${HOME}/.config/alpha/main.conf"
mod_install alpha >/dev/null 2>&1
assert_eq "MY OWN main" "$(cat "${HOME}/.config/alpha/main.conf")" "existing file kept"
assert_link "${HOME}/.config/alpha/theme.conf" "${M}/alpha/files/.config/alpha/theme.conf"
assert_link "${HOME}/.config/alpha/sub/deep.conf" "${M}/alpha/files/.config/alpha/sub/deep.conf"
mod_rollback latest >/dev/null 2>&1
assert_eq "MY OWN main" "$(cat "${HOME}/.config/alpha/main.conf")" "existing file still intact after rollback"
assert_no_path "${HOME}/.config/alpha/theme.conf" "link removed by rollback"
assert_no_path "${HOME}/.config/alpha/sub" "created directory removed by rollback"
assert_file "${HOME}/.config/alpha/main.conf" "pre-existing directory and file remain"

# ---- ownership: rollback never touches what the user changed after deployment
rm -rf "${HOME}/.config"
mod_install alpha >/dev/null 2>&1
rm "${HOME}/.config/alpha/main.conf"
printf 'USER REPLACED\n' >"${HOME}/.config/alpha/main.conf"                 # replaced by user
printf 'USER ADDED\n' >"${HOME}/.config/alpha/sub/mine.txt"                  # user file in our dir
rm "${HOME}/.config/alpha/theme.conf"
ln -s /somewhere/else "${HOME}/.config/alpha/theme.conf"                     # re-pointed link
out="$(mod_rollback latest 2>&1)"
assert_eq "USER REPLACED" "$(cat "${HOME}/.config/alpha/main.conf")" "replaced file preserved"
assert_eq "USER ADDED" "$(cat "${HOME}/.config/alpha/sub/mine.txt")" "user file inside created dir preserved"
assert_eq "/somewhere/else" "$(readlink "${HOME}/.config/alpha/theme.conf")" "re-pointed link preserved"
assert_contains "${out}" "was changed after install, left untouched" "changes reported"
assert_no_path "${HOME}/.config/alpha/sub/deep.conf" "our own link was removed"
assert_rc 0 "non-empty created directory kept" test -d "${HOME}/.config/alpha/sub"
rm -rf "${HOME}/.config"

# ---- interrupted install: rollback still restores a clean state
rm -rf "${HOME}/.config"
mkdir -p "${T_TMP}/failbin"
real_ln="$(command -v ln)"
cat >"${T_TMP}/failbin/ln" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == *deep.conf ]] && exit 1; done
exec "${real_ln}" "\$@"
EOF
chmod +x "${T_TMP}/failbin/ln"
rc=0
PATH="${T_TMP}/failbin:${PATH}" mod_install alpha >/dev/null 2>&1 || rc=$?
assert_eq "1" "${rc}" "install reports the failure"
mod_rollback latest >/dev/null 2>&1
assert_eq "" "$(tree "${HOME}" | grep -v '^D \.$')" "interrupted install rolled back to a clean HOME"

# ---- rollback session validation
assert_rc 1 "session outside state dir refused" mod_rollback "${T_TMP}/home"
assert_rc 1 "traversal refused" mod_rollback "${ZACKOS_STATE_DIR}/backups/../../etc"
assert_rc 1 "missing manifest refused" mod_rollback "${ZACKOS_STATE_DIR}/backups/does-not-exist"

# ---- status detects drift
mod_install beta >/dev/null 2>&1
rm "${HOME}/.local/share/beta/data.txt"
assert_contains "$(mod_status)" $'\tmissing' "status: missing link"
printf 'mine\n' >"${HOME}/.local/share/beta/data.txt"
assert_contains "$(mod_status)" $'\tchanged' "status: replaced by a user file"

t_finish

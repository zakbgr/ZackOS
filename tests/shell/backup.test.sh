#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/shell/harness.sh
source "${HERE}/harness.sh"
# shellcheck source=lib/backup.sh
source "${HERE}/../../lib/backup.sh"

make_tmp
export NO_COLOR=1
export ZACKOS_APPLY=1
export ZACKOS_STATE_DIR="${T_TMP}/state"
FAKE_HOME="${T_TMP}/home"
mkdir -p "${FAKE_HOME}/.config/kitty" "${FAKE_HOME}/.config/rofi/themes"

printf 'original kitty\n' >"${FAKE_HOME}/.config/kitty/kitty.conf"
printf 'theme a\n' >"${FAKE_HOME}/.config/rofi/themes/a.rasi"
ln -s /nonexistent/target "${FAKE_HOME}/.config/linkcfg"
# FAKE_HOME/.config/waybar does not exist (the "absent" case)

# --- argument validation
backup_begin >/dev/null 2>&1
assert_rc 4 "relative path refused" backup_path "relative/path"
assert_rc 4 "root refused" backup_path "/"
assert_rc 4 "tab in path refused" backup_path "$(printf '/tmp/a\tb')"

# --- backup each kind
backup_path "${FAKE_HOME}/.config/kitty/kitty.conf" 2>/dev/null
backup_path "${FAKE_HOME}/.config/rofi" 2>/dev/null
backup_path "${FAKE_HOME}/.config/linkcfg" 2>/dev/null
backup_path "${FAKE_HOME}/.config/waybar" 2>/dev/null
session="${BACKUP_DIR}"
manifest="$(cat "${session}/manifest.tsv")"
assert_contains "${manifest}" $'file\t'"${FAKE_HOME}/.config/kitty/kitty.conf" "manifest has file"
assert_contains "${manifest}" $'dir\t'"${FAKE_HOME}/.config/rofi" "manifest has dir"
assert_contains "${manifest}" $'symlink\t'"${FAKE_HOME}/.config/linkcfg" "manifest has symlink"
assert_contains "${manifest}" $'absent\t'"${FAKE_HOME}/.config/waybar" "manifest has absent"
assert_eq "4" "$(wc -l <"${session}/manifest.tsv" | tr -d ' ')" "four manifest lines"
assert_file "${session}/files${FAKE_HOME}/.config/kitty/kitty.conf" "file copied"
assert_link "${session}/files${FAKE_HOME}/.config/linkcfg" "/nonexistent/target"

# idempotent within a session
backup_path "${FAKE_HOME}/.config/kitty/kitty.conf" 2>/dev/null
assert_eq "4" "$(wc -l <"${session}/manifest.tsv" | tr -d ' ')" "no duplicate entry"

# --- verify
assert_rc 0 "verify ok" backup_verify "${session}"
printf 'tampered\n' >"${session}/files${FAKE_HOME}/.config/kitty/kitty.conf"
assert_rc 4 "verify detects corruption" backup_verify "${session}"
printf 'original kitty\n' >"${session}/files${FAKE_HOME}/.config/kitty/kitty.conf"
assert_rc 0 "verify ok again" backup_verify "${session}"

# --- simulate an installer changing things
printf 'ZACKOS kitty\n' >"${FAKE_HOME}/.config/kitty/kitty.conf"
printf 'extra\n' >"${FAKE_HOME}/.config/rofi/themes/b.rasi"
rm -- "${FAKE_HOME}/.config/linkcfg"
ln -s /somewhere/else "${FAKE_HOME}/.config/linkcfg"
mkdir -p "${FAKE_HOME}/.config/waybar"
printf 'created by installer\n' >"${FAKE_HOME}/.config/waybar/config"

# --- dry-run restore changes nothing
ZACKOS_DRY_RUN=1 backup_restore "${session}" 2>/dev/null
assert_eq "ZACKOS kitty" "$(cat "${FAKE_HOME}/.config/kitty/kitty.conf")" "dry-run restore changes nothing"
assert_file "${FAKE_HOME}/.config/waybar/config" "dry-run keeps installer file"

# --- real restore
backup_restore "${session}" 2>/dev/null
rc=$?
assert_eq "0" "${rc}" "restore rc"
assert_eq "original kitty" "$(cat "${FAKE_HOME}/.config/kitty/kitty.conf")" "file restored"
assert_file "${FAKE_HOME}/.config/rofi/themes/a.rasi" "dir content restored"
assert_no_path "${FAKE_HOME}/.config/rofi/themes/b.rasi" "added file gone after dir restore"
assert_link "${FAKE_HOME}/.config/linkcfg" "/nonexistent/target"
assert_no_path "${FAKE_HOME}/.config/waybar" "absent path removed again"

# nothing was destroyed: displaced items live in the restore session
restore_session="${BACKUP_DIR}"
assert_file "${restore_session}/displaced${FAKE_HOME}/.config/waybar/config" "installer file kept in displaced/"
assert_eq "ZACKOS kitty" "$(cat "${restore_session}/displaced${FAKE_HOME}/.config/kitty/kitty.conf")" "pre-restore file kept"
assert_file "${restore_session}/displaced${FAKE_HOME}/.config/rofi/themes/b.rasi" "pre-restore dir content kept"

# --- original session untouched by restore (and the restore got its own directory)
assert_rc 0 "original session still verifies" backup_verify "${session}"
assert_eq "4" "$(wc -l <"${session}/manifest.tsv" | tr -d ' ')" "original manifest not truncated"
assert_eq "no" "$([[ "${restore_session}" == "${session}" ]] && echo yes || echo no)" "restore uses a new session dir"

# two sessions started in the same second never share a directory
backup_begin >/dev/null 2>&1; first="${BACKUP_DIR}"
backup_begin >/dev/null 2>&1; second="${BACKUP_DIR}"
assert_eq "no" "$([[ "${first}" == "${second}" ]] && echo yes || echo no)" "unique session dirs"

# --- corrupted backup: restore refuses before changing anything
printf 'changed again\n' >"${FAKE_HOME}/.config/kitty/kitty.conf"
printf 'corrupt\n' >"${session}/files${FAKE_HOME}/.config/kitty/kitty.conf"
backup_restore "${session}" 2>/dev/null
assert_eq "4" "$?" "corrupt backup refused with rc 4"
assert_eq "changed again" "$(cat "${FAKE_HOME}/.config/kitty/kitty.conf")" "nothing changed when backup is corrupt"

# --- dry-run backup writes nothing
before="$(find "${ZACKOS_STATE_DIR}" | wc -l)"
(
    export ZACKOS_DRY_RUN=1
    backup_begin
    backup_path "${FAKE_HOME}/.config/kitty/kitty.conf"
) 2>/dev/null
after="$(find "${ZACKOS_STATE_DIR}" | wc -l)"
assert_eq "${before}" "${after}" "dry-run backup writes nothing"

# --- backup_list
assert_contains "$(backup_list)" "${ZACKOS_STATE_DIR}/backups/" "backup_list shows sessions"

# ---- regression: directory backups must not need diffutils (absent on a minimal Fedora)
mkdir -p "${T_TMP}/nodiff"
printf '#!/bin/sh\necho "diff: command not found" >&2\nexit 127\n' >"${T_TMP}/nodiff/diff"
cp "${T_TMP}/nodiff/diff" "${T_TMP}/nodiff/cmp"
chmod +x "${T_TMP}/nodiff/diff" "${T_TMP}/nodiff/cmp"
mkdir -p "${FAKE_HOME}/.config/nodiffdir/sub"
printf 'x\n' >"${FAKE_HOME}/.config/nodiffdir/sub/f"
backup_begin >/dev/null 2>&1
assert_rc 0 "dir backup works without diff/cmp" env PATH="${T_TMP}/nodiff:${PATH}" bash -c "source '${HERE}/../../lib/backup.sh'; BACKUP_DIR='${BACKUP_DIR}'; backup_path '${FAKE_HOME}/.config/nodiffdir'"

t_finish

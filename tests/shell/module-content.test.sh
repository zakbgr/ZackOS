#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Checks the real modules shipped in modules/ (kitty, zsh, fastfetch) against a fake $HOME.
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/shell/harness.sh
source "${HERE}/harness.sh"
# shellcheck source=lib/modules.sh
source "${HERE}/../../lib/modules.sh"

make_tmp
export NO_COLOR=1 ZACKOS_STATE_DIR="${T_TMP}/state" HOME="${T_TMP}/home" ZACKOS_APPLY=1
unset ZACKOS_MODULES_DIR
mkdir -p "${HOME}"

for m in kitty zsh fastfetch; do
    assert_rc 0 "module ${m} validates" mod_validate "${m}"
done

# Phase 3 scope: no Waybar/Rofi/Hyprland session deployment from these three modules.
for m in kitty zsh fastfetch; do
    assert_eq "0" "$(mod_files "${m}" | grep -c -E 'hypr|waybar|rofi|\.zshrc|\.zprofile|\.zshenv|/etc/|\.config/nvim')" "${m}: touches nothing out of scope"
done

assert_contains "$(cat "$(mod_dir)/kitty/files/.config/kitty/kitty.conf")" "include zackos-theme.conf" "kitty.conf includes the theme"

# fastfetch config is valid JSON once // comments are stripped
if command -v jq >/dev/null 2>&1; then
    assert_rc 0 "fastfetch config is valid JSON(C)" bash -c "grep -v '^[[:space:]]*//' '$(mod_dir)/fastfetch/files/.config/fastfetch/config.jsonc' | jq -e . >/dev/null"
fi

# zsh: syntax, sourcing in an isolated HOME, and it never creates/edits rc files
if command -v zsh >/dev/null 2>&1; then
    z="$(mod_dir)/zsh/files/.config/zackos/zsh"
    assert_rc 0 "zackos.zsh syntax" zsh -n "${z}/zackos.zsh"
    assert_rc 0 "zackos-theme.zsh syntax" zsh -n "${z}/zackos-theme.zsh"
    out="$(env -i HOME="${HOME}" PATH="${PATH}" ZDOTDIR="${HOME}" zsh -f -c "source '${z}/zackos.zsh'; print -r -- \"\${ZACKOS_FG_ACCENT}|\${HISTFILE}\"" 2>&1)"
    assert_eq "38;2;0;217;255|${HOME}/.local/state/zsh/history" "${out}" "zsh sourcing sets theme and history inside HOME"
    for rc in .zshrc .zprofile .zshenv .zlogin; do assert_no_path "${HOME}/${rc}" "sourcing created no ${rc}"; done
    rm -rf "${HOME}/.local"
fi

# install all three into a fake HOME, then roll back to exactly empty
before="$(cd "${HOME}" && find . | LC_ALL=C sort)"
mod_install kitty zsh fastfetch >/dev/null 2>&1
assert_eq "0" "$?" "install of the three modules"
assert_link "${HOME}/.config/kitty/kitty.conf" "$(mod_dir)/kitty/files/.config/kitty/kitty.conf"
assert_link "${HOME}/.config/fastfetch/config.jsonc" "$(mod_dir)/fastfetch/files/.config/fastfetch/config.jsonc"
assert_no_path "${HOME}/.zshrc" "install never creates .zshrc"
mod_rollback latest >/dev/null 2>&1
assert_eq "${before}" "$(cd "${HOME}" && find . | LC_ALL=C sort)" "rollback restores the empty HOME"

# a user's existing kitty.conf and zsh files are never replaced
mkdir -p "${HOME}/.config/kitty"
printf 'user kitty\n' >"${HOME}/.config/kitty/kitty.conf"
printf 'user zshrc\n' >"${HOME}/.zshrc"
mod_install kitty zsh fastfetch >/dev/null 2>&1
assert_eq "user kitty" "$(cat "${HOME}/.config/kitty/kitty.conf")" "user kitty.conf untouched"
assert_eq "user zshrc" "$(cat "${HOME}/.zshrc")" "user .zshrc untouched"
assert_link "${HOME}/.config/kitty/zackos-theme.conf" "$(mod_dir)/kitty/files/.config/kitty/zackos-theme.conf"

t_finish

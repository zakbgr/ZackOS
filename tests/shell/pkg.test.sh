#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/shell/harness.sh
source "${HERE}/harness.sh"
# shellcheck source=lib/pkg.sh
source "${HERE}/../../lib/pkg.sh"

make_tmp
use_fakebin
export NO_COLOR=1

# ---- the fakes are really first on PATH: no real sudo/dnf5 can be reached
assert_contains "$(command -v sudo)" "tests/fakebin" "sudo is the fake"
assert_contains "$(command -v dnf5)" "tests/fakebin" "dnf5 is the fake"

# ---- real manifest
assert_rc 0 "committed manifest is valid" pkg_validate
assert_eq "kitty
zsh
fastfetch" "$(pkg_select)" "default selection is core-terminal only"
assert_eq "dolphin" "$(pkg_select optional-dolphin)" "dolphin only when its group is asked for"
assert_eq "" "$(pkg_select hyprland-session)" "COPR candidates are not selectable"
assert_eq "" "$(pkg_select bar-launcher)" "waybar/rofi candidates are not selectable in Phase 3"
assert_eq "" "$(pkg_select editor)" "neovim candidate is not selectable"
assert_eq "fedora" "$(pkg_source waybar)" "waybar from fedora"
assert_eq "copr:lionheartp/Hyprland" "$(pkg_source hyprland)" "hyprland from the COPR"

# protected packages are all Fedora-sourced in the real manifest
for p in "${PKG_PROTECTED[@]}"; do
    assert_eq "fedora" "$(pkg_source "${p}" || echo MISSING)" "protected ${p} is fedora"
done
# default selection never contains a KDE package
assert_eq "no" "$(pkg_select | grep -qi 'dolphin\|kde' && echo yes || echo no)" "no KDE in default selection"

# ---- validator negative cases
tab=$'\t'
check_bad() { # description row [extra rows...]
    local desc="$1"
    shift
    printf '%s\n' "$@" >"${T_TMP}/bad.tsv"
    local rc=0
    ZACKOS_PACKAGES_FILE="${T_TMP}/bad.tsv" pkg_validate >/dev/null 2>&1 || rc=$?
    assert_eq "1" "${rc}" "validator rejects: ${desc}"
}
good="kitty${tab}fedora${tab}core-terminal${tab}no${tab}approved${tab}x"
printf '%s\n' "${good}" >"${T_TMP}/good.tsv"
assert_rc 0 "minimal good manifest" env ZACKOS_PACKAGES_FILE="${T_TMP}/good.tsv" bash -c "source '${HERE}/../../lib/pkg.sh'; pkg_validate"

check_bad "empty manifest" "# nothing"
check_bad "missing column" "kitty${tab}fedora${tab}core-terminal${tab}no${tab}approved"
check_bad "extra column" "${good}${tab}extra"
check_bad "protected package from COPR" "kitty${tab}copr:o/p${tab}hyprland-session${tab}no${tab}candidate${tab}x"
check_bad "waybar from COPR" "waybar${tab}copr:o/p${tab}hyprland-session${tab}no${tab}candidate${tab}x"
check_bad "-git package" "hyprland-git${tab}copr:o/p${tab}hyprland-session${tab}no${tab}candidate${tab}x"
check_bad "glob in name" "hypr*${tab}copr:o/p${tab}hyprland-session${tab}no${tab}candidate${tab}x"
check_bad "comma in name" "a,b${tab}fedora${tab}core-terminal${tab}no${tab}approved${tab}x"
check_bad "duplicate" "${good}" "${good}"
check_bad "COPR outside hyprland-session" "foo${tab}copr:o/p${tab}core-terminal${tab}no${tab}candidate${tab}x"
check_bad "approved COPR row while locked" "hyprland${tab}copr:o/p${tab}hyprland-session${tab}no${tab}approved${tab}x"
check_bad "optional row in default group" "foo${tab}fedora${tab}core-terminal${tab}yes${tab}approved${tab}x"
check_bad "unknown group" "foo${tab}fedora${tab}nonsense${tab}no${tab}approved${tab}x"
check_bad "bad status" "foo${tab}fedora${tab}core-terminal${tab}no${tab}maybe${tab}x"
check_bad "bad source" "foo${tab}rpmfusion${tab}core-terminal${tab}no${tab}approved${tab}x"
check_bad "bad optional" "foo${tab}fedora${tab}core-terminal${tab}sometimes${tab}approved${tab}x"
assert_rc 1 "unreadable manifest" env ZACKOS_PACKAGES_FILE="${T_TMP}/missing.tsv" bash -c "source '${HERE}/../../lib/pkg.sh'; pkg_validate"

# ---- classification with fake rpm/dnf5
printf 'kitty\nzsh\nfastfetch\n' >"${T_TMP}/installed"
printf 'kitty\tfedora\nzsh\tupdates\nfastfetch\tcopr:copr.fedorainfracloud.org:someone:thing\n' >"${T_TMP}/origins"
export FAKE_RPM_INSTALLED="${T_TMP}/installed" FAKE_DNF_ORIGINS="${T_TMP}/origins"
assert_eq "fedora" "$(pkg_state kitty)" "fedora origin"
assert_eq "fedora" "$(pkg_state zsh)" "updates counts as fedora"
assert_eq "copr" "$(pkg_state fastfetch)" "copr origin detected"
assert_eq "none" "$(pkg_state neovim)" "not installed"
printf 'kitty\n' >"${T_TMP}/installed"
: >"${T_TMP}/origins"
assert_eq "unknown" "$(pkg_state kitty)" "installed with unknown origin"
assert_eq "other" "$(dnf_origin_class rpmfusion-free)" "third-party repo is other"

# ---- plan actions
printf 'kitty\nfastfetch\n' >"${T_TMP}/installed"
printf 'kitty\tfedora\nfastfetch\tcopr:copr.fedorainfracloud.org:someone:thing\n' >"${T_TMP}/origins"
plan="$(pkg_plan "${PKG_DEFAULT_GROUPS[@]}")"
assert_contains "${plan}" $'kitty\tfedora\tok' "plan: kitty ok"
assert_contains "${plan}" $'zsh\tnone\tinstall' "plan: zsh install"
assert_contains "${plan}" $'fastfetch\tcopr\tconflict' "plan: COPR-origin protected package is a conflict"

# ---- name validation protects the query path
assert_rc 2 "invalid name refused" dnf_installed_origin 'kitty;rm -rf'
assert_rc 2 "glob refused" dnf_installed_origin 'kit*'

# ---- nothing mutating was ever called
assert_eq "no" "$(grep -qE '^dnf5 (install|upgrade|remove|copr)' "${FAKE_LOG}" && echo yes || echo no)" "no mutating dnf5 call"

t_finish

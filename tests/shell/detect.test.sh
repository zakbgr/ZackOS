#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/shell/harness.sh
source "${HERE}/harness.sh"
# shellcheck source=lib/detect.sh
source "${HERE}/../../lib/detect.sh"

make_tmp
export ZACKOS_ROOT="${T_TMP}/root"
mkdir -p "${ZACKOS_ROOT}/etc/systemd/system" "${ZACKOS_ROOT}/usr/share/wayland-sessions" "${ZACKOS_ROOT}/usr/share/xsessions"

# --- os-release
cat >"${ZACKOS_ROOT}/etc/os-release" <<'EOF'
NAME="Fedora Linux"
VERSION_ID=44
ID=fedora
EOF
assert_eq "fedora" "$(detect_distro_id)" "distro id"
assert_eq "44" "$(detect_fedora_version)" "fedora version"

printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"${ZACKOS_ROOT}/etc/os-release"
assert_eq "ubuntu" "$(detect_distro_id)" "non-fedora id"
assert_eq "none" "$(detect_fedora_version)" "no fedora version on ubuntu"

rm -f "${ZACKOS_ROOT}/etc/os-release"
assert_eq "unknown" "$(detect_distro_id)" "missing os-release"

# os-release is parsed, never executed
# shellcheck disable=SC2016  # the $( ) must stay literal: it is the attack string
printf 'ID=fedora\nVERSION_ID=44\nEVIL=$(touch %s/pwned)\n' "${T_TMP}" >"${ZACKOS_ROOT}/etc/os-release"
detect_fedora_version >/dev/null
assert_no_path "${T_TMP}/pwned" "os-release must not be executed"

# --- desktop
unset XDG_SESSION_DESKTOP
XDG_CURRENT_DESKTOP="GNOME" assert_eq "gnome" "$(XDG_CURRENT_DESKTOP=GNOME detect_desktop)" "GNOME"
assert_eq "kde" "$(XDG_CURRENT_DESKTOP=KDE detect_desktop)" "KDE"
assert_eq "hyprland" "$(XDG_CURRENT_DESKTOP=Hyprland detect_desktop)" "Hyprland"
assert_eq "gnome" "$(XDG_CURRENT_DESKTOP=ubuntu:GNOME detect_desktop)" "multi-valued picks known DE"
assert_eq "unknown" "$(XDG_CURRENT_DESKTOP='' detect_desktop)" "empty desktop"
assert_eq "kde" "$(XDG_CURRENT_DESKTOP='' XDG_SESSION_DESKTOP=KDE detect_desktop)" "fallback to XDG_SESSION_DESKTOP"
assert_eq "weirdwm" "$(XDG_CURRENT_DESKTOP='WeirdWM' detect_desktop)" "unknown name is lower-cased"
assert_eq "evilrm" "$(XDG_CURRENT_DESKTOP='evil;rm' detect_desktop)" "unsafe characters stripped"

# --- session type
assert_eq "wayland" "$(XDG_SESSION_TYPE=wayland detect_session_type)" "session type"
assert_eq "unknown" "$(unset XDG_SESSION_TYPE; detect_session_type)" "session type unset"

# --- display manager
dm() { ln -sfn "/usr/lib/systemd/system/$1" "${ZACKOS_ROOT}/etc/systemd/system/display-manager.service"; }
dm gdm.service
assert_eq "gdm" "$(detect_display_manager)" "gdm"
dm sddm.service
assert_eq "sddm" "$(detect_display_manager)" "sddm"
dm plasmalogin.service
assert_eq "plasma-login-manager" "$(detect_display_manager)" "plasma login manager"
dm greetd.service
assert_eq "greetd" "$(detect_display_manager)" "greetd"
dm mystery-dm.service
assert_eq "mystery-dm" "$(detect_display_manager)" "unknown DM reports raw unit"
rm -f "${ZACKOS_ROOT}/etc/systemd/system/display-manager.service"
assert_eq "unknown" "$(detect_display_manager)" "no DM link"
assert_eq "gdm" "$(ZACKOS_DM_UNIT=gdm.service detect_display_manager)" "override"

# --- sessions
assert_eq "" "$(detect_sessions wayland)" "no sessions"
touch "${ZACKOS_ROOT}/usr/share/wayland-sessions/gnome.desktop" "${ZACKOS_ROOT}/usr/share/wayland-sessions/hyprland.desktop"
touch "${ZACKOS_ROOT}/usr/share/xsessions/plasmax11.desktop"
assert_eq "gnome hyprland" "$(detect_sessions wayland)" "wayland sessions"
assert_eq "plasmax11" "$(detect_sessions x11)" "x11 sessions"
assert_rc 2 "invalid session kind" detect_sessions bogus

# --- summary has all keys and no side effects
sum="$(detect_summary)"
for key in distro_id fedora_version arch desktop session_type display_manager wayland_sessions x11_sessions has_hyprland has_dolphin has_dnf; do
    assert_contains "${sum}" "${key}=" "summary key ${key}"
done

t_finish

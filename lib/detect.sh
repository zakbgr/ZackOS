#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Read-only environment detection: Fedora version, desktop environment, session type,
# display manager. Nothing here changes the system or requires root.
#
# For tests, ZACKOS_ROOT can point at a fake filesystem root, and ZACKOS_DM_UNIT can
# override the display manager unit name.

[[ -n "${_ZACKOS_DETECT_LOADED:-}" ]] && return 0
_ZACKOS_DETECT_LOADED=1

_detect_root() { printf '%s' "${ZACKOS_ROOT:-}"; }

# detect_os_field <FIELD>: read a field from /etc/os-release without executing the file.
detect_os_field() {
    local field="${1:?field name required}" file value
    file="$(_detect_root)/etc/os-release"
    [[ -r "${file}" ]] || return 1
    value="$(sed -n "s/^${field}=//p" "${file}" | head -n 1)"
    value="${value#\"}"
    value="${value%\"}"
    printf '%s' "${value}"
}

detect_distro_id() { detect_os_field ID || printf 'unknown'; }

detect_fedora_version() {
    if [[ "$(detect_distro_id)" == "fedora" ]]; then
        detect_os_field VERSION_ID
    else
        printf 'none'
    fi
}

detect_arch() { uname -m; }

# detect_desktop: normalized desktop name, e.g. gnome, kde, hyprland, sway, unknown.
# Uses XDG_CURRENT_DESKTOP, then XDG_SESSION_DESKTOP. Empty (ssh, tty) gives "unknown".
detect_desktop() {
    local raw="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
    [[ -n "${raw}" ]] || {
        printf 'unknown'
        return 0
    }
    local token known
    local IFS=':'
    for token in ${raw}; do
        token="${token,,}"
        for known in gnome kde hyprland sway xfce cosmic budgie cinnamon mate lxqt; do
            if [[ "${token}" == "${known}" ]]; then
                printf '%s' "${known}"
                return 0
            fi
        done
    done
    # Not a known name: report the first token, lower-cased, with unsafe characters removed.
    token="${raw%%:*}"
    token="${token,,}"
    printf '%s' "${token//[^a-z0-9_-]/}"
}

detect_session_type() { printf '%s' "${XDG_SESSION_TYPE:-unknown}"; }

# detect_display_manager: normalized name of the enabled display manager, or "unknown".
detect_display_manager() {
    local unit="${ZACKOS_DM_UNIT:-}"
    if [[ -z "${unit}" ]]; then
        local link
        link="$(_detect_root)/etc/systemd/system/display-manager.service"
        if [[ -L "${link}" ]]; then
            unit="$(basename -- "$(readlink -- "${link}")")"
        elif [[ -z "${ZACKOS_ROOT:-}" ]] && command -v systemctl >/dev/null 2>&1; then
            unit="$(systemctl show display-manager.service --property=Id --value 2>/dev/null || true)"
        fi
    fi
    unit="${unit%.service}"
    case "${unit}" in
    "" | display-manager) printf 'unknown' ;;
    gdm | gdm3) printf 'gdm' ;;
    sddm) printf 'sddm' ;;
    lightdm) printf 'lightdm' ;;
    plasmalogin | plasma-login-manager | plasmalogin-*) printf 'plasma-login-manager' ;;
    greetd) printf 'greetd' ;;
    ly) printf 'ly' ;;
    cosmic-greeter) printf 'cosmic-greeter' ;;
    *) printf '%s' "${unit//[^A-Za-z0-9_.@-]/}" ;;
    esac
}

# detect_sessions <wayland|x11>: space-separated names of installed session files.
detect_sessions() {
    local kind="${1:?wayland or x11}" dir f out=()
    case "${kind}" in
    wayland) dir="$(_detect_root)/usr/share/wayland-sessions" ;;
    x11) dir="$(_detect_root)/usr/share/xsessions" ;;
    *) return 2 ;;
    esac
    if [[ -d "${dir}" ]]; then
        for f in "${dir}"/*.desktop; do
            [[ -e "${f}" ]] || continue
            out+=("$(basename -- "${f}" .desktop)")
        done
    fi
    printf '%s' "${out[*]:-}"
}

# detect_command <name>: "yes" or "no".
detect_command() {
    if command -v "${1:?command name required}" >/dev/null 2>&1; then
        printf 'yes'
    else
        printf 'no'
    fi
}

# detect_summary: key=value report, meant to be pasted back into a bug report or chat.
detect_summary() {
    printf 'distro_id=%s\n' "$(detect_distro_id)"
    printf 'fedora_version=%s\n' "$(detect_fedora_version)"
    printf 'arch=%s\n' "$(detect_arch)"
    printf 'desktop=%s\n' "$(detect_desktop)"
    printf 'session_type=%s\n' "$(detect_session_type)"
    printf 'display_manager=%s\n' "$(detect_display_manager)"
    printf 'wayland_sessions=%s\n' "$(detect_sessions wayland)"
    printf 'x11_sessions=%s\n' "$(detect_sessions x11)"
    printf 'has_hyprland=%s\n' "$(detect_command Hyprland)"
    printf 'has_dolphin=%s\n' "$(detect_command dolphin)"
    printf 'has_dnf=%s\n' "$(detect_command dnf)"
}

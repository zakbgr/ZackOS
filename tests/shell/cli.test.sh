#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# End-to-end tests of bin/zackos with fake dnf5/rpm/sudo/lspci. Real DNF5 behavior is covered by
# the Fedora 44 CI job (tests/dnf5), not here.
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/shell/harness.sh
source "${HERE}/harness.sh"
REPO="$(cd -P -- "${HERE}/../.." && pwd)"
ZACKOS="${REPO}/bin/zackos"

make_tmp
use_fakebin
export NO_COLOR=1 ZACKOS_TEST_EUID=1000
export ZACKOS_STATE_DIR="${T_TMP}/state" HOME="${T_TMP}/home" ZACKOS_ROOT="${T_TMP}/root"
unset ZACKOS_APPLY ZACKOS_DRY_RUN
mkdir -p "${HOME}" "${ZACKOS_ROOT}/etc/yum.repos.d"
printf 'ID=fedora\nVERSION_ID="44"\n' >"${ZACKOS_ROOT}/etc/os-release"
export FAKE_RPM_INSTALLED="${T_TMP}/rpm-installed" FAKE_DNF_ORIGINS="${T_TMP}/origins" FAKE_LSPCI="${T_TMP}/lspci"
: >"${FAKE_RPM_INSTALLED}"
: >"${FAKE_DNF_ORIGINS}"
printf '00:02.0 VGA compatible controller [0300]: Intel Corporation UHD Graphics 620 [8086:5917] (rev 07)\n' >"${FAKE_LSPCI}"

snap() { # everything a read-only command must not change
    (cd "${T_TMP}" && find home root state -printf '%p %y %m %l\n' 2>/dev/null | LC_ALL=C sort)
}
sudo_calls() { grep -c '^sudo ' "${FAKE_LOG}"; }
mutating_dnf() { grep -cE '^dnf5 (install|upgrade|remove|downgrade|copr|history|config-manager|swap|reinstall)' "${FAKE_LOG}"; }

# ---- help / unknown
assert_rc 0 "help" bash "${ZACKOS}" --help
assert_rc 1 "unknown command" bash "${ZACKOS}" frobnicate

# ---- read-only commands change nothing and call neither sudo nor a mutating dnf5
before="$(snap)"
out="$(bash "${ZACKOS}" doctor 2>&1)"
assert_rc 0 "doctor rc" bash "${ZACKOS}" doctor
bash "${ZACKOS}" plan >/dev/null 2>&1
bash "${ZACKOS}" status >/dev/null 2>&1
bash "${ZACKOS}" packages plan >/dev/null 2>&1
bash "${ZACKOS}" repo show-override >/dev/null 2>&1
bash "${ZACKOS}" repo audit >/dev/null 2>&1
assert_eq "${before}" "$(snap)" "doctor/plan/status/packages plan/repo are read-only"
assert_eq "0" "$(sudo_calls)" "read-only commands never call sudo"
assert_eq "0" "$(mutating_dnf)" "read-only commands never call a mutating dnf5 command"
assert_contains "${out}" "UHD Graphics 620" "doctor reports the GPU"
assert_contains "${out}" "COPR operations: locked" "doctor reports COPR locked"
assert_contains "${out}" "not enabled" "doctor reports the COPR as not enabled"
assert_contains "${out}" "NOT selectable in Phase 3" "doctor lists candidates as non-selectable"
assert_contains "${out}" "hyprland " "doctor lists hyprland as a candidate"
assert_contains "${out}" "nothing was changed" "doctor states it changed nothing"

# ---- doctor reports conflicts and a COPR repo file when present
mkdir -p "${HOME}/.config/kitty"
printf 'mine\n' >"${HOME}/.config/kitty/kitty.conf"
touch "${ZACKOS_ROOT}/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:lionheartp:Hyprland.repo"
out="$(bash "${ZACKOS}" doctor 2>&1)"
assert_contains "${out}" "conflict  kitty: ~/.config/kitty/kitty.conf" "doctor reports a config conflict"
assert_contains "${out}" "COPR repo file present" "doctor reports a present COPR repo file"
rm -r "${HOME}/.config" "${ZACKOS_ROOT}/etc/yum.repos.d/"*

# ---- dry-run is the default for install and rollback
before="$(snap)"
out="$(bash "${ZACKOS}" install kitty zsh fastfetch 2>&1)"
assert_eq "${before}" "$(snap)" "install without --apply changes nothing"
assert_contains "${out}" "would:" "dry-run install says what it would do"
bash "${ZACKOS}" rollback >/dev/null 2>&1
assert_eq "${before}" "$(snap)" "rollback without --apply changes nothing"

# ---- install --apply, idempotent, status, rollback
bash "${ZACKOS}" install kitty zsh fastfetch --apply >/dev/null 2>&1
assert_eq "0" "$?" "install --apply rc"
assert_link "${HOME}/.config/kitty/kitty.conf" "${REPO}/modules/kitty/files/.config/kitty/kitty.conf"
snap_installed="$(snap)"
bash "${ZACKOS}" install kitty zsh fastfetch --apply >/dev/null 2>&1
assert_eq "${snap_installed}" "$(snap)" "second install --apply is a no-op"
assert_contains "$(bash "${ZACKOS}" status 2>&1)" "ok" "status shows ok links"
bash "${ZACKOS}" rollback --apply >/dev/null 2>&1
bash "${ZACKOS}" rollback --apply >/dev/null 2>&1
assert_eq "0" "$?" "repeated rollback is fine"
assert_no_path "${HOME}/.config/kitty/kitty.conf" "rollback removed our link"
assert_eq "0" "$(sudo_calls)" "module install/rollback never use sudo"

# ---- apply preflight: wrong Fedora release, root, wrong distro
printf 'ID=fedora\nVERSION_ID="43"\n' >"${ZACKOS_ROOT}/etc/os-release"
assert_rc 2 "apply refused on Fedora 43" bash "${ZACKOS}" install kitty --apply
printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"${ZACKOS_ROOT}/etc/os-release"
assert_rc 2 "apply refused on non-Fedora" bash "${ZACKOS}" install kitty --apply
printf 'ID=fedora\nVERSION_ID="44"\n' >"${ZACKOS_ROOT}/etc/os-release"
assert_rc 2 "apply refused as root" env ZACKOS_TEST_EUID=0 bash "${ZACKOS}" install kitty --apply
assert_no_path "${HOME}/.config/kitty/kitty.conf" "refused runs changed nothing"

# ---- packages plan: default group only; dolphin is optional; hyprland is not selectable
out="$(bash "${ZACKOS}" packages plan 2>&1)"
assert_contains "${out}" "kitty" "plan lists kitty"
assert_contains "${out}" "action=install" "missing packages would be installed"
assert_eq "0" "$(grep -c -E 'dolphin|hyprland|uwsm|waybar|rofi|neovim' <<<"${out}")" "default plan has no optional/candidate packages"
assert_contains "$(bash "${ZACKOS}" packages plan --group optional-dolphin 2>&1)" "dolphin" "dolphin only on request"
assert_rc 1 "hyprland-session group is not selectable" bash "${ZACKOS}" packages plan --group hyprland-session
assert_rc 1 "unknown group rejected" bash "${ZACKOS}" packages plan --group nonsense
assert_rc 1 "stray argument rejected" bash "${ZACKOS}" packages plan hyprland

# ---- packages install: dry-run default; hyprland refused even with --apply
: >"${FAKE_LOG}"
bash "${ZACKOS}" packages install >/dev/null 2>&1
assert_eq "0" "$(sudo_calls)" "packages install without --apply calls no sudo"
export ZACKOS_PRIV_INPUT="${T_TMP}/answers"
printf 'yes\nyes\nyes\n' >"${ZACKOS_PRIV_INPUT}"
assert_rc 1 "hyprland install refused with --apply" bash "${ZACKOS}" packages install --group hyprland-session --apply
assert_rc 1 "candidate package names are not accepted as arguments" bash "${ZACKOS}" packages install hyprland --apply
assert_eq "0" "$(sudo_calls)" "no sudo for refused installs"

# ---- packages install --apply: one confirmation per package, exact argv, journal
: >"${FAKE_LOG}"
printf 'yes\nyes\nyes\n' >"${ZACKOS_PRIV_INPUT}"
bash "${ZACKOS}" packages install --apply >/dev/null 2>&1
assert_eq "3" "$(sudo_calls)" "three confirmed steps, three sudo calls"
assert_contains "$(grep '^sudo ' "${FAKE_LOG}")" "sudo dnf5 install -- kitty" "exact install command"
assert_eq "0" "$(grep '^sudo ' "${FAKE_LOG}" | grep -c -E ' -y|--assumeyes|copr|remove')" "no -y, no copr, no remove"
assert_eq "3" "$(grep -c $'\tok$' "${ZACKOS_STATE_DIR}/priv-journal.tsv")" "journal has three ok entries"

# declining stops further steps
: >"${FAKE_LOG}"
printf 'no\nyes\nyes\n' >"${ZACKOS_PRIV_INPUT}"
unset _ZACKOS_PRIV_FD
rc=0
bash "${ZACKOS}" packages install --apply >/dev/null 2>&1 || rc=$?
assert_eq "3" "${rc}" "declined step exits 3"
assert_eq "0" "$(sudo_calls)" "declined step runs nothing and stops the run"

# installed-from-COPR conflict is reported and never touched
printf 'kitty\n' >"${FAKE_RPM_INSTALLED}"
printf 'kitty\tcopr:copr.fedorainfracloud.org:lionheartp:Hyprland\n' >"${FAKE_DNF_ORIGINS}"
: >"${FAKE_LOG}"
printf 'yes\nyes\nyes\n' >"${ZACKOS_PRIV_INPUT}"
rc=0
out="$(bash "${ZACKOS}" packages install --apply 2>&1)" || rc=$?
assert_eq "1" "${rc}" "COPR-origin core package is a failure"
assert_contains "${out}" "Not touching it" "conflict explained"
assert_eq "0" "$(grep '^sudo ' "${FAKE_LOG}" | grep -c 'kitty')" "the conflicting package is never reinstalled"
assert_contains "$(bash "${ZACKOS}" repo audit 2>&1)" "VIOLATION" "audit flags the Fedora package that came from the COPR"

# ---- COPR enable/disable stay locked, in every mode
: >"${FAKE_LOG}"
for mode in "" "--apply"; do
    assert_rc 5 "repo enable locked ${mode}" bash "${ZACKOS}" repo enable ${mode}
    assert_rc 5 "repo disable locked ${mode}" bash "${ZACKOS}" repo disable ${mode}
done
assert_rc 5 "ZACKOS_ASSUME_YES does not unlock" env ZACKOS_ASSUME_YES=1 ZACKOS_APPLY=1 bash "${ZACKOS}" repo enable
assert_eq "0" "$(sudo_calls)" "locked operations call no sudo"
assert_eq "0" "$(mutating_dnf)" "locked operations call no mutating dnf5 command"
assert_eq "0" "$(find "${ZACKOS_ROOT}/etc/yum.repos.d" -type f | wc -l)" "no repo file created"

# ---- the override preview is generated, not written
out="$(bash "${ZACKOS}" repo show-override 2>&1)"
assert_contains "${out}" "includepkgs=" "override has includepkgs"
assert_contains "${out}" "excludepkgs=*-git" "override excludes -git packages"
assert_no_path "${ZACKOS_ROOT}/etc/dnf" "preview wrote nothing under /etc/dnf"

t_finish

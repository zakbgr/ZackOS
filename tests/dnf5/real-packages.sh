#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Fedora 44 CI: the shipped modules and the CLI against the REAL Fedora kitty, zsh and fastfetch,
# real dnf5 (read-only commands) and a real unprivileged user. Runs only in a fedora:44 container.
set -u
# shellcheck source=tests/dnf5/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
ci_guard

echo "== tooling and packages (real Fedora 44 repositories)"
dnf5 --version | head -2
dnf5 -y install kitty zsh fastfetch jq util-linux >/dev/null 2>&1 || {
    record "R0 install kitty zsh fastfetch from Fedora" FAIL
    finish "Fedora 44 real packages"
}
record "R0 install kitty zsh fastfetch from Fedora" PASS "$(rpm -q kitty zsh fastfetch | tr '\n' ' ')"

echo
echo "== R1-probe: which dnf5 query/info fields report the origin of an installed package?"
for tag in from_repo repoid reponame; do
    echo "-- queryformat %{${tag}}"
    dnf5 repoquery --installed --queryformat "%{name}\t%{${tag}}\n" kitty 2>&1 | head -5 | sed 's/^/   | /'
done
echo "-- repoquery --info (origin lines)"
dnf5 repoquery --installed --info kitty 2>&1 | grep -iE 'repo|from|origin' | head -8 | sed 's/^/   | /'
echo "-- dnf5 info --installed"
dnf5 info --installed kitty 2>&1 | grep -iE 'repo|from|origin' | head -8 | sed 's/^/   | /'
echo "-- dnf5 history info last"
dnf5 history info 2>&1 | head -12 | sed 's/^/   | /'

echo
echo "== R1 origin classification against real repository IDs"
for p in kitty zsh fastfetch; do
    o="$( (source "${REPO_ROOT}/lib/dnf.sh"; dnf_installed_origin "${p}") )"
    c="$( (source "${REPO_ROOT}/lib/dnf.sh"; dnf_origin_class "${o}") )"
    echo "   ${p}: from_repo='${o}' class='${c}'"
    if [[ "${c}" == "fedora" ]]; then record "R1 ${p} origin is fedora" PASS "(${o})"; else record "R1 ${p} origin is fedora" FAIL "(from_repo='${o}': extend dnf_origin_class or fix the query tag)"; fi
done

echo
echo "== R2 Dolphin footprint on a GNOME-less container (informational, nothing installed)"
dnf5 -y --assumeno install dolphin 2>&1 | tail -15 | sed 's/^/   | /'
record "R2 dolphin dependency footprint printed" PASS "(informational: see log)"

echo
echo "== R3 modules and CLI as an unprivileged user"
id zuser >/dev/null 2>&1 || useradd -m zuser
rm -rf /home/zuser/zackos
cp -a "${REPO_ROOT}" /home/zuser/zackos
chown -R zuser:zuser /home/zuser
as_user() { runuser -u zuser -- env HOME=/home/zuser ZACKOS_STATE_DIR=/home/zuser/.local/state/zackos NO_COLOR=1 "$@"; }
Z=/home/zuser/zackos/bin/zackos

out="$(as_user bash "${Z}" doctor 2>&1)"
printf '%s\n' "${out//$'\n'/$'\n'   | }" | sed '1s/^/   | /'
if grep -q 'nothing was changed' <<<"${out}" && grep -q 'COPR operations: locked' <<<"${out}"; then record "R3a doctor against real dnf5 (read-only)" PASS; else record "R3a doctor against real dnf5 (read-only)" FAIL; fi
if grep -qE '^(kitty|zsh|fastfetch) +state=fedora +action=ok' <<<"${out}"; then record "R3b doctor classifies the three packages as fedora/ok" PASS; else record "R3b doctor classifies the three packages as fedora/ok" FAIL; fi

as_user bash "${Z}" packages install >/dev/null 2>&1; rc=$?
if ((rc == 0)); then record "R3c packages install dry-run is harmless" PASS; else record "R3c packages install dry-run is harmless" FAIL "rc=${rc}"; fi
as_user bash "${Z}" repo enable >/dev/null 2>&1; rc=$?
if ((rc == 5)) && ! ls /etc/yum.repos.d/*copr* >/dev/null 2>&1; then record "R3d repo enable is locked and creates no repo file" PASS; else record "R3d repo enable is locked and creates no repo file" FAIL "rc=${rc}"; fi

as_user bash "${Z}" install kitty zsh fastfetch --apply >/dev/null 2>&1; rc=$?
if ((rc == 0)); then record "R3e install --apply into the user's HOME" PASS; else record "R3e install --apply into the user's HOME" FAIL "rc=${rc}"; fi

echo
echo "== R4 config validation with the real programs"
cfg=/home/zuser/.config
out="$(as_user timeout 60 fastfetch -c "${cfg}/fastfetch/config.jsonc" --pipe 2>&1)"; rc=$?
if ((rc == 0)) && [[ -n "${out}" ]]; then record "R4a fastfetch accepts the ZackOS config" PASS; else record "R4a fastfetch accepts the ZackOS config" FAIL "rc=${rc}: ${out%%$'\n'*}"; fi
printf '{ "modules": [ \n' >/tmp/broken.jsonc
as_user timeout 60 fastfetch -c /tmp/broken.jsonc --pipe >/dev/null 2>&1; rc=$?
if ((rc != 0)); then record "R4b control: fastfetch rejects a broken config" PASS; else record "R4b control: fastfetch rejects a broken config" FAIL "validation proves nothing"; fi

kitty_check() { # <config file>: kitty prints "Ignoring ..." lines for config it cannot use
    as_user timeout 60 kitty +runpy "from kitty.config import load_config; b=[]; load_config('$1', accumulate_bad_lines=b); print('BAD', len(b))" 2>&1 | tail -5
}
printf 'bogus_option_zackos_ci 1\n' >/tmp/kitty-bad.conf
chmod a+r /tmp/kitty-bad.conf
good="$(kitty_check "${cfg}/kitty/kitty.conf")"
bad="$(kitty_check /tmp/kitty-bad.conf)"
echo "   good:    ${good}"
echo "   control: ${bad}"
if ! grep -qiE 'ignoring|^BAD [1-9]' <<<"${bad}"; then
    record "R4c kitty parses the ZackOS config" SKIP "control config was not flagged, so nothing is claimed"
elif grep -qiE 'ignoring|invalid|error|traceback' <<<"${good}"; then
    record "R4c kitty parses the ZackOS config" FAIL "${good}"
else
    record "R4c kitty parses the ZackOS config" PASS "(a bogus option IS flagged; the ZackOS config produces no warnings)"
fi

z=/home/zuser/.config/zackos/zsh
if as_user zsh -n "${z}/zackos.zsh" && as_user zsh -n "${z}/zackos-theme.zsh"; then record "R4d zsh syntax of both files" PASS; else record "R4d zsh syntax of both files" FAIL; fi
out="$(as_user env -i HOME=/home/zuser PATH="${PATH}" zsh -f -c "source ${z}/zackos.zsh; print -r -- \"\${ZACKOS_FG_ACCENT}\"" 2>&1)"
if [[ "${out}" == "38;2;0;217;255" ]]; then record "R4e zsh sources the file and sets the palette" PASS; else record "R4e zsh sources the file and sets the palette" FAIL "${out}"; fi
# Fedora's zsh package ships /etc/skel/.zshrc and .zprofile, copied by useradd. ZackOS must not
# have modified them: they must still equal the skeleton (or be absent if the skeleton lacks them).
zrc_ok=1
for f in .zshrc .zprofile .zshenv; do
    if [[ -e "/etc/skel/${f}" ]]; then [[ "$(sha256sum <"/etc/skel/${f}")" == "$(sha256sum <"/home/zuser/${f}")" ]] || zrc_ok=0; else [[ ! -e "/home/zuser/${f}" ]] || zrc_ok=0; fi
done
if ((zrc_ok)); then record "R4f zsh rc files untouched (equal the distro skeleton)" PASS; else record "R4f zsh rc files untouched (equal the distro skeleton)" FAIL; fi
shell_before="$(getent passwd zuser | cut -d: -f7)"

echo
echo "== R5 rollback leaves nothing behind"
as_user bash "${Z}" rollback --apply >/dev/null 2>&1
as_user bash "${Z}" rollback --apply >/dev/null 2>&1; rc=$?
left="$(find /home/zuser/.config -mindepth 1 2>/dev/null | head -5)"
if ((rc == 0)) && [[ -z "${left}" ]]; then record "R5a rollback twice: clean and idempotent" PASS; else record "R5a rollback twice: clean and idempotent" FAIL "rc=${rc} left: ${left}"; fi
if [[ "$(getent passwd zuser | cut -d: -f7)" == "${shell_before}" ]]; then record "R5b login shell unchanged" PASS; else record "R5b login shell unchanged" FAIL; fi

echo
echo "== R6 the full local suite on Fedora 44 (bash/python versions differ from CI Ubuntu)"
dnf5 -y install python3 git ShellCheck >/dev/null 2>&1
if (cd /home/zuser/zackos && as_user bash tests/run.sh >/tmp/suite.out 2>&1); then record "R6 tests/run.sh on Fedora 44" PASS "$(grep -c passed /tmp/suite.out) shell suites"; else record "R6 tests/run.sh on Fedora 44" FAIL; grep -nE "FAIL|SC[0-9]+|Traceback|Error|error" /tmp/suite.out | head -40; fi

finish "Fedora 44 real packages and CLI"

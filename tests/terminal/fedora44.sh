#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Fedora 44 CI, terminal experience: the shipped Fastfetch, Zsh prompt and Kitty files against the
# REAL Fedora fastfetch, zsh and kitty, as an unprivileged user. This is not a package-management
# test: dnf5 is used only to put the three programs into the disposable container. Runs only
# inside a fedora:44 container (see tests/dnf5/common.sh for the guard).
set -u
# shellcheck source=tests/dnf5/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../dnf5/common.sh"
ci_guard

echo "== tooling (disposable container only)"
dnf5 -y install kitty zsh fastfetch git util-linux >/dev/null 2>&1 || {
    record "T0 install kitty zsh fastfetch git" FAIL
    finish "Fedora 44 terminal experience"
}
record "T0 install kitty zsh fastfetch git" PASS "$(rpm -q kitty zsh fastfetch git | tr '\n' ' ')"

id tuser >/dev/null 2>&1 || useradd -m tuser
rm -rf /home/tuser/zackos
cp -a "${REPO_ROOT}" /home/tuser/zackos
chown -R tuser:tuser /home/tuser
as_user() { runuser -u tuser -- env HOME=/home/tuser NO_COLOR=1 "$@"; }
M=/home/tuser/zackos/modules

echo
echo "== T1 Fastfetch (real $(fastfetch --version 2>&1 | head -1))"
cfg="${M}/fastfetch/files/.config/fastfetch/config.jsonc"
out="$(as_user timeout 60 fastfetch -c "${cfg}" --pipe 2>&1)"; rc=$?
printf '%s\n' "${out}" | sed 's/^/   | /'
if ((rc == 0)) && [[ -n "${out}" ]]; then record "T1a fastfetch accepts the ZackOS config" PASS; else record "T1a fastfetch accepts the ZackOS config" FAIL "rc=${rc}: ${out%%$'\n'*}"; fi
if grep -q 'Fedora' <<<"${out}"; then record "T1b os module still reports Fedora" PASS; else record "T1b os module still reports Fedora" FAIL; fi
if grep -q 'ZackOS.*Matrix Edition' <<<"${out}"; then record "T1c ZackOS Matrix Edition line is shown" PASS; else record "T1c ZackOS Matrix Edition line is shown" FAIL; fi
# --pipe turns the logo off, so draw it once with --pipe false and strip the escapes.
logo="$(as_user timeout 60 fastfetch -c "${cfg}" --pipe false 2>&1 | sed -e $'s/\x1b\\[[0-9;?]*[A-Za-z]//g')"
if grep -q 'ZZZZZZZZ' <<<"${logo}"; then record "T1d the ZackOS logo is drawn" PASS; else record "T1d the ZackOS logo is drawn" FAIL "logo marker not found"; printf '%s\n' "${logo}" | head -20 | sed 's/^/   | /'; fi
raw="$(as_user timeout 60 fastfetch -c "${cfg}" --pipe false 2>&1)"
if grep -q $'\x1b\\[38;2;0;217;255m' <<<"${raw}"; then record "T1e palette cyan reaches the output" PASS; else record "T1e palette cyan reaches the output" FAIL; fi

# Controls: validation proves nothing unless Fastfetch rejects bad input.
printf '{ "modules": [ \n' >/tmp/ff-broken.jsonc
printf '{ "logo": { "type": "data", "source": "x", "zackos_bogus_property": 1 }, "modules": ["os"] }\n' >/tmp/ff-unknown.jsonc
printf '{ "modules": [ { "type": "custom", "format": "x", "zackos_bogus_property": 1 } ] }\n' >/tmp/ff-unknown-module.jsonc
chmod a+r /tmp/ff-*.jsonc
as_user timeout 60 fastfetch -c /tmp/ff-broken.jsonc --pipe >/dev/null 2>&1; rc=$?
if ((rc != 0)); then record "T1f control: broken JSON is rejected" PASS; else record "T1f control: broken JSON is rejected" FAIL "validation proves nothing"; fi
for f in ff-unknown ff-unknown-module; do
    msg="$(as_user timeout 60 fastfetch -c "/tmp/${f}.jsonc" --pipe 2>&1)"; rc=$?
    echo "   ${f}: rc=${rc} ${msg%%$'\n'*}"
    if ((rc != 0)) || grep -qiE 'unknown|invalid|unsupported|error' <<<"${msg}"; then
        record "T1g control: ${f} property is flagged" PASS "(so the ZackOS config using none is meaningful)"
    else
        record "T1g control: ${f} property is flagged" SKIP "fastfetch ignores unknown properties; acceptance of the ZackOS config proves syntax only"
    fi
done

echo
echo "== T2 Zsh prompt (real zsh $(zsh --version | cut -d' ' -f2), real git $(git --version | cut -d' ' -f3))"
z="${M}/zsh/files/.config/zackos/zsh"
if as_user zsh -n "${z}/prompt.zsh" && as_user zsh -n "${z}/zackos.zsh"; then record "T2a zsh -n on prompt.zsh and zackos.zsh" PASS; else record "T2a zsh -n on prompt.zsh and zackos.zsh" FAIL; fi
if (cd /home/tuser/zackos && as_user bash tests/shell/zsh-prompt.test.sh >/tmp/prompt.out 2>&1); then
    record "T2b prompt test suite with Fedora's zsh and git" PASS "$(tail -1 /tmp/prompt.out | tr -s ' ')"
else
    record "T2b prompt test suite with Fedora's zsh and git" FAIL
    sed 's/^/   | /' /tmp/prompt.out | tail -30
fi
# Sourcing must leave the user's startup files exactly as the distro skeleton made them.
zrc_ok=1
for f in .zshrc .zprofile .zshenv; do
    if [[ -e "/etc/skel/${f}" ]]; then [[ "$(sha256sum <"/etc/skel/${f}")" == "$(sha256sum <"/home/tuser/${f}")" ]] || zrc_ok=0; else [[ ! -e "/home/tuser/${f}" ]] || zrc_ok=0; fi
done
as_user zsh -f -i -c "source ${z}/zackos.zsh" >/dev/null 2>&1
for f in .zshrc .zprofile .zshenv; do
    if [[ -e "/etc/skel/${f}" ]]; then [[ "$(sha256sum <"/etc/skel/${f}")" == "$(sha256sum <"/home/tuser/${f}")" ]] || zrc_ok=0; else [[ ! -e "/home/tuser/${f}" ]] || zrc_ok=0; fi
done
if ((zrc_ok)); then record "T2c sourcing leaves rc files equal to the skeleton" PASS; else record "T2c sourcing leaves rc files equal to the skeleton" FAIL; fi
if [[ "$(getent passwd tuser | cut -d: -f7)" == "/bin/bash" ]]; then record "T2d login shell not changed" PASS; else record "T2d login shell not changed" FAIL "$(getent passwd tuser | cut -d: -f7)"; fi

echo
echo "== T3 Kitty (real $(kitty --version 2>&1 | head -1))"
kitty_check() { # <config file>
    as_user timeout 60 kitty +runpy "from kitty.config import load_config; b=[]; load_config('$1', accumulate_bad_lines=b); print('BAD', len(b)); [print(x) for x in b]" 2>&1 | tail -8
}
printf 'bogus_option_zackos_ci 1\n' >/tmp/kitty-bad.conf
chmod a+r /tmp/kitty-bad.conf
bad="$(kitty_check /tmp/kitty-bad.conf)"
echo "   control: ${bad//$'\n'/ | }"
for f in kitty.conf zackos-theme.conf; do
    good="$(kitty_check "${M}/kitty/files/.config/kitty/${f}")"
    echo "   ${f}: ${good//$'\n'/ | }"
    if ! grep -qE '^BAD [1-9]' <<<"${bad}"; then
        record "T3 kitty parses ${f}" SKIP "control config was not flagged, so nothing is claimed"
    elif grep -qE '^BAD 0' <<<"${good}" && ! grep -qiE 'traceback|error' <<<"${good}"; then
        record "T3 kitty parses ${f}" PASS "(a bogus option IS flagged; ${f} has no bad lines)"
    else
        record "T3 kitty parses ${f}" FAIL "${good//$'\n'/ | }"
    fi
done

echo
echo "== T4 generated files are reproducible on Fedora's python"
dnf5 -y install python3 >/dev/null 2>&1
if (cd /home/tuser/zackos && as_user python3 scripts/render-theme.py --check >/tmp/render.out 2>&1); then record "T4 render-theme.py --check" PASS; else record "T4 render-theme.py --check" FAIL; sed 's/^/   | /' /tmp/render.out | tail -10; fi

finish "Fedora 44 terminal experience"
